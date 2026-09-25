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
#    "errors":"...","summary":"...","tokens":N,"verify"?:{...},
#    "driver_result":{...},"log_tag":"..."}
#
# tokens stays the historical integer (Claude usage input_tokens + output_tokens,
# cache excluded). driver_result is schema driver-result/v1. Before that line,
# stderr carries the per-run log between
#   =====RUN-LOG-BEGIN <log_tag>=====
# and
#   =====RUN-LOG-END=====
#
# This file is the generic wrapper. It does not branch on the tool. Model
# choice, the claude -p invocation, and the JSON parse live in
# agents/scripts/drivers/run-claude.sh. A missing payload.driver defaults to
# claude only when the payload has no team or team=team1.
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
export LOG
mkdir -p "$HOME/logs" "$WORKTREE_ROOT"
HERE="$(cd "$(dirname "$0")" && pwd)"
HOST_LABEL_FILE="${ORCH_HOST_LABEL_FILE:-/etc/fleet-agent/config.json}"

# Shared fleet log AND the per-run log. RUN_LOG is empty until the payload
# has been parsed far enough to name the file.
RUN_LOG=""
log() {
  local line="[$(date -u +%H:%M:%S)] $*"
  echo "$line" >> "$LOG"
  if [ -n "${RUN_LOG:-}" ]; then
    echo "$line" >> "$RUN_LOG"
  fi
}

# Cat the per-run log to stderr, framed, immediately before the final JSON
# line. The markers are not written into the file (that would recurse).
dump_run_log() {
  [ -n "${ORCH_LOG_TAG:-}" ] || return 0
  [ -n "${RUN_LOG:-}" ] && [ -f "$RUN_LOG" ] || return 0
  echo "=====RUN-LOG-BEGIN ${ORCH_LOG_TAG}=====" >&2
  cat "$RUN_LOG" >&2
  echo "=====RUN-LOG-END=====" >&2
}

# ── Shared-repo lock ──────────────────────────────────────────────────────────
# Up to 3 runners share $PLATFORM_DIR per server; concurrent fetch / worktree
# add / push race on refs ("cannot lock ref ... but expected") and killed
# bootstraps ~60s in (52 failed dispatches on 2026-07-05). Serialize every git
# op that mutates the shared clone. The fd lock releases automatically on exit,
# so emit()'s exit paths can never leak a held lock.
REPO_LOCK="$HOME/.grotap-platform.git.lock"
repo_lock()   { exec 9>"$REPO_LOCK"; flock -w 300 9 || log "WARN: repo lock timeout — proceeding unlocked"; }
# Close fd 9 only. `exec 9>&- 2>/dev/null` with no command applies EVERY
# redirection to this shell, which discarded stderr for the rest of the run
# (the per-run log frame never reached the orchestrator). Do not put a
# redirection on this exec.
repo_unlock() { exec 9>&- || true; }

# Emit the machine-readable result line and exit. python3 handles JSON escaping.
# Optional 7th arg = a verify JSON object string (Layer 9 build/lint evidence).
# Existing fields stay in their historical order. driver_result and log_tag are
# appended. tokens is the integer the caller passed (back-compat total).
emit() {
  dump_run_log
  DRIVER_RESULT_FILE="${DRIVER_RESULT_FILE:-}" \
  ORCH_LOG_TAG="${ORCH_LOG_TAG:-}" \
  ORCH_TEAM="${ORCH_TEAM:-${TEAM:-}}" \
  ORCH_DRIVER="${ORCH_DRIVER:-${DRIVER:-}}" \
  python3 -c '
import sys, json, os
status, branch, code, errors, summary, tokens = sys.argv[1:7]
out = {"status": status, "branch": branch, "exit_code": int(code),
       "errors": errors, "summary": summary, "tokens": int(tokens)}
verify = sys.argv[7] if len(sys.argv) > 7 else ""
if verify:
    try: out["verify"] = json.loads(verify)
    except Exception: pass

def load_driver():
    path = os.environ.get("DRIVER_RESULT_FILE") or ""
    if path and os.path.isfile(path) and os.path.getsize(path) > 0:
        try:
            with open(path) as fh:
                return json.load(fh)
        except Exception:
            return None
    return None

dr = load_driver()
if not isinstance(dr, dict):
    err_class = None
    if errors.startswith("error_class="):
        err_class = errors.split(" ", 1)[0].split("=", 1)[1] or None
    now = os.environ.get("ORCH_STARTED_AT") or ""
    team = os.environ.get("ORCH_TEAM") or None
    driver = os.environ.get("ORCH_DRIVER") or None
    dr = {
        "schema": "driver-result/v1",
        "team": team,
        "driver": driver,
        "driver_version": None,
        "tool_bin": None,
        "provider": None,
        "model": None,
        "profile": None,
        "status": "failed" if status != "success" else "success",
        "error_class": err_class,
        "summary": summary,
        "errors": errors,
        "tokens": {"input": 0, "cached_input": 0, "cache_write_input": 0,
                   "output": 0, "reasoning": 0, "total": 0},
        "cost": {"usd": None, "source": "not_priced", "price_table_version": None,
                 "long_context_multiplier_applied": False},
        "attempts_inside_driver": 0,
        "session_id": None,
        "started_at": now or None,
        "ended_at": now or None,
    }
out["driver_result"] = dr
out["log_tag"] = os.environ.get("ORCH_LOG_TAG") or ""
print(json.dumps(out), flush=True)
' "$1" "$2" "$3" "$4" "$5" "$6" "${7:-}"
  exit 0
}

