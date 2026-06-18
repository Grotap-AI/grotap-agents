#!/bin/bash
# orchestrator-run.sh — SSH entrypoint invoked by the central LangGraph
# orchestrator (platform/orchestrator). It runs ONE task attempt in an isolated
# git worktree using Claude CLI headless, validates the result, pushes the
# branch, and prints a single JSON result line on stdout that the orchestrator
# parses. All human-readable logging goes to the log file / stderr so it never
# pollutes the JSON result line.
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

PLATFORM_DIR="/home/agent/grotap-platform"
WORKTREE_ROOT="/home/agent/worktrees"
LOG="/home/agent/logs/orchestrator-run.log"
mkdir -p /home/agent/logs "$WORKTREE_ROOT"

log() { echo "[$(date -u +%H:%M:%S)] $*" >> "$LOG"; }

# Emit the machine-readable result line and exit. Strings are JSON-escaped via jq.
emit() {
  local status="$1" branch="$2" code="$3" errors="$4" summary="$5" tokens="$6"
  jq -cn \
    --arg status "$status" --arg branch "$branch" --argjson exit_code "$code" \
    --arg errors "$errors" --arg summary "$summary" --argjson tokens "$tokens" \
    '{status:$status,branch:$branch,exit_code:$exit_code,errors:$errors,summary:$summary,tokens:$tokens}'
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
  BRANCH="$(echo "$PAYLOAD" | jq -r '.branch')"
  ensure_repo || { echo '{"merged":false,"error":"repo unavailable"}'; exit 1; }
  log "Merging $BRANCH → master"
  git checkout master --quiet >> "$LOG" 2>&1
  git pull origin master --quiet >> "$LOG" 2>&1
  if git merge --no-ff "origin/$BRANCH" -m "merge: $BRANCH (orchestrator-approved)" >> "$LOG" 2>&1; then
    git push origin master >> "$LOG" 2>&1
    echo '{"merged":true}'
    exit 0
  else
    git merge --abort >> "$LOG" 2>&1 || true
    echo '{"merged":false,"error":"merge conflict"}'
    exit 1
  fi
fi

# ── Execute mode ─────────────────────────────────────────────────────────────
CASE_ID="$(echo "$PAYLOAD" | jq -r '.case_id')"
BRANCH="$(echo "$PAYLOAD" | jq -r '.branch')"
TITLE="$(echo "$PAYLOAD" | jq -r '.title')"
CONTEXT="$(echo "$PAYLOAD" | jq -r '.context')"
REQUIREMENTS="$(echo "$PAYLOAD" | jq -r '.requirements')"
ATTEMPT="$(echo "$PAYLOAD" | jq -r '.attempt // 1')"
PRIOR_ERRORS="$(echo "$PAYLOAD" | jq -r '(.prior_errors // []) | join("\n---\n")')"

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
- Before finishing, validate: run 'npx tsc --noEmit' in any frontend/TS package you changed, and 'python -m py_compile' on any backend .py file you changed.
- If you cannot complete the task, explain why clearly."

# ── Run Claude CLI headless ──────────────────────────────────────────────────
CLAUDE_OUT="$(claude -p "$PROMPT" --output-format json --dangerously-skip-permissions 2>>"$LOG")"
CLAUDE_RC=$?

IS_ERROR="$(echo "$CLAUDE_OUT" | jq -r '.is_error // true' 2>/dev/null || echo true)"
RESULT_TEXT="$(echo "$CLAUDE_OUT" | jq -r '.result // ""' 2>/dev/null | head -c 1000)"
IN_TOK="$(echo "$CLAUDE_OUT" | jq -r '.usage.input_tokens // 0' 2>/dev/null || echo 0)"
OUT_TOK="$(echo "$CLAUDE_OUT" | jq -r '.usage.output_tokens // 0' 2>/dev/null || echo 0)"
TOKENS=$(( IN_TOK + OUT_TOK ))

if [ "$CLAUDE_RC" -ne 0 ] || [ "$IS_ERROR" = "true" ]; then
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
