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

# ── Shared-repo lock ──────────────────────────────────────────────────────────
# Up to 3 runners share $PLATFORM_DIR per server; concurrent fetch / worktree
# add / push race on refs ("cannot lock ref ... but expected") and killed
# bootstraps ~60s in (52 failed dispatches on 2026-07-05). Serialize every git
# op that mutates the shared clone. The fd lock releases automatically on exit,
# so emit()'s exit paths can never leak a held lock.
REPO_LOCK="$HOME/.grotap-platform.git.lock"
repo_lock()   { exec 9>"$REPO_LOCK"; flock -w 300 9 || log "WARN: repo lock timeout — proceeding unlocked"; }
repo_unlock() { exec 9>&- 2>/dev/null || true; }

# Emit the machine-readable result line and exit. python3 handles JSON escaping.
# Optional 7th arg = a verify JSON object string (Layer 9 build/lint evidence).
emit() {
  python3 -c '
import sys, json
status, branch, code, errors, summary, tokens = sys.argv[1:7]
out = {"status": status, "branch": branch, "exit_code": int(code),
       "errors": errors, "summary": summary, "tokens": int(tokens)}
verify = sys.argv[7] if len(sys.argv) > 7 else ""
if verify:
    try: out["verify"] = json.loads(verify)
    except Exception: pass
print(json.dumps(out))
' "$1" "$2" "$3" "$4" "$5" "$6" "${7:-}"
  exit 0
}

PAYLOAD="$(cat)"

# ── Self-healing git auth (durability fix, v2) ───────────────────────────────
# .gitconfig is PERSISTENT and shared by every process on the box; the env of
# whichever process wrote it is not. The previous version persisted an inline
# helper reading $GH_PUSH_TOKEN — it worked inside this script (which exports
# the var) but broke every OTHER push path (dispatch.sh runners) with empty-
# password "Authentication failed" each time an orchestrator run rewrote the
# config (2026-07-03 outage). So: persist only a SELF-SUFFICIENT helper script
# that resolves the token per call — env GITHUB_TOKEN first (sourced from
# ~/.env), Doppler fallback (survives rotation). Re-written on every run so it
# survives reprovision and stale copies.
ensure_git_auth() {
  mkdir -p "$HOME/bin"
  cat > "$HOME/bin/git-credential-doppler" <<'HELPER'
#!/bin/sh
# git credential helper — env GITHUB_TOKEN first, then Doppler. Self-sufficient:
# safe to persist in .gitconfig (no dependency on the caller's environment).
tok="${GITHUB_TOKEN:-}"
[ -z "$tok" ] && tok="$(doppler secrets get GITHUB_TOKEN --project grotap --config prd --plain 2>/dev/null)"
echo username=x-access-token
echo "password=$tok"
HELPER
  chmod +x "$HOME/bin/git-credential-doppler"
  if [ -z "${GITHUB_TOKEN:-}" ] && ! doppler secrets get GITHUB_TOKEN --project grotap --config prd --plain >/dev/null 2>&1; then
    log "WARN: no GitHub token resolvable (env GITHUB_TOKEN or Doppler) — git push may fail"
  fi
  # --replace-all: collapse any stale/duplicate helper entries (empty-string
  # resets and old inline $GH_PUSH_TOKEN helpers included). Worktrees share
  # the repo config, so this covers them too.
  git config --global --replace-all credential.helper "!$HOME/bin/git-credential-doppler" >> "$LOG" 2>&1 || true
  if [ -d "$PLATFORM_DIR/.git" ]; then
    git -C "$PLATFORM_DIR" config --replace-all credential.helper "!$HOME/bin/git-credential-doppler" >> "$LOG" 2>&1 || true
  fi
}

# ── Ensure platform repo exists and is current ───────────────────────────────
ensure_repo() {
  ensure_git_auth
  if [ ! -d "$PLATFORM_DIR/.git" ]; then
    log "Cloning grotap-platform..."
    git clone https://github.com/Grotap-AI/grotap-platform.git "$PLATFORM_DIR" >> "$LOG" 2>&1
    ensure_git_auth   # re-assert repo-scope helper now that .git exists
  fi
  cd "$PLATFORM_DIR" || return 1
  git fetch origin master --quiet >> "$LOG" 2>&1 || { sleep 5; git fetch origin master --quiet >> "$LOG" 2>&1; }
}