# deploy.ts treats a zero exit from --merge as merged. emit() always exits 0,
# so a merge-mode refusal must not call it: that recorded a refused merge as
# merged while origin was untouched. Exit 1 with the merge-shaped object.
merge_refuse() {
  dump_run_log
  python3 -c 'import json, sys; print(json.dumps({"merged": False, "error": sys.argv[1]}))' "$1"
  exit 1
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

# ── Bootstrap pin (P1-B) ─────────────────────────────────────────────────────
# ~/grotap-agents is refreshed from origin on every run and THIS FILE is
# executed out of it, so whatever that tree holds runs as the agent user on
# every fleet host (and grotap-platform's dispatch.sh cats BOOTSTRAP.md and
# agents/GLOBAL.md out of the same tree straight into the model prompt).
# agents/BOOTSTRAP_SHA records the blessed commit, and this function decides
# what is put on disk.
#
# MODES (ORCH_BOOTSTRAP_PIN):
#   detach  (DEFAULT — `on` and `pin` are aliases). A REAL pin. The pinned
#     commit must exist in the fetched repo; the runner then checks it out
#     DETACHED and confirms HEAD equals it. Master may have moved on; the fleet
#     runs the blessed tree regardless. A stale pin therefore degrades to
#     "agents read a slightly older BOOTSTRAP.md", never to "no agents run".
#     That is exactly the property the old exact-match pin lacked: it asserted
#     "master tip == hardcoded SHA", which is false on every box at once after
#     any routine push, and every abort burned a retry strike because nothing
#     caps dispatch strikes.
#     ROTATION IS MANDATORY: nothing pushed to grotap-agents master reaches an
#     agent until agents/BOOTSTRAP_SHA names it. See that file's ROTATION
#     section.
#   ancestor — the legacy DETECTOR: verify the tip descends from the pin, then
#     run the TIP. Catches a force-push/rewrite but does not control what runs.
#     Kept as a one-env-var rollback.
#   exact — the fetched tip must EQUAL the pin (and is then what runs). A
#     lockdown window only: it stops the fleet the moment master moves.
#   off (also 0/false/no) — no check, loud warning. Emergency bypass.
#   Anything unrecognised is treated as `detach` with a warning: a typo in an
#   env var must not silently switch the control off.
#
# ANCESTRY IS KEPT AS AN ADDITIONAL SIGNAL. In detach mode a pin that is not an
# ancestor of the tip still means a force-push or a history rewrite, so it gets
# a distinct, louder line — but it does NOT abort, because the tree that runs is
# the blessed commit either way, and aborting there would hand anyone with push
# access a fleet-wide kill switch.
#
# Absent or malformed pin file on a host that has NEVER verified a pin => loud
# warning and continue, NOT a brick: this file reaches hosts by the very
# self-sync it is guarding, so a host can be running a copy of the script that is
# newer than its copy of the pin file.
# Absent or malformed on a host that HAS verified one before => hard FAIL. The
# difference is $HOME/.grotap_bootstrap_pin_seen, stamped on every successful
# verify and living outside the git tree so a push cannot clear it. Without that
# distinction, one ordinary commit deleting agents/BOOTSTRAP_SHA would switch
# the control off permanently, for every actor, with nothing louder than a log
# line.
BOOTSTRAP_PIN_FAIL=""
BOOTSTRAP_PIN_SHA=""   # set only in detach mode: the commit to check out
verify_bootstrap_pin() {
  local mode target pinned
  BOOTSTRAP_PIN_SHA=""
  mode="$(printf '%s' "${ORCH_BOOTSTRAP_PIN:-detach}" | tr '[:upper:]' '[:lower:]')"
  case "$mode" in
    off|0|false|no)
      log "WARNING: bootstrap pin DISABLED (ORCH_BOOTSTRAP_PIN=$mode) — ~/grotap-agents is UNVERIFIED"
      return 0
      ;;
    detach|on|pin|"") mode="detach" ;;
    ancestor|exact)   ;;
    *)
      log "WARNING: unrecognised ORCH_BOOTSTRAP_PIN='$mode' — enforcing the default 'detach' mode (a typo must not disable the pin)"
      mode="detach"
      ;;
  esac

  # The pin lives INSIDE the repo it pins, so anyone with ordinary push access
  # can delete or corrupt it with one legitimate commit. The seen-marker lives
  # OUTSIDE the git tree, where a push cannot reach it, and turns that into a
  # fail-closed error. A genuinely fresh host has no marker and keeps the
  # deliberate fail-open, so this does not brick a box whose script is newer
  # than its pin file.
  #
  # WHERE THE PIN IS READ FROM, and why it is not the working tree.
  # The verify runs BEFORE the incoming tree is put on disk, so the on-disk file
  # is the PREVIOUS run's copy. If a bad value is ever committed -- a trailing
  # space, a CRLF from a Windows edit, an abbreviated SHA -- it lands on all
  # five boxes on run N and fails every run from N+1, and the corrected push can
  # never take effect, because updating the tree is downstream of the check that
  # is refusing. Recovery would be SSH to five boxes. Reading the pin out of the
  # fetched remote ref instead makes a corrected push effective on the very next
  # run, while still being a value the operator committed deliberately.
  local pin_file="$HOME/grotap-agents/agents/BOOTSTRAP_SHA"
  local seen_marker="$HOME/.grotap_bootstrap_pin_seen"
  local pin_src="working tree"
  local pin_text=""
  if [ "${_BS_FETCH_OK:-1}" = "1" ]; then
    pin_text="$(git -C "$HOME/grotap-agents" show origin/master:agents/BOOTSTRAP_SHA 2>/dev/null || true)"
    [ -n "$pin_text" ] && pin_src="origin/master"
  fi
  if [ ! -f "$pin_file" ] && [ -z "$pin_text" ]; then
    if [ -f "$seen_marker" ]; then
      BOOTSTRAP_PIN_FAIL="bootstrap pin WENT MISSING: $pin_file is absent but this host has verified a pin before ($seen_marker). A commit deleted the pin file — that disables the control for every later run, so this is refused rather than warned. Restore agents/BOOTSTRAP_SHA, or set ORCH_BOOTSTRAP_PIN=off deliberately."
      log "ERROR: $BOOTSTRAP_PIN_FAIL"
      return 1
    fi
    log "WARNING: no $pin_file — bootstrap tree UNPINNED (P1-B still open on this host)"
    return 0
  fi
  # Strip CR so a Windows-edited pin file still parses; keep line structure so
  # the 40-hex match stays anchored to a line of its own. (Deleting newlines
  # here instead would fold the whole commented file onto ONE line, no line
  # would ever match ^[0-9a-f]{40}$, and the pin would silently read as absent.)
  if [ -n "$pin_text" ]; then
    pinned="$(printf '%s\n' "$pin_text" | tr -d '\r' | grep -oE '^[0-9a-f]{40}$' | head -1)"
  else
    pinned="$(tr -d '\r' < "$pin_file" 2>/dev/null | grep -oE '^[0-9a-f]{40}$' | head -1)"
  fi
  log "Bootstrap pin source: $pin_src"
  if [ -z "$pinned" ]; then
    if [ -f "$seen_marker" ]; then
      BOOTSTRAP_PIN_FAIL="bootstrap pin CORRUPT: $pin_src holds no bare 40-hex SHA on a line of its own, but this host has verified a pin before ($seen_marker). Treated as tampering, not as a fresh host. Restore agents/BOOTSTRAP_SHA, or set ORCH_BOOTSTRAP_PIN=off deliberately."
      log "ERROR: $BOOTSTRAP_PIN_FAIL"
      return 1
    fi
    log "WARNING: $pin_src holds no bare 40-hex SHA — bootstrap tree UNPINNED"
    return 0
  fi

  # The tip we would otherwise have run: the fetched remote when the fetch
  # worked, otherwise whatever is already checked out.
  if [ "${_BS_FETCH_OK:-1}" = "1" ]; then
    target="$(git -C "$HOME/grotap-agents" rev-parse origin/master 2>/dev/null || echo "")"
  else
    target="$(git -C "$HOME/grotap-agents" rev-parse HEAD 2>/dev/null || echo "")"
  fi
  if [ -z "$target" ]; then
    BOOTSTRAP_PIN_FAIL="bootstrap pin: cannot resolve a commit to verify in ~/grotap-agents"
    log "ERROR: $BOOTSTRAP_PIN_FAIL"
    return 1
  fi

  # Does the blessed commit exist here at all? Missing means the history was
  # rewritten, the remote is a different repository, or the pin names a commit
  # that was never pushed. Refuse in every enforcing mode — there is nothing
  # blessed to run.
  if ! git -C "$HOME/grotap-agents" cat-file -e "${pinned}^{commit}" 2>/dev/null; then
    local fetch_state="fetch OK"
    [ "${_BS_FETCH_OK:-1}" = "1" ] || fetch_state="fetch FAILED"
    BOOTSTRAP_PIN_FAIL="bootstrap pin: pinned commit $pinned does not exist in ~/grotap-agents ($fetch_state) — the history was rewritten, the remote is not the repo this pin was taken from, or the pin names a commit that was never pushed. Rotate agents/BOOTSTRAP_SHA to a commit that IS on the remote; ORCH_BOOTSTRAP_PIN=off is the emergency bypass."
    log "ERROR: $BOOTSTRAP_PIN_FAIL"
    return 1
  fi

  # Cheap, and still meaningful in detach mode as a rewrite signal.
  local descends="no"
  git -C "$HOME/grotap-agents" merge-base --is-ancestor "$pinned" "$target" 2>/dev/null && descends="yes"

  if [ "$mode" = "detach" ]; then
    if [ "$descends" != "yes" ] && [ "$target" != "$pinned" ]; then
      log "SECURITY WARNING: pinned $pinned is NOT an ancestor of $target — force-push or history rewrite on grotap-agents master. The PINNED tree is what runs, so dispatch continues rather than handing push access a fleet-wide kill switch. Investigate the remote before rotating the pin."
    fi
    BOOTSTRAP_PIN_SHA="$pinned"
    if [ "$target" = "$pinned" ]; then
      log "Bootstrap tree VERIFIED at pinned $pinned (mode=detach; the pin IS the current tip)"
    else
      local ahead
      ahead="$(git -C "$HOME/grotap-agents" rev-list --count "${pinned}..${target}" 2>/dev/null || echo "?")"
      log "Bootstrap tree PINNED at $pinned (mode=detach) — tip $target is $ahead commit(s) ahead and will NOT be run. Rotate agents/BOOTSTRAP_SHA to ship it."
    fi
    : > "$seen_marker" 2>/dev/null || true
    return 0
  fi

  # ── Legacy modes: verify only, then run whatever the tip is ────────────────
  if [ "$target" = "$pinned" ]; then
    log "Bootstrap tree VERIFIED at pinned $pinned (mode=$mode)"
    : > "$seen_marker" 2>/dev/null || true
    return 0
  fi

  if [ "$mode" = "exact" ]; then
    BOOTSTRAP_PIN_FAIL="bootstrap pin MISMATCH (exact): ~/grotap-agents is at $target, agents/BOOTSTRAP_SHA pins $pinned. Rotate the pin, or drop ORCH_BOOTSTRAP_PIN to get the default detach mode, which RUNS the pin instead of refusing."
    log "ERROR: $BOOTSTRAP_PIN_FAIL"
    return 1
  fi

  # ancestor mode
  if [ "$descends" = "yes" ]; then
    log "Bootstrap tree OK: $target descends from pinned $pinned (mode=ancestor) — running the TIP, not the pin"
    : > "$seen_marker" 2>/dev/null || true
    return 0
  fi
  BOOTSTRAP_PIN_FAIL="bootstrap pin BROKEN: $target does not descend from pinned $pinned — force-push or history rewrite on grotap-agents master. Refusing to run it. Rotate agents/BOOTSTRAP_SHA only after reading what changed; ORCH_BOOTSTRAP_PIN=off is the emergency bypass."
  log "ERROR: $BOOTSTRAP_PIN_FAIL"
  return 1
}

