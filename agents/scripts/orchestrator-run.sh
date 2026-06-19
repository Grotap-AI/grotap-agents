#!/bin/bash
# orchestrator-run.sh — SSH entrypoint invoked by the central LangGraph
# orchestrator (platform/orchestrator). It runs ONE task attempt in an isolated
# git worktree using Claude CLI headless, validates the result, pushes the
# branch, and prints a single JSON result line on stdout that the orchestrator
# parses. All human-readable logging goes to the log file / stderr so it never
# pollutes the JSON result line.
#
# Invoked over SSH as the `agent` user (claude auth + git creds + repos live in
# /home/agent). Uses python3 for JSON (no jq dependency — jq isn't on the fleet).
#
# Modes:
#   (default)         read task JSON on stdin → execute attempt → push branch
#   --merge           read {case_id,branch} on stdin → merge branch to master
#
# Task JSON (stdin):
#   {case_id, task_number, branch, title, context, requirements,
#    complexity, priority, attempt, prior_errors[]}
#
# Result JSON (last stdout line):
#   {"status":"success|failed","branch":"...","exit_code":N,
#    "errors":"...","summary":"...","tokens":N}
#
# This is ADDITIVE — it does not replace the bash coordinator. The orchestrator
# calls it directly; the legacy self-dispatch loop is untouched.
set -uo pipefail

# This script runs non-interactively over SSH, so login-shell env (where the
# fleet defines ANTHROPIC_API_KEY and other creds) is NOT loaded. Source it
# explicitly or Claude CLI fails with "Not logged in". Guard -u while sourcing.
set +u
for envf in "$HOME/.env" "$HOME/.profile" "$HOME/.bashrc"; do
  if [ -f "$envf" ]; then set -a; . "$envf" >/dev/null 2>&1 || true; set +a; fi
  [ -n "${ANTHROPIC_API_KEY:-}" ] && break
done
set -u

PLATFORM_DIR="$HOME/grotap-platform"
WORKTREE_ROOT="$HOME/worktrees"
LOG="$HOME/logs/orchestrator-run.log"
mkdir -p "$HOME/logs" "$WORKTREE_ROOT"

log() { echo "[$(date -u +%H:%M:%S)] $*" >> "$LOG"; }

# Emit the machine-readable result line and exit. python3 handles JSON escaping.
emit() {
  python3 -c '
import sys, json
status, branch, code, errors, summary, tokens = sys.argv[1:7]
print(json.dumps({"status": status, "branch": branch, "exit_code": int(code),
                  "errors": errors, "summary": summary, "tokens": int(tokens)}))
' "$1" "$2" "$3" "$4" "$5" "$6"
  exit 0
}

PAYLOAD="$(cat)"

# ── Ensure platform repo exists and is current ───────────────────────────────
ensure_repo() {
  if [ ! -d "$PLATFORM_DIR/.git" ]; then
    log "Cloning grotap-platform..."
    git clone https://github.com/Grotap-AI/grotap-platform.git "$PLATFORM_DIR" >> "$LOG" 2>&1
  fi
  cd "$PLATFORM_DIR" || return 1
  git fetch origin master --quiet >> "$LOG" 2>&1
}

# ── Merge mode ───────────────────────────────────────────────────────────────
if [ "${1:-}" = "--merge" ]; then
  BRANCH="$(printf '%s' "$PAYLOAD" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("branch",""))')"
  ensure_repo || { echo '{"merged": false, "error": "repo unavailable"}'; exit 1; }
  log "Merging $BRANCH → master"
  git checkout master --quiet >> "$LOG" 2>&1
  git pull origin master --quiet >> "$LOG" 2>&1
  if git merge --no-ff "origin/$BRANCH" -m "merge: $BRANCH (orchestrator-approved)" >> "$LOG" 2>&1; then
    git push origin master >> "$LOG" 2>&1
    echo '{"merged": true}'
    exit 0
  else
    git merge --abort >> "$LOG" 2>&1 || true
    echo '{"merged": false, "error": "merge conflict"}'
    exit 1
  fi
fi

# ── Execute mode — parse task fields from the payload ────────────────────────
eval "$(printf '%s' "$PAYLOAD" | python3 -c '
import sys, json, shlex
d = json.load(sys.stdin)
def g(k, default=""):
    v = d.get(k, default)
    return default if v is None else v
print("CASE_ID="      + shlex.quote(str(g("case_id"))))
print("BRANCH="       + shlex.quote(str(g("branch"))))
print("TITLE="        + shlex.quote(str(g("title"))))
print("CONTEXT="      + shlex.quote(str(g("context"))))
print("REQUIREMENTS=" + shlex.quote(str(g("requirements"))))
print("ATTEMPT="      + shlex.quote(str(g("attempt", 1))))
print("PRIOR_ERRORS=" + shlex.quote("\n---\n".join(d.get("prior_errors") or [])))
')"

log "=== Execute case=$CASE_ID branch=$BRANCH attempt=$ATTEMPT ==="

ensure_repo || emit "failed" "$BRANCH" 1 "Platform repo unavailable" "Could not clone/fetch grotap-platform" 0