# ── Merge mode ───────────────────────────────────────────────────────────────
if [ "${1:-}" = "--merge" ]; then
  BRANCH="$(printf '%s' "$PAYLOAD" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("branch",""))')"
  repo_lock  # held until exit — merge mode checkouts/pulls the shared clone directly
  ensure_repo || { echo '{"merged": false, "error": "repo unavailable"}'; exit 1; }
  # ensure_repo fetches ONLY master, so on any host that didn't execute this
  # case origin/$BRANCH is missing (or stale) and the merge fails — which the
  # catch-all below used to misreport as "merge conflict". Fetch the branch
  # explicitly, force-updating the remote-tracking ref.
  git fetch origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" >> "$LOG" 2>&1 \
    || { echo '{"merged": false, "error": "branch not found on origin"}'; exit 1; }
  log "Merging $BRANCH → master"
  git checkout master --quiet >> "$LOG" 2>&1
  git pull origin master --quiet >> "$LOG" 2>&1
  if git merge --no-ff "origin/$BRANCH" -m "merge: $BRANCH (orchestrator-approved)" >> "$LOG" 2>&1; then
    git push origin master >> "$LOG" 2>&1
    # Branch hygiene: its commits are now in master, so delete it remotely +
    # locally + drop the worktree. Prevents the orphan-branch accumulation that
    # required a manual 1,135-branch cleanup. Best-effort — never fails the merge.
    git push origin --delete "$BRANCH" >> "$LOG" 2>&1 || true
    git worktree remove --force "$WORKTREE_ROOT/${BRANCH#case-}" >> "$LOG" 2>&1 || true
    git branch -D "$BRANCH" >> "$LOG" 2>&1 || true
    echo '{"merged": true, "branch_deleted": true}'
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
print("PLAN="         + shlex.quote(str(g("plan"))))
print("CONTEXT_PACK=" + shlex.quote(str(g("context_pack"))))
print("COMPLEXITY="   + shlex.quote(str(g("complexity", "medium"))))
print("ATTEMPT="      + shlex.quote(str(g("attempt", 1))))
print("PRIOR_ERRORS=" + shlex.quote("\n---\n".join(d.get("prior_errors") or [])))
')"

log "=== Execute case=$CASE_ID branch=$BRANCH attempt=$ATTEMPT ==="

repo_lock
ensure_repo || emit "failed" "$BRANCH" 1 "Platform repo unavailable" "Could not clone/fetch grotap-platform" 0

# Worktree GC + inode guard (fleet incident 2026-07-08: hundreds of stale
# done-case worktrees, each carrying a node_modules, exhausted inodes on
# agent-02/03 — `df -h` showed free bytes while `df -i` was 100%, so checkouts
# died ~2 min in with empty branches and no persisted error). Runs under the
# repo lock. Age is necessary but NOT sufficient: peers hold the repo lock
# only around fetch/worktree-add/push, not during execution, so an age-only
# sweep could race a slow live run. A worktree is treated as dead only if no
# process still references its case ID on the command line — a live run always
# has at least the peer's `orchestrator-run.sh <CASE-ID>` process, and its
# claude/npm children carry the worktree path too.
wt_dead() { ! pgrep -f "$(basename "$1")" > /dev/null 2>&1; }
gc_worktree() {
  if ! wt_dead "$1"; then
    log "GC skip (live runner): $(basename "$1")"
    return 0
  fi
  log "GC stale worktree: $(basename "$1")"
  git worktree remove --force "$1" >> "$LOG" 2>&1 && return 0
  # Destructive fallback (worktree remove can fail on corrupt metadata) only
  # after re-confirming nothing came alive since the check above.
  wt_dead "$1" && rm -rf "$1"
  return 0
}
find "$WORKTREE_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +2 2>/dev/null | while IFS= read -r wt; do
  gc_worktree "$wt"
done
git worktree prune >> "$LOG" 2>&1 || true
INODE_USE="$(df --output=ipcent "$WORKTREE_ROOT" 2>/dev/null | tail -1 | tr -dc '0-9')"
if [ -n "$INODE_USE" ] && [ "$INODE_USE" -ge 90 ]; then
  log "Inodes at ${INODE_USE}% — emergency worktree GC (>4h old)"
  find "$WORKTREE_ROOT" -mindepth 1 -maxdepth 1 -type d -mmin +240 2>/dev/null | while IFS= read -r wt; do
    gc_worktree "$wt"
  done
  git worktree prune >> "$LOG" 2>&1 || true
fi

# Fresh worktree per attempt (idempotent: remove a stale one first).
WT="$WORKTREE_ROOT/${CASE_ID}"
git worktree remove --force "$WT" >> "$LOG" 2>&1 || true
git branch -D "$BRANCH" >> "$LOG" 2>&1 || true
if ! git worktree add -b "$BRANCH" "$WT" origin/master >> "$LOG" 2>&1; then
  emit "failed" "$BRANCH" 1 "Could not create worktree/branch" "git worktree add failed" 0