# Put the blessed commit on disk and PROVE it landed. Every failure here is
# "we could not establish the tree we are required to run", which is an infra
# abort — NOT the stale-pin case. A stale pin never reaches this function's
# error paths: it simply checks out an older commit and the agents read an older
# BOOTSTRAP.md, so a routine push to grotap-agents can never brick the fleet.
checkout_bootstrap_pin() {
  local sha="$BOOTSTRAP_PIN_SHA" now
  [ -z "$sha" ] && return 0
  if ! git -C "$HOME/grotap-agents" checkout --quiet --force --detach "$sha" >> "$LOG" 2>&1; then
    BOOTSTRAP_PIN_FAIL="bootstrap pin: could not check out pinned commit $sha in ~/grotap-agents (git checkout --detach failed — see $LOG). The blessed tree was NOT put on disk, so the run is refused instead of executing an unverified tree."
    log "ERROR: $BOOTSTRAP_PIN_FAIL"
    return 1
  fi
  now="$(git -C "$HOME/grotap-agents" rev-parse HEAD 2>/dev/null || echo "")"
  if [ "$now" != "$sha" ]; then
    BOOTSTRAP_PIN_FAIL="bootstrap pin: HEAD is '$now' after checking out pinned $sha — refusing to run a bootstrap tree that is not the blessed commit."
    log "ERROR: $BOOTSTRAP_PIN_FAIL"
    return 1
  fi
  # checkout --force already restored tracked files; this makes the index agree
  # and clears anything a killed earlier run left staged.
  git -C "$HOME/grotap-agents" reset --quiet --hard "$sha" >> "$LOG" 2>&1 || true
  log "Bootstrap tree CHECKED OUT detached at pinned $sha"
  return 0
}