# Fresh worktree per attempt (idempotent: remove a stale one first).
WT="$WORKTREE_ROOT/${CASE_ID}"
git worktree remove --force "$WT" >> "$LOG" 2>&1 || true
git branch -D "$BRANCH" >> "$LOG" 2>&1 || true
if ! git worktree add -b "$BRANCH" "$WT" origin/master >> "$LOG" 2>&1; then
  emit "failed" "$BRANCH" 1 "Could not create worktree/branch" "git worktree add failed" 0
fi
cd "$WT" || emit "failed" "$BRANCH" 1 "Worktree missing" "cd into worktree failed" 0

# ── Build the Claude CLI prompt ──────────────────────────────────────────────
RETRY_BLOCK=""
if [ "$ATTEMPT" -gt 1 ] && [ -n "$PRIOR_ERRORS" ]; then
  RETRY_BLOCK="

## This is retry attempt $ATTEMPT. The previous attempt(s) failed. Fix these issues:
$PRIOR_ERRORS"
fi

PROMPT="You are an autonomous engineer working in an isolated git worktree on the grotap-platform repo.

# Task: $TITLE

## Context
$CONTEXT

## Requirements
$REQUIREMENTS
$RETRY_BLOCK

## Rules
- Follow the repo CLAUDE.md and agents/GLOBAL.md rules exactly.
- Make the minimal correct change. Commit your work with git (do NOT push — the runner pushes).
- Before finishing, validate: run 'npx tsc --noEmit' in any frontend/TS package you changed, and 'python3 -m py_compile' on any backend .py file you changed.
- If you cannot complete the task, explain why clearly."

# ── Run Claude CLI headless ──────────────────────────────────────────────────
CLAUDE_OUT="$(claude -p "$PROMPT" --output-format json --dangerously-skip-permissions 2>>"$LOG")"
CLAUDE_RC=$?

# Parse claude's JSON result → tab-separated: is_error, result, input_tok, output_tok
CLAUDE_PARSED="$(printf '%s' "$CLAUDE_OUT" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("true\t\t0\t0"); sys.exit(0)
is_error = str(d.get("is_error", True)).lower()
result = (d.get("result") or "")[:1000].replace("\n", " ").replace("\t", " ")
u = d.get("usage") or {}
print("\t".join([is_error, result, str(u.get("input_tokens", 0) or 0), str(u.get("output_tokens", 0) or 0)]))
' 2>/dev/null)"
IFS=$'\t' read -r IS_ERROR RESULT_TEXT IN_TOK OUT_TOK <<< "$CLAUDE_PARSED"
TOKENS=$(( ${IN_TOK:-0} + ${OUT_TOK:-0} ))

if [ "$CLAUDE_RC" -ne 0 ] || [ "${IS_ERROR:-true}" = "true" ]; then
  emit "failed" "$BRANCH" "$CLAUDE_RC" "Claude CLI error: $RESULT_TEXT" "Agent run failed" "$TOKENS"
fi

# ── Validate ─────────────────────────────────────────────────────────────────
VALID_ERR=""
CHANGED="$(git diff --name-only origin/master 2>/dev/null; git diff --cached --name-only 2>/dev/null)"

if echo "$CHANGED" | grep -q '^frontend/' && [ -f frontend/package.json ]; then
  log "Validating frontend tsc..."
  if ! (cd frontend && npx tsc --noEmit >> "$LOG" 2>&1); then
    VALID_ERR="frontend tsc --noEmit failed"
  fi
fi
if echo "$CHANGED" | grep -q '^agent-worker/' && [ -f agent-worker/package.json ]; then
  log "Validating agent-worker tsc..."
  if ! (cd agent-worker && npx tsc --noEmit >> "$LOG" 2>&1); then
    VALID_ERR="${VALID_ERR:+$VALID_ERR; }agent-worker tsc --noEmit failed"
  fi
fi
if echo "$CHANGED" | grep -q '^orchestrator/' && [ -f orchestrator/package.json ]; then
  log "Validating orchestrator tsc..."
  if ! (cd orchestrator && npx tsc --noEmit >> "$LOG" 2>&1); then
    VALID_ERR="${VALID_ERR:+$VALID_ERR; }orchestrator tsc --noEmit failed"
  fi
fi
while IFS= read -r pyf; do
  [ -z "$pyf" ] && continue
  if ! python3 -m py_compile "$pyf" >> "$LOG" 2>&1; then
    VALID_ERR="${VALID_ERR:+$VALID_ERR; }py_compile failed: $pyf"
  fi
done < <(echo "$CHANGED" | grep '\.py$')

# Did the agent actually produce committed changes?
if ! git rev-parse --verify HEAD >/dev/null 2>&1 || [ -z "$(git log origin/master..HEAD --oneline 2>/dev/null)" ]; then
  emit "failed" "$BRANCH" 1 "No commits produced on $BRANCH" "Agent made no committed changes" "$TOKENS"
fi

if [ -n "$VALID_ERR" ]; then
  emit "failed" "$BRANCH" 1 "$VALID_ERR" "Validation failed" "$TOKENS"
fi

# ── Push branch (orchestrator decides on merge later, after human gate) ──────
if ! git push -u origin "$BRANCH" --force-with-lease >> "$LOG" 2>&1; then
  emit "failed" "$BRANCH" 1 "git push failed" "Could not push branch" "$TOKENS"
fi

log "=== Success case=$CASE_ID branch=$BRANCH tokens=$TOKENS ==="
emit "success" "$BRANCH" 0 "" "$RESULT_TEXT" "$TOKENS"