fi
repo_unlock  # the long Claude run must not hold the shared-repo lock
cd "$WT" || emit "failed" "$BRANCH" 1 "Worktree missing" "cd into worktree failed" 0

# ── Build the Claude CLI prompt ──────────────────────────────────────────────
RETRY_BLOCK=""
if [ "$ATTEMPT" -gt 1 ] && [ -n "$PRIOR_ERRORS" ]; then
  RETRY_BLOCK="

## This is retry attempt $ATTEMPT. The previous attempt(s) failed. Fix these issues (real output below):
$PRIOR_ERRORS"
fi

PLAN_BLOCK=""
if [ -n "$PLAN" ]; then
  PLAN_BLOCK="

## Execution Plan (from triage — follow it unless it's clearly wrong)
$PLAN"
fi

KNOWLEDGE_BLOCK=""
if [ -n "$CONTEXT_PACK" ]; then
  KNOWLEDGE_BLOCK="

## Platform Knowledge (grounded from our docs — prefer this over assumptions)
$CONTEXT_PACK"
fi

PROMPT="You are an autonomous engineer working in an isolated git worktree on the grotap-platform repo.

# Task: $TITLE

## Context
$CONTEXT

## Requirements
$REQUIREMENTS
$KNOWLEDGE_BLOCK
$PLAN_BLOCK
$RETRY_BLOCK

## Rules
- Follow the repo CLAUDE.md and agents/GLOBAL.md rules exactly.
- Make the minimal correct change. Commit your work with git (do NOT push — the runner pushes).
- Never symlink node_modules (or any path) from the shared ~/grotap-platform clone into this worktree. If a package needs deps, run 'npm ci' inside that package here — the shared install may be stale and a symlink breaks build verification.
- Before finishing, validate: run 'npx tsc --noEmit' in any frontend/TS package you changed, and 'python3 -m py_compile' on any backend .py file you changed.
- If you cannot complete the task, explain why clearly."

# ── Permission policy ────────────────────────────────────────────────────────
# Replaces --dangerously-skip-permissions with an explicit allow/deny policy so
# the agent can do normal dev work (git/npm/tsc/python/file edits) but CANNOT
# exfiltrate (curl/wget/ssh/scp/nc), read secrets (.env, ~/.ssh, doppler), or
# run destructive/privileged commands. `deny` always wins over `allow`.
#
# The settings file lives OUTSIDE the worktree (so it's never committed) and is
# passed via --settings (highest precedence). Rollout is env-gated per the
# CLAUDE.md "framework change → staging first" rule. The orchestrator is LIVE,
# so the DEFAULT preserves current behavior; flip the env in Doppler to enforce
# after validating on one server (a headless permission prompt would hang a slot
# until the SSH timeout, so prove the allow-list is complete before fleet-wide):
#   CLAUDE_PERMISSION_MODE=bypass       (default) — current behavior (skip perms)
#   CLAUDE_PERMISSION_MODE=acceptEdits            — enforce allow/deny policy
#   CLAUDE_PERMISSION_MODE=dontAsk                — strict fail-closed (deny, no prompt)
PERM_MODE="${CLAUDE_PERMISSION_MODE:-bypass}"
SETTINGS_FILE="$HOME/.config/orchestrator/claude-settings.json"
mkdir -p "$(dirname "$SETTINGS_FILE")"
cat > "$SETTINGS_FILE" <<'JSON'
{
  "permissions": {
    "allow": [
      "Read", "Edit", "Write",
      "Bash(git *)",
      "Bash(npm *)", "Bash(npx *)", "Bash(pnpm *)", "Bash(yarn *)", "Bash(node *)",
      "Bash(python *)", "Bash(python3 *)", "Bash(pip *)", "Bash(pip3 *)",
      "Bash(pytest *)", "Bash(ruff *)", "Bash(mypy *)",
      "Bash(tsc *)", "Bash(eslint *)", "Bash(prettier *)", "Bash(vite *)",
      "Bash(ls *)", "Bash(cat *)", "Bash(head *)", "Bash(tail *)",
      "Bash(grep *)", "Bash(rg *)", "Bash(find *)", "Bash(wc *)",
      "Bash(sort *)", "Bash(uniq *)", "Bash(diff *)",
      "Bash(mkdir *)", "Bash(cp *)", "Bash(mv *)", "Bash(touch *)",
      "Bash(echo *)", "Bash(sed *)", "Bash(awk *)",
      "Bash(cd *)", "Bash(pwd)", "Bash(test *)", "Bash(env)"
    ],
    "deny": [
      "Bash(curl *)", "Bash(wget *)",
      "Bash(ssh *)", "Bash(scp *)", "Bash(sftp *)", "Bash(rsync *)",
      "Bash(nc *)", "Bash(ncat *)", "Bash(telnet *)",
      "Bash(doppler *)", "Bash(sudo *)",
      "Bash(cat *.env*)", "Bash(cat *secret*)", "Bash(cat *.pem)",
      "Bash(cat ~/.ssh/*)", "Bash(cat ~/.aws/*)",
      "Read(.env)", "Read(.env.*)", "Read(**/.env)", "Read(**/.env.*)",
      "Read(~/.ssh/**)", "Read(~/.aws/**)", "Read(~/.config/doppler/**)",
      "Read(**/id_rsa*)", "Read(**/*.pem)"
    ]
  }
}
JSON