# ── Ensure platform repo exists and is current ───────────────────────────────
ensure_repo() {
  # A preset ORCH_BOOTSTRAP_FETCH_DONE=1 (from ~/.env, dotfiles, or the
  # orchestrator's run_env) must not skip fetch, verify, or checkout.
  # Honour the skip only for the re-exec'd copy, and only after that copy
  # proves it is still on the commit the parent pinned.
  # The snapshot path is the one the parent created with mktemp and passed
  # in ORCH_RUNNER_SNAPSHOT. It is not derived from ORCH_LOG_TAG, and it is
  # not canonicalized: readlink -f is how a symlinked directory or a '..'
  # tag used to resolve back at this repo and skip the pin.
  if _snapshot_trusted "${ORCH_RUNNER_SNAPSHOT:-}" \
      && [ "${ORCH_RUNNER_REEXECED:-}" = "1" ] \
      && [ "${ORCH_BOOTSTRAP_FETCH_DONE:-}" = "1" ]; then
    # Validated. This process may remove it on the way out.
    _ORCH_OWNED_SNAP="$ORCH_RUNNER_SNAPSHOT"
    local head
    head="$(git -C "$HOME/grotap-agents" rev-parse HEAD 2>/dev/null || true)"
    if [ -z "${ORCH_BOOTSTRAP_PINNED_SHA:-}" ] || [ "$head" != "$ORCH_BOOTSTRAP_PINNED_SHA" ]; then
      BOOTSTRAP_PIN_FAIL="bootstrap pin: re-exec HEAD '${head:-missing}' does not equal pinned '${ORCH_BOOTSTRAP_PINNED_SHA:-unset}'"
      log "ERROR: $BOOTSTRAP_PIN_FAIL"
      return 1
    fi
    log "runner re-exec: skipping bootstrap fetch and checkout (HEAD $head)"
    cd "$PLATFORM_DIR" || return 1
    return 0
  fi
  if [ "${ORCH_BOOTSTRAP_FETCH_DONE:-}" = "1" ] || [ "${ORCH_RUNNER_REEXECED:-}" = "1" ]; then
    log "WARN: ignoring preset ORCH_BOOTSTRAP_FETCH_DONE (snapshot is not a private mktemp dir)"
    unset ORCH_BOOTSTRAP_FETCH_DONE
    unset ORCH_RUNNER_REEXECED
  fi
  ensure_git_auth
  # Self-sync the bootstrap repo: the orchestrator SSH path runs this file straight from
  # ~/grotap-agents and never executes dispatch.sh's bootstrap sync, so runner fixes never
  # reached agent-03 (clone stale since 2026-07-12; CASE-20260910-571311 re-hit the
  # already-fixed stale-lease bug). git swaps the file by rename, so the running bash keeps
  # the old inode; the NEXT run gets the update. Local-only commits are parked on a
  # backup branch, never discarded.
  _BS_FETCH_OK=1
  if git -C "$HOME/grotap-agents" fetch origin +refs/heads/master:refs/remotes/origin/master -q >> "$LOG" 2>&1; then
    # ── P1-B: verify the incoming bootstrap tree BEFORE anything of it lands
    # on disk. This is not prompt hygiene: the next run executes this very
    # file out of ~/grotap-agents, so an unverified checkout is remote code
    # execution on every fleet host, one run later.
    if ! verify_bootstrap_pin; then
      return 1
    fi
    if [ -n "$(git -C "$HOME/grotap-agents" log --oneline origin/master..HEAD 2>/dev/null)" ]; then
      git -C "$HOME/grotap-agents" branch -f "backup/local-$(date -u +%Y%m%d-%H%M%S)" HEAD >> "$LOG" 2>&1 || true
    fi
    if [ -n "$BOOTSTRAP_PIN_SHA" ]; then
      # Default (detach) mode: run the BLESSED commit, not the tip.
      checkout_bootstrap_pin || return 1
    else
      # Legacy/off modes: the tip is what runs.
      git -C "$HOME/grotap-agents" reset --hard origin/master -q >> "$LOG" 2>&1 || true
    fi
  else
    # Fetch failed: nothing new lands, but the tree on disk still executes, so
    # it is still checked — against HEAD rather than the unavailable remote —
    # and still moved onto the pin when the pinned commit is already here.
    _BS_FETCH_OK=0
    if ! verify_bootstrap_pin; then
      return 1
    fi
    checkout_bootstrap_pin || return 1
  fi
  if [ ! -d "$PLATFORM_DIR/.git" ]; then
    log "Cloning grotap-platform..."
    git clone https://github.com/Grotap-AI/grotap-platform.git "$PLATFORM_DIR" >> "$LOG" 2>&1
    ensure_git_auth   # re-assert repo-scope helper now that .git exists
  fi
  cd "$PLATFORM_DIR" || return 1
  git fetch origin master --quiet >> "$LOG" 2>&1 || { sleep 5; git fetch origin master --quiet >> "$LOG" 2>&1; }
}

# ── Per-run log, host-label cross-check, driver name ─────────────────────────
# All of this is before any git operation on the repos. A host-label mismatch
# or a missing driver for a non-team1 payload emits error_class=infra and
# returns without touching ~/grotap-agents or ~/grotap-platform.
_safe_component() {
  local s
  s="$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"
  [ -n "$s" ] || s="unknown"
  printf '%s' "$s"
}
_open_run_log() {
  local c a
  c="$(_safe_component "$1")"
  a="$(_safe_component "$2")"
  mkdir -p "$HOME/logs/runs"
  RUN_LOG="$HOME/logs/runs/${c}-${a}-${ORCH_LOG_TAG}.log"
  touch "$RUN_LOG"
  chmod 600 "$RUN_LOG" 2>/dev/null || true
  export RUN_LOG
}
# Assigned only after this process creates a directory with mktemp, or after
# the re-exec child has validated the path the parent passed. Never read from
# the environment: ~/.env is sourced with set -a, so an exported value would
# be an attacker-chosen rm -rf target. Unset here, after that source.
unset _ORCH_OWNED_SNAP

# A directory is safe to remove when it is a real /tmp directory (not a
# symlink), owned by this user, mode 0700, with exactly one path component
# and no '..'. The trap uses this so it cannot follow a tag or an env path.
_snap_removable() {
  local snap="$1" base owner mode
  [ -n "$snap" ] || return 1
  case "$snap" in
    *..*) return 1 ;;
    /tmp/*/*) return 1 ;;
    /tmp/*) ;;
    *) return 1 ;;
  esac
  base="${snap#/tmp/}"
  [ -n "$base" ] || return 1
  case "$base" in
    */*) return 1 ;;
  esac
  # test -d follows symlinks. Reject a link before that check.
  [ ! -L "$snap" ] || return 1
  [ -d "$snap" ] || return 1
  owner="$(stat -c '%u' -- "$snap" 2>/dev/null || true)"
  [ "$owner" = "$(id -u)" ] || return 1
  mode="$(stat -c '%a' -- "$snap" 2>/dev/null || true)"
  [ "$mode" = "700" ] || return 1
  return 0
}

# The re-exec copy. $0 must be that directory's runner, exactly — a
# canonicalized path is how a symlink or a '..' tag used to look legitimate.
_snapshot_trusted() {
  local snap="$1"
  _snap_removable "$snap" || return 1
  [ "$0" = "${snap}/orchestrator-run.sh" ] || return 1
  return 0
}

_orch_on_exit() {
  # The per-run log stays. Remove only the snapshot path this process
  # recorded after mktemp or after the checks above.
  if [ -n "${_ORCH_OWNED_SNAP:-}" ] && _snap_removable "$_ORCH_OWNED_SNAP"; then
    rm -rf -- "$_ORCH_OWNED_SNAP"
  fi
}
trap _orch_on_exit EXIT

# Log tags are path components (per-run log, payload file). Accept only a
# short alphanumeric token. Anything else — slashes, '..', spaces — is
# replaced. The generator is urandom, not date+$$.
_fresh_log_tag() {
  local t
  t="$(od -An -N8 -tx8 /dev/urandom 2>/dev/null | tr -d ' \n' || true)"
  if [[ ! "$t" =~ ^[A-Za-z0-9]{1,32}$ ]]; then
    t="$(python3 -c 'import os; print(os.urandom(8).hex())' 2>/dev/null || true)"
  fi
  printf '%s' "$t"
}
if [[ ! "${ORCH_LOG_TAG:-}" =~ ^[A-Za-z0-9]{1,32}$ ]]; then
  if [ -n "${ORCH_LOG_TAG:-}" ]; then
    _ORCH_LOG_TAG_REJECTED=1
  fi
  ORCH_LOG_TAG="$(_fresh_log_tag)"
  if [[ ! "${ORCH_LOG_TAG:-}" =~ ^[A-Za-z0-9]{1,32}$ ]]; then
    echo "FATAL: could not generate ORCH_LOG_TAG" >&2
    exit 1
  fi
  if [ "${_ORCH_LOG_TAG_REJECTED:-}" = "1" ]; then
    log "WARN: ORCH_LOG_TAG rejected; regenerated"
  fi
fi
export ORCH_LOG_TAG
ORCH_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export ORCH_STARTED_AT

CASE_ID=""; BRANCH=""; TEAM=""; DRIVER=""; ATTEMPT="1"; PARSE_OK=0
eval "$(printf '%s' "$PAYLOAD" | python3 -c '
import sys, json, shlex
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print("PARSE_OK=0")
    sys.exit(0)
if not isinstance(d, dict):
    print("PARSE_OK=0")
    sys.exit(0)
def g(k, default=""):
    v = d.get(k, default)
    return default if v is None else v
print("PARSE_OK=1")
print("CASE_ID=" + shlex.quote(str(g("case_id"))))
print("BRANCH="  + shlex.quote(str(g("branch"))))
print("TEAM="    + shlex.quote(str(g("team"))))
print("DRIVER="  + shlex.quote(str(g("driver"))))
print("ATTEMPT=" + shlex.quote(str(g("attempt", 1))))
')" || PARSE_OK=0

if [ "${PARSE_OK:-0}" != "1" ]; then
  if [ "${1:-}" = "--merge" ]; then
    _open_run_log "unknown" "merge"
    merge_refuse "payload is not valid JSON"
  fi
  _open_run_log "unknown" "0"
  emit "failed" "" 1 "error_class=infra payload is not valid JSON" \
    "Payload JSON parse failed (infra, not a task defect)" 0
fi

if [ "${1:-}" = "--merge" ]; then
  _open_run_log "${CASE_ID:-unknown}" "merge"
else
  _open_run_log "${CASE_ID:-unknown}" "${ATTEMPT:-1}"
  # Historical payloads omit team; that is team1. Named here so an infra
  # result emitted before the driver runs still carries it.
  export ORCH_TEAM="${TEAM:-team1}"
fi

# Host label is a refuse-on-mismatch cross-check only. It never selects a team.
# Missing file / missing team key: warn and proceed, unless
# ORCH_REQUIRE_HOST_LABEL=1. An empty payload.team is the historical team1
# payload, so a PRESENT label is compared against team1.
_host_label_value() {
  local f="$1"
  if [ ! -e "$f" ]; then
    echo missing
    return 0
  fi
  python3 -c '
import json, sys
path = sys.argv[1]
try:
    with open(path) as fh:
        data = json.load(fh)
except Exception:
    print("unreadable")
    sys.exit(0)
if not isinstance(data, dict):
    print("missing")
    sys.exit(0)
team = data.get("team")
if team is None or str(team).strip() == "":
    print("missing")
else:
    print(str(team).strip())
' "$f" 2>/dev/null || echo unreadable
}
HOST_LABEL="$(_host_label_value "$HOST_LABEL_FILE")"
HOST_LABEL="${HOST_LABEL:-unreadable}"
case "$HOST_LABEL" in
  missing|unreadable)
    log "WARN: host label ${HOST_LABEL} at ${HOST_LABEL_FILE} — proceeding without a team cross-check"
    if [ "${ORCH_REQUIRE_HOST_LABEL:-}" = "1" ]; then
      if [ "${1:-}" = "--merge" ]; then
        merge_refuse "error_class=infra host label required but ${HOST_LABEL} at ${HOST_LABEL_FILE}. Refusing before any repo access."
      fi
      emit "failed" "$BRANCH" 1 \
        "error_class=infra host label required but ${HOST_LABEL} at ${HOST_LABEL_FILE}. Refusing before any repo access." \
        "Host label required (infra, not a task defect)" 0
    fi
    ;;
  *)
    _payload_team="${TEAM:-team1}"
    if [ "$_payload_team" != "$HOST_LABEL" ]; then
      log "ERROR: host label mismatch payload.team=${TEAM:-<unset>} host=${HOST_LABEL}"
      if [ "${1:-}" = "--merge" ]; then
        merge_refuse "error_class=infra host label mismatch: payload team '${_payload_team}' host team '${HOST_LABEL}' (${HOST_LABEL_FILE}). Refusing before any repo access."
      fi
      emit "failed" "$BRANCH" 1 \
        "error_class=infra host label mismatch: payload team '${_payload_team}' host team '${HOST_LABEL}' (${HOST_LABEL_FILE}). Refusing before any repo access." \
        "Host label mismatch (infra, not a task defect)" 0
    fi
    log "Host label OK: ${HOST_LABEL}"
    ;;
esac

# Driver name only. The tool itself is selected by executing
# drivers/run-$DRIVER.sh — there is no per-tool branch here.
# Missing driver defaults to claude ONLY for no-team / team1.
if [ "${1:-}" != "--merge" ]; then
  if [ -z "$DRIVER" ]; then
    if [ -z "$TEAM" ] || [ "$TEAM" = "team1" ]; then
      DRIVER="claude"
    else
      export ORCH_TEAM="$TEAM"
      emit "failed" "$BRANCH" 1 \
        "error_class=infra driver required for ${TEAM}; refusing to default a non-team1 run" \
        "Driver required (infra, not a task defect)" 0
    fi
  fi
  export ORCH_DRIVER="$DRIVER"
  export ORCH_TEAM="${TEAM:-team1}"
  case "$DRIVER" in
    *[!a-z0-9_-]*)
      emit "failed" "$BRANCH" 1 \
        "error_class=infra unknown driver ${DRIVER}" \
        "Unknown driver (infra, not a task defect)" 0
      ;;
  esac
  if [ ! -x "$HERE/drivers/run-${DRIVER}.sh" ]; then
    emit "failed" "$BRANCH" 1 \
      "error_class=infra unknown driver ${DRIVER}" \
      "Unknown driver (infra, not a task defect)" 0
  fi
  export ORCH_DRIVER="$DRIVER"
  export ORCH_TEAM="${TEAM:-team1}"