# ── Model selection by complexity (cost control — #5) ────────────────────────
# Default the heavy coding model to the task's complexity tier; override with
# CODING_MODEL to pin a single model fleet-wide.
case "$COMPLEXITY" in
  complex) MODEL="${CODING_MODEL:-claude-opus-4-8}" ;;
  *)       MODEL="${CODING_MODEL:-claude-sonnet-4-6}" ;;
esac

# ── Run Claude CLI headless ──────────────────────────────────────────────────
if [ "$PERM_MODE" = "bypass" ]; then
  PERM_ARGS=(--dangerously-skip-permissions)
else
  PERM_ARGS=(--permission-mode "$PERM_MODE" --settings "$SETTINGS_FILE")
fi
log "Running Claude: model=$MODEL perm_mode=$PERM_MODE"
CLAUDE_OUT="$(claude -p "$PROMPT" --model "$MODEL" --output-format json "${PERM_ARGS[@]}" 2>>"$LOG")"
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

# ── Verify (Layer 9) ─────────────────────────────────────────────────────────
# Real on-server verification, stronger than a typecheck: full `npm run build`
# for the frontend (catches bundling/import errors tsc misses), tsc for the TS
# workers, eslint as a soft signal, py_compile for Python, and any package
# `test` script that exists. Hard failures (build/tsc/py_compile/tests) set
# VALID_ERR — captured verbatim so the diagnose node retries against the REAL
# error (grounded retries, #3). Every check is recorded in VERIFY_CHECKS so the
# review node + human gate see exactly what passed.
VALID_ERR=""
VERIFY_CHECKS=""   # newline-separated "name: pass|FAIL|warn|skipped"
CHANGED="$(git diff --name-only origin/master 2>/dev/null; git diff --cached --name-only 2>/dev/null)"

add_check() { VERIFY_CHECKS="${VERIFY_CHECKS:+$VERIFY_CHECKS
}$1"; }
add_fail()  { VALID_ERR="${VALID_ERR:+$VALID_ERR

}### $1:
$(printf '%s' "$2" | tail -c 2000)"; }

# Hard build/tsc verification for a changed TS package. mode = build|tsc.
verify_ts() {
  local pkg="$1" mode="$2"
  echo "$CHANGED" | grep -q "^${pkg}/" || return 0
  [ -f "${pkg}/package.json" ] || return 0
  # Self-heal deps so verification actually runs fleet-wide (node_modules coverage
  # varies per server). npm ci needs the lockfile; an install failure degrades to
  # a skip — never a false task failure.
  # A symlinked node_modules is NOT an install: runners have linked it to the
  # shared clone's (possibly stale/broken) install mid-run, which made this
  # existence check pass and verification fail with missing-module errors from
  # untouched master files (fleet incident 2026-07-08). Same for a dir without
  # npm's .package-lock.json marker (partial/killed install). Both → reinstall.
  if [ -L "${pkg}/node_modules" ]; then
    log "Removing ${pkg}/node_modules symlink (not a real install)..."
    rm -f "${pkg}/node_modules"
  fi
  if [ ! -d "${pkg}/node_modules" ] || [ ! -f "${pkg}/node_modules/.package-lock.json" ]; then
    if [ -f "${pkg}/package-lock.json" ]; then
      log "Installing ${pkg} deps (npm ci)..."
      if ! (cd "$pkg" && timeout 420 npm ci --prefer-offline --no-audit --no-fund >>"$LOG" 2>&1); then
        add_check "${pkg} ${mode}: skipped (dep install failed)"
        return 0
      fi
    else
      add_check "${pkg} ${mode}: skipped (no lockfile)"
      return 0
    fi
  fi
  log "Verifying ${pkg} (${mode})..."
  local out rc
  if [ "$mode" = "build" ]; then
    out="$(cd "$pkg" && timeout 360 npm run build 2>&1)"; rc=$?
  else
    out="$(cd "$pkg" && timeout 240 npx tsc --noEmit 2>&1)"; rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    add_check "${pkg} ${mode}: FAIL"
    add_fail "${pkg} ${mode} failed" "$out"
  else
    add_check "${pkg} ${mode}: pass"
  fi
}
verify_ts frontend build          # tsc && vite build — real bundle
verify_ts agent-worker tsc
verify_ts orchestrator tsc
verify_ts ingestion-worker tsc