fi

# After the pin checkout, re-exec a private copy so a later checkout cannot
# swap the wrapper or the driver under this run. The copy is what finishes
# the run. ORCH_RUNNER_REEXECED stops the second process from copying again.
reexec_snapshot() {
  if [ "${ORCH_RUNNER_REEXECED:-}" = "1" ]; then
    log "runner snapshot active: $0"
    return 0
  fi
  # Unpredictable name, mode 0700. The child is told this exact path; it
  # does not rebuild it from ORCH_LOG_TAG.
  local dest
  dest="$(mktemp -d /tmp/runner-XXXXXXXX 2>/dev/null)" || {
    log "WARN: runner snapshot mktemp failed — continuing in place"
    return 0
  }
  if ! chmod 0700 "$dest"; then
    log "WARN: runner snapshot chmod failed — continuing in place"
    rm -rf -- "$dest"
    return 0
  fi
  # Recorded only after mktemp. The exit trap removes this path. It is a
  # shell variable, not an export.
  _ORCH_OWNED_SNAP="$dest"
  if ! cp -a "$HERE/orchestrator-run.sh" "$dest/orchestrator-run.sh"; then
    log "WARN: runner snapshot copy failed — continuing in place"
    return 0
  fi
  if [ -d "$HERE/drivers" ]; then
    rm -rf "$dest/drivers"
    if ! cp -a "$HERE/drivers" "$dest/drivers"; then
      log "WARN: runner snapshot drivers copy failed — continuing in place"
      return 0
    fi
  fi
  chmod +x "$dest/orchestrator-run.sh" 2>/dev/null || true
  chmod +x "$dest/drivers/"*.sh 2>/dev/null || true
  local pf="/tmp/orch-payload-${ORCH_LOG_TAG}"
  if ! printf '%s' "$PAYLOAD" > "$pf"; then
    log "WARN: runner snapshot payload copy failed — continuing in place"
    return 0
  fi
  log "runner snapshot exec $dest/orchestrator-run.sh"
  export ORCH_RUNNER_SNAPSHOT="$dest"
  export ORCH_RUNNER_REEXECED=1
  # The copy is the same process image on the same tree. Do not fetch or
  # checkout again; the first process already did both. Pass the blessed
  # SHA so the child can prove HEAD did not move. Detach mode sets
  # BOOTSTRAP_PIN_SHA; off/ancestor run the tip, so HEAD is the check.
  local _pin_sha="${BOOTSTRAP_PIN_SHA:-}"
  if [ -z "$_pin_sha" ]; then
    _pin_sha="$(git -C "$HOME/grotap-agents" rev-parse HEAD 2>/dev/null || true)"
  fi
  export ORCH_BOOTSTRAP_PINNED_SHA="$_pin_sha"
  export ORCH_BOOTSTRAP_FETCH_DONE=1
  export ORCH_LOG_TAG ORCH_STARTED_AT
  exec bash "$dest/orchestrator-run.sh" "$@" < "$pf"
}

# ── Merge mode ───────────────────────────────────────────────────────────────
if [ "${1:-}" = "--merge" ]; then
  BRANCH="$(printf '%s' "$PAYLOAD" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("branch",""))')"
  repo_lock  # held until exit — merge mode checkouts/pulls the shared clone directly
  ensure_repo || { dump_run_log; python3 -c '
import json, sys
print(json.dumps({"merged": False,
                  "error": sys.argv[1] or "repo unavailable"}))
' "${BOOTSTRAP_PIN_FAIL:-}"; exit 1; }
  reexec_snapshot "$@"
  # ensure_repo fetches ONLY master, so on any host that didn't execute this
  # case origin/$BRANCH is missing (or stale) and the merge fails — which the
  # catch-all below used to misreport as "merge conflict". Fetch the branch
  # explicitly, force-updating the remote-tracking ref.
  git fetch origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" >> "$LOG" 2>&1 \
    || { dump_run_log; echo '{"merged": false, "error": "branch not found on origin"}'; exit 1; }
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
    dump_run_log
    echo '{"merged": true, "branch_deleted": true}'
    exit 0
  else
    git merge --abort >> "$LOG" 2>&1 || true
    dump_run_log
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
# A pin abort is an INFRASTRUCTURE fault, not a defect in the task. The
# orchestrator's evaluateRunnerResult only classifies timeout and api_exhausted
# as infra, so without this marker every case dispatched during a pin outage
# burns a retry strike and lands as `failed` for a reason unrelated to its own
# content — one bad pin churns the whole backlog. The marker is carried in the
# errors string because emit()'s positional contract has no error_class slot
# here; the orchestrator greps for it.
ensure_repo || {
  _EC=""
  [ -n "${BOOTSTRAP_PIN_FAIL:-}" ] && _EC="error_class=infra "
  emit "failed" "$BRANCH" 1     "${_EC}${BOOTSTRAP_PIN_FAIL:-Platform repo unavailable}"     "${BOOTSTRAP_PIN_FAIL:+Bootstrap pin check failed (infra, not a task defect)}${BOOTSTRAP_PIN_FAIL:-Could not clone/fetch grotap-platform}" 0
}
# Pin is on disk now. Finish the run from a private copy of this wrapper
# and drivers/ so the checkout cannot change the code under us.
reexec_snapshot "$@"

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

# Trust the fresh worktree in ~/.claude.json. A worktree Claude Code has never
# seen is untrusted, and an untrusted workspace silently DISCARDS every
# permissions.allow entry from .claude/settings.json ("Ignoring N
# permissions.allow entries ... this workspace has not been trusted"), so the
# run blocks on the first gated tool and dies with no commits (2026-09-14).
# flock + a per-process temp file: slots on this box stamp concurrently, and a
# shared .tmp path would let one runner clobber another's config (or read a
# half-written one) and leave its worktree untrusted.
if ! flock "$HOME/.claude.json.lock" python3 - "$WT" <<'TRUSTPY' >> "$LOG" 2>&1
import json, os, sys, tempfile
path, cfg = sys.argv[1], os.path.expanduser('~/.claude.json')
try:
    with open(cfg) as fh:
        data = json.load(fh)
except Exception:
    data = {}
entry = data.setdefault('projects', {}).setdefault(path, {})
if entry.get('hasTrustDialogAccepted') is not True:
    entry['hasTrustDialogAccepted'] = True
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(cfg) or '.', prefix='.claude.json.')
    try:
        with os.fdopen(fd, 'w') as fh:
            json.dump(data, fh)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, 0o600)
        os.replace(tmp, cfg)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    print('trusted workspace %s' % path)
TRUSTPY
then
  # Do NOT soft-fail. An untrusted workspace does not error — it silently drops
  # every permissions.allow entry and the run dies later with no commits, which
  # is exactly the failure mode this step exists to prevent. The stamp is a
  # no-op exit 0 when the entry is already true, so reaching here means a write
  # was needed and did not happen.
  emit "failed" "$BRANCH" 1 "Could not trust worktree"     "writing hasTrustDialogAccepted for $WT in ~/.claude.json failed" 0