# Soft signal: frontend lint (recorded, never blocks — style ≠ correctness).
if echo "$CHANGED" | grep -q '^frontend/' && [ -d frontend/node_modules ]; then
  if (cd frontend && timeout 180 npm run lint >/dev/null 2>&1); then
    add_check "frontend lint: pass"
  else
    add_check "frontend lint: warn"
  fi
fi

# Python: compile every changed .py (hard). Deleted files can't compile —
# a task that removes a .py file must not fail verification on its own
# deletion (7F3D79 burned 3 attempts on this, 2026-07-11).
while IFS= read -r pyf; do
  [ -z "$pyf" ] && continue
  if [ ! -f "$pyf" ]; then
    add_check "py_compile ${pyf}: skipped (deleted)"
    continue
  fi
  pyout="$(python3 -m py_compile "$pyf" 2>&1)"
  if [ $? -ne 0 ]; then
    add_check "py_compile ${pyf}: FAIL"
    add_fail "py_compile failed (${pyf})" "$pyout"
  else
    add_check "py_compile ${pyf}: pass"
  fi
done < <(echo "$CHANGED" | grep '\.py$')

# Run a package `test` script if one exists (future-proof; most have none today).
for pkg in frontend agent-worker orchestrator ingestion-worker backend; do
  echo "$CHANGED" | grep -q "^${pkg}/" || continue
  [ -f "${pkg}/package.json" ] && [ -d "${pkg}/node_modules" ] || continue
  if node -e "process.exit((require('./${pkg}/package.json').scripts||{}).test?0:1)" 2>/dev/null; then
    log "Running ${pkg} tests..."
    tout="$(cd "$pkg" && timeout 300 npm test 2>&1)"
    if [ $? -ne 0 ]; then
      add_check "${pkg} tests: FAIL"; add_fail "${pkg} tests failed" "$tout"
    else
      add_check "${pkg} tests: pass"
    fi
  fi
done

# Build the verify evidence object passed back to the orchestrator.
build_verify_json() {
  local passed="$1"
  python3 -c '
import sys, json
checks = [c for c in sys.argv[1].split("\n") if c.strip()]
print(json.dumps({"checks": checks, "passed": sys.argv[2] == "1",
                  "details": sys.argv[3][:2000]}))
' "$VERIFY_CHECKS" "$passed" "$VALID_ERR"
}

# Did the agent actually produce committed changes?
if ! git rev-parse --verify HEAD >/dev/null 2>&1 || [ -z "$(git log origin/master..HEAD --oneline 2>/dev/null)" ]; then
  emit "failed" "$BRANCH" 1 "No commits produced on $BRANCH" "Agent made no committed changes" "$TOKENS" "$(build_verify_json 0)"
fi

if [ -n "$VALID_ERR" ]; then
  emit "failed" "$BRANCH" 1 "$VALID_ERR" "Verification failed" "$TOKENS" "$(build_verify_json 0)"
fi

# ── Push branch (orchestrator decides on merge later, after human gate) ──────
repo_lock  # pushes update shared remote-tracking refs — same race as fetch
# Refresh the lease basis first: ensure_repo fetches ONLY master, so a leftover
# remote branch from a previous attempt leaves the remote-tracking ref stale or
# absent and --force-with-lease fails "[rejected] (stale info)" on EVERY retry
# (BAA42B/F4D19E each burned 3 strikes on this, 2026-07-05).
git fetch origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" >> "$LOG" 2>&1 || true
if ! git push -u origin "$BRANCH" --force-with-lease >> "$LOG" 2>&1; then
  repo_unlock
  emit "failed" "$BRANCH" 1 "git push failed" "Could not push branch" "$TOKENS" "$(build_verify_json 1)"
fi
repo_unlock

log "=== Success case=$CASE_ID branch=$BRANCH tokens=$TOKENS checks=[$VERIFY_CHECKS] ==="
emit "success" "$BRANCH" 0 "" "$RESULT_TEXT" "$TOKENS" "$(build_verify_json 1)"