fi

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

# ── Dispatch the named driver ────────────────────────────────────────────────
# No per-tool branch. run-$DRIVER.sh owns the model call. It must not retry
# or fall back across models; the graph owns retries. A non-success driver
# status is returned as-is (the Claude driver builds the historical
# "Claude CLI error:" errors string). cost.source=unknown fails closed.
DENY_NOTE=""
RESULT_TEXT=""
TOKENS=0
DR_STATUS=""
DR_ERRORS=""
DR_SUMMARY=""
# A non-empty but unparseable driver file used to die here under set -u
# (these two were only assigned inside the eval) and produced no JSON line.
DR_ERROR_CLASS=""
DR_COST_SOURCE=""
DR_PARSE_OK=0
DRIVER_RC=0
export COMPLEXITY LOG RUN_LOG
export ORCH_DRIVER="${ORCH_DRIVER:-$DRIVER}"
export ORCH_TEAM="${ORCH_TEAM:-${TEAM:-team1}}"
PROMPT_FILE="/tmp/orch-prompt-${ORCH_LOG_TAG}.txt"
DRIVER_RESULT_FILE="/tmp/orch-driver-${ORCH_LOG_TAG}.json"
export DRIVER_RESULT_FILE
printf '%s' "$PROMPT" > "$PROMPT_FILE"
chmod 600 "$PROMPT_FILE" 2>/dev/null || true
log "Dispatching driver=$DRIVER"
"$HERE/drivers/run-${DRIVER}.sh" "$WT" "$PROMPT_FILE" "$DRIVER_RESULT_FILE" 2>>"$RUN_LOG" || DRIVER_RC=$?
if [ ! -s "$DRIVER_RESULT_FILE" ]; then
  emit "failed" "$BRANCH" "${DRIVER_RC:-1}" \
    "error_class=infra driver ${DRIVER} produced no driver-result" \
    "Driver produced no result (infra, not a task defect)" 0
fi
eval "$(python3 - "$DRIVER_RESULT_FILE" <<'PY'
import json, shlex, sys
try:
    with open(sys.argv[1]) as fh:
        d = json.load(fh)
except Exception:
    print("DR_PARSE_OK=0")
    sys.exit(0)
if not isinstance(d, dict) or d.get("schema") != "driver-result/v1":
    print("DR_PARSE_OK=0")
    sys.exit(0)
tok = d.get("tokens") or {}
def n(v):
    try:
        return int(v or 0)
    except Exception:
        return 0
inp = n(tok.get("input"))
cached = n(tok.get("cached_input"))
cw = n(tok.get("cache_write_input"))
outp = n(tok.get("output"))
back = inp - cached - cw + outp
if back < 0:
    back = n(tok.get("total"))
cost = d.get("cost") if isinstance(d.get("cost"), dict) else {}
src = cost.get("source")
if src is None:
    src = ""
err_class = d.get("error_class")
print("DR_STATUS="+shlex.quote(str(d.get("status") or "failed")))
print("DR_ERRORS="+shlex.quote(str(d.get("errors") or "")))
print("DR_SUMMARY="+shlex.quote(str(d.get("summary") or "")))
print("DR_ERROR_CLASS="+shlex.quote("" if err_class is None else str(err_class)))
print("DR_COST_SOURCE="+shlex.quote(str(src)))
print("TOKENS="+str(back))
print("DR_PARSE_OK=1")
PY
)" || true
if [ "${DR_PARSE_OK:-0}" != "1" ]; then
  # Do not leave the driver's file for emit() to load. A JSON-looking
  # document can still say status success; replace it with our own
  # failed/infra result before the result line is built.
  python3 - "$DRIVER_RESULT_FILE" <<'PY'
import json, os, sys
path = sys.argv[1]
now = os.environ.get("ORCH_STARTED_AT") or None
driver = os.environ.get("ORCH_DRIVER") or None
doc = {
    "schema": "driver-result/v1",
    "team": os.environ.get("ORCH_TEAM") or None,
    "driver": driver,
    "driver_version": None,
    "tool_bin": None,
    "provider": None,
    "model": None,
    "profile": None,
    "status": "failed",
    "error_class": "infra",
    "summary": "Malformed driver result (infra, not a task defect)",
    "errors": "error_class=infra driver %s produced a malformed driver-result" % (driver or ""),
    "tokens": {"input": 0, "cached_input": 0, "cache_write_input": 0,
               "output": 0, "reasoning": 0, "total": 0},
    "cost": {"usd": None, "source": "not_priced", "price_table_version": None,
             "long_context_multiplier_applied": False},
    "attempts_inside_driver": 0,
    "session_id": None,
    "started_at": now,
    "ended_at": now,
}
with open(path, "w") as fh:
    json.dump(doc, fh)
    fh.write("\n")
PY
  emit "failed" "$BRANCH" "${DRIVER_RC:-1}" \
    "error_class=infra driver ${DRIVER} produced a malformed driver-result" \
    "Malformed driver result (infra, not a task defect)" 0
fi
# Drivers do not price a miss as success. source=unknown is a hard failure
# and is not a Claude fallback.
if [ "$DR_COST_SOURCE" = "unknown" ]; then
  log "ERROR: driver cost.source=unknown — failing closed (error_class=cost_unknown)"
  python3 - "$DRIVER_RESULT_FILE" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as fh:
    d = json.load(fh)
d["status"] = "failed"
d["error_class"] = "cost_unknown"
err = d.get("errors") or ""
if not str(err).startswith("error_class=cost_unknown"):
    d["errors"] = ("error_class=cost_unknown " + str(err)).strip()
with open(path, "w") as fh:
    json.dump(d, fh)
    fh.write("\n")
PY
  DR_STATUS="failed"
  DR_ERROR_CLASS="cost_unknown"
  case "$DR_ERRORS" in
    error_class=cost_unknown*) ;;
    *) DR_ERRORS="error_class=cost_unknown ${DR_ERRORS}" ;;
  esac
fi
if [ "$DR_STATUS" != "success" ]; then
  emit "failed" "$BRANCH" "$DRIVER_RC" "$DR_ERRORS" "${DR_SUMMARY:-Agent run failed}" "$TOKENS"
fi
# On success the driver's errors field is the tool-denial note (empty when
# nothing was denied). The no-commits guard below prepends it, same as before.
DENY_NOTE="$DR_ERRORS"
RESULT_TEXT="$DR_SUMMARY"


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

# ── Changed-file set — scopes every check below ──────────────────────────────
# Each check runs only for the package this branch actually touched. That
# matters most for tests: frontend's `test` script is `vitest run`, i.e. the
# WHOLE unit suite, so an unrelated package's (or a pre-existing master) red
# must never decide this branch's verdict.
#
# Scoping is only safe while the changed set is TRUSTWORTHY. It is derived from
# origin/master, so a missing/unfetched ref used to yield an EMPTY list, which
# silently skipped every check — a gate that never runs is a worse failure than
# a gate that runs too much. So: three independent sources, and if none of them
# succeeds (or they yield nothing) while commits exist, fall back to verifying
# EVERY package — never to verifying none.
_c_rc=1
_c1="$(git diff --name-only origin/master 2>/dev/null)"       && _c_rc=0
_c2="$(git diff --cached --name-only 2>/dev/null)"            && _c_rc=0
_c3="$(git diff --name-only origin/master..HEAD 2>/dev/null)" && _c_rc=0
CHANGED="$(printf '%s\n%s\n%s\n' "$_c1" "$_c2" "$_c3" | grep -v '^[[:space:]]*$' | sort -u)"

# Commits present? (same expression as the no-commits guard below.) Without
# commits there is nothing to verify and nothing to preserve, so the empty
# changed set is CORRECT there and must not trigger the verify-everything
# fallback — that run fails on the no-commits guard moments later anyway.
HAS_COMMITS=0
if git rev-parse --verify HEAD >/dev/null 2>&1 \
   && [ -n "$(git log origin/master..HEAD --oneline 2>/dev/null)" ]; then
  HAS_COMMITS=1
fi

CHANGED_TRUSTED=1
if [ "$HAS_COMMITS" = "1" ] && { [ "$_c_rc" -ne 0 ] || [ -z "$CHANGED" ]; }; then
  CHANGED_TRUSTED=0
fi

# Did $1 change? An untrusted changed set answers YES for every package, which
# is exactly the unscoped pre-2026-09-16 behaviour.
pkg_changed() {
  [ "$CHANGED_TRUSTED" = "1" ] || return 0
  printf '%s\n' "$CHANGED" | grep -q "^$1/"
}

add_check() { VERIFY_CHECKS="${VERIFY_CHECKS:+$VERIFY_CHECKS
}$1"; }
add_fail()  { VALID_ERR="${VALID_ERR:+$VALID_ERR

}### $1:
$(printf '%s' "$2" | tail -c 2000)"; }

# Make the fallback visible in the evidence the review node + human gate read,
# so "everything was verified" is never confused with "nothing was".
if [ "$CHANGED_TRUSTED" != "1" ]; then
  log "WARN: changed-file list unavailable — verifying ALL packages (scoping off)"
  add_check "changed-file scoping: unavailable (verifying all packages)"
fi

# Hard build/tsc verification for a changed TS package. mode = build|tsc.
verify_ts() {
  local pkg="$1" mode="$2"
  pkg_changed "$pkg" || return 0
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
if pkg_changed frontend && [ -d frontend/node_modules ]; then
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

# Run a package `test` script if one exists, for CHANGED packages only. The
# frontend script is `vitest run` (the whole suite), so an unscoped loop let one
# red test on master fail every concurrent branch that touched frontend/.
for pkg in frontend agent-worker orchestrator ingestion-worker backend; do
  pkg_changed "$pkg" || continue
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
  # DENY_NOTE first: "no commits produced" on its own is exactly the string
  # people misread as an API/credit fault.
  emit "failed" "$BRANCH" 1 "${DENY_NOTE:+$DENY_NOTE }No commits produced on $BRANCH" "Agent made no committed changes" "$TOKENS" "$(build_verify_json 0)"
fi

# Record the verdict — do NOT exit on it yet. A failing gate used to call emit()
# here, and emit() EXITS, so the push below never ran and the agent's committed
# work stayed on the box with no preservation path (CASE-20260914-E01AB5: a
# complete 8-file implementation stranded on agent-04; the strike cap then parks
# the case for good). The commit must always reach origin — the same intent as
# dispatch.sh's api_exhausted branch, which pushes partial work before reporting
# the failure, and the same order the platform repo's copy of this runner uses
# (record result → push → emit). The VERDICT is unchanged: a failed
# verification is still reported "failed", with VALID_ERR intact.
VERIFY_PASSED=1
[ -n "$VALID_ERR" ] && VERIFY_PASSED=0

# ── Push branch (orchestrator decides on merge later, after human gate) ──────
repo_lock  # pushes update shared remote-tracking refs — same race as fetch
# Refresh the lease basis first: ensure_repo fetches ONLY master, so a leftover
# remote branch from a previous attempt leaves the remote-tracking ref stale or
# absent and --force-with-lease fails "[rejected] (stale info)" on EVERY retry
# (BAA42B/F4D19E each burned 3 strikes on this, 2026-07-05), and drop the
# tracking ref when the remote branch is gone (CASE-20260910-E6CF1E:
# gate-deleted branch → 'stale info' on every retry).
git fetch origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" >> "$LOG" 2>&1 \
  || git update-ref -d "refs/remotes/origin/$BRANCH" >> "$LOG" 2>&1 || true
# --force-with-lease is still correct on the preserve-on-failure path: the lease
# basis was just refreshed above, and every attempt rebuilds $BRANCH from
# origin/master in a fresh worktree, so the only thing this can overwrite is an
# EARLIER ATTEMPT OF THIS SAME CASE — which is only ever retried because it
# failed, and whose successor carries its prior_errors. It can never reach
# master, and a passing attempt is never followed by another attempt on the same
# branch. (Plain --force would be unsafe; do not weaken this to that.)
PUSH_OK=1
git push -u origin "$BRANCH" --force-with-lease >> "$LOG" 2>&1 || PUSH_OK=0
repo_unlock

if [ "$PUSH_OK" -ne 1 ]; then
  # Push failed: report that, but never drop the verification errors — a retry
  # must see the real cause, not just "git push failed".
  log "=== Push FAILED case=$CASE_ID branch=$BRANCH verify_passed=$VERIFY_PASSED ==="
  emit "failed" "$BRANCH" 1 "${VALID_ERR:+$VALID_ERR

}### git push failed:
Could not push $BRANCH to origin — see $LOG on $(hostname)" \
    "Could not push branch" "$TOKENS" "$(build_verify_json "$VERIFY_PASSED")"
fi

if [ "$VERIFY_PASSED" -ne 1 ]; then
  # Work is safe on origin; the case still fails, with the real errors.
  log "=== Verification FAILED case=$CASE_ID branch=$BRANCH PUSHED (work preserved) checks=[$VERIFY_CHECKS] ==="
  emit "failed" "$BRANCH" 1 "$VALID_ERR" "Verification failed" "$TOKENS" "$(build_verify_json 0)"
fi

log "=== Success case=$CASE_ID branch=$BRANCH tokens=$TOKENS checks=[$VERIFY_CHECKS] ==="
emit "success" "$BRANCH" 0 "" "$RESULT_TEXT" "$TOKENS" "$(build_verify_json 1)"
