#!/bin/bash
# agents/tests/test_repo_lock_timeout.sh
#
# Cover for the PROCEED-UNLOCKED path of repo_lock() in
# agents/scripts/orchestrator-run.sh — the live fleet runner.
#
#   repo_lock()   { exec 9>"$REPO_LOCK"; flock -w 300 9 || log "WARN: repo lock timeout — proceeding unlocked"; }
#   repo_unlock() { exec 9>&- 2>/dev/null || true; }
#
# THIS IS A TEST, NOT A FIX. Failing open on timeout is the INTENDED production
# path and it stays (decision of record, grotap-platform
# scripts/hi_clarification_sweep_0809.py:38): making the timeout fatal trades a
# rare unlocked fetch for a guaranteed failed dispatch, and a failed dispatch is
# far more expensive — it burns the run, leaves a dispatch_log row, and strands
# every dependent case at awaiting_deps. Five minutes of contention on the
# shared clone also means something is already badly wrong upstream, and
# aborting there hides it behind a generic dispatch failure instead of leaving
# the WARN in the runner log. Scope boundary from that record: do not change
# -w 300, do not wrap it in set -e semantics, do not make it fatal.
#
#   L1  the production text still says: fd 9, flock with a wait, non-fatal ||,
#       a log() on the failure branch, no exit/return  (scope-boundary guard)
#   L2  lock held past the wait -> WARN is emitted, repo_lock returns 0, and
#       execution CONTINUES into the git work
#   L3  no contention -> lock acquired, no WARN, exit 0
#   L4  repo_unlock releases, so the next repo_lock acquires immediately
#
# The production -w 300 is NOT edited: the driver is derived from the real lines
# with the wait rewritten to 2s IN THE TEST COPY ONLY, and L1 asserts the
# production value is still 300. Delete the flock from the runner and L1/L2 fail.
#
# No SSH, no network, no fleet host. Usage:
#   bash agents/tests/test_repo_lock_timeout.sh [--verbose]

set -uo pipefail
VERBOSE=0; [[ "${1:-}" == "--verbose" ]] && VERBOSE=1

PASS=0; FAIL=0
TMP=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$SCRIPT_DIR/../scripts/orchestrator-run.sh"
HOLDER_PID=""

cleanup() {
  [[ -n "$HOLDER_PID" ]] && kill "$HOLDER_PID" 2>/dev/null
  [[ -n "$HOLDER_PID" ]] && wait "$HOLDER_PID" 2>/dev/null
  rm -rf "$TMP"
  return 0
}
trap 'cleanup' EXIT

vlog() { [[ $VERBOSE -eq 1 ]] && printf '  [dbg] %s\n' "$*" || true; }
check() {
  local desc="$1" ok="$2"
  if [[ "$ok" == "true" ]]; then PASS=$((PASS+1)); printf 'PASS: %s\n' "$desc"
  else FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$desc"; fi
}

bash -n "$RUNNER" || { echo "FATAL: runner does not parse"; exit 1; }

# flock is util-linux: present on the fleet (Ubuntu), absent in Git Bash. A shim
# would make every assertion here vacuous, so say so and stop rather than
# reporting a green run that tested nothing.
if ! command -v flock >/dev/null 2>&1; then
  echo "SKIPPED: flock(1) is not available on this host — the locking path cannot" >&2
  echo "  be exercised and a shim would only fake it. This is an ENVIRONMENT gap," >&2
  echo "  not a code failure. Run this test on a fleet host or any Linux box." >&2
  exit 2
fi

# ─── Derive a fast driver from the REAL lines ────────────────────────────────
DERIVED="$TMP/derived-repo-lock.sh"
{
  grep -E '^REPO_LOCK=' "$RUNNER"
  grep -E '^repo_lock\(\)' "$RUNNER"
  grep -E '^repo_unlock\(\)' "$RUNNER"
} > "$DERIVED.raw" 2>/dev/null || true
PROD_WAIT=$(grep -oE 'flock[[:space:]]+-w[[:space:]]+[0-9]+[[:space:]]+9' "$DERIVED.raw" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
sed "s/flock -w ${PROD_WAIT:-300} 9/flock -w 2 9/" "$DERIVED.raw" > "$DERIVED"
vlog "derived: $(cat "$DERIVED")"

echo "L1: the production repo_lock still fails OPEN, on fd 9, after a 300s wait"
check "L1: repo_lock() found in the runner" \
  "$( grep -qE '^repo_lock\(\)' "$RUNNER" && echo true || echo false )"
check "L1: it opens fd 9 on \$REPO_LOCK" \
  "$( grep -qE '^repo_lock\(\).*exec 9>"\$REPO_LOCK"' "$RUNNER" && echo true || echo false )"
check "L1: it takes an flock on fd 9 with a wait" \
  "$( [[ -n "$PROD_WAIT" ]] && echo true || echo false )"
check "L1: the wait is still 300s (decision of record: do not change it)" \
  "$( [[ "$PROD_WAIT" == "300" ]] && echo true || echo false )"
check "L1: the timeout branch is non-fatal — it logs, it does not exit/return" \
  "$( grep -E '^repo_lock\(\)' "$RUNNER" | grep -qE '\|\|[[:space:]]*log ' \
      && ! grep -E '^repo_lock\(\)' "$RUNNER" | grep -qE '\|\|[[:space:]]*(exit|return|false)' \
      && echo true || echo false )"
check "L1: the WARN names what actually happens (proceeding unlocked)" \
  "$( grep -E '^repo_lock\(\)' "$RUNNER" | grep -qF 'proceeding unlocked' && echo true || echo false )"
check "L1: repo_unlock closes fd 9" \
  "$( grep -E '^repo_unlock\(\)' "$RUNNER" | grep -qF 'exec 9>&-' && echo true || echo false )"
check "L1: the derived driver still carries the real flock call" \
  "$( grep -qE 'flock[[:space:]]+-w[[:space:]]+2[[:space:]]+9' "$DERIVED" && echo true || echo false )"

# ─── A local bare remote so the "git work" after the lock is real ────────────
REMOTE="$TMP/remote.git"; MAIN="$TMP/main"
git init -q --bare "$REMOTE"
git -C "$REMOTE" symbolic-ref HEAD refs/heads/master
git clone -q "$REMOTE" "$MAIN" 2>/dev/null
git -C "$MAIN" config user.email ci@test; git -C "$MAIN" config user.name ci
printf 'init\n' > "$MAIN/file.txt"
git -C "$MAIN" add file.txt; git -C "$MAIN" commit -qm init; git -C "$MAIN" push -q origin master 2>/dev/null

LOCK_FILE="$TMP/.grotap-platform.git.lock"   # $HOME is $TMP below, so this IS $REPO_LOCK
_start_holder() {
  ( exec 9>"$LOCK_FILE"; flock -x 9; sleep 30 ) &
  HOLDER_PID=$!
  sleep 0.5
}
_stop_holder() {
  [[ -n "$HOLDER_PID" ]] && kill "$HOLDER_PID" 2>/dev/null
  [[ -n "$HOLDER_PID" ]] && wait "$HOLDER_PID" 2>/dev/null
  HOLDER_PID=""
  return 0
}

echo "L2: lock held past the wait → WARN, return 0, and the git work still runs"
{
  _start_holder
  OUT="$TMP/l2.out"; RC=0
  (
    set -uo pipefail
    export HOME="$TMP"
    LOG="$TMP/l2.log"; : > "$LOG"
    log() { echo "[t] $*" >> "$LOG"; }
    . "$DERIVED"
    repo_lock
    echo "REPO_LOCK_RC=$?"
    git -C "$MAIN" fetch origin --quiet || { sleep 1; git -C "$MAIN" fetch origin --quiet; }
    echo "CONTINUED_TO_GIT_WORK=1"
    repo_unlock
  ) > "$OUT" 2>&1 || RC=$?
  vlog "L2 exit=$RC out=$(cat "$OUT") log=$(cat "$TMP/l2.log" 2>/dev/null)"

  check "L2: the caller exits 0 (the timeout is not fatal)" \
    "$( [[ $RC -eq 0 ]] && echo true || echo false )"
  check "L2: repo_lock itself returned 0" \
    "$( grep -q 'REPO_LOCK_RC=0' "$OUT" && echo true || echo false )"
  check "L2: the WARN line is emitted through log()" \
    "$( grep -qF 'WARN: repo lock timeout' "$TMP/l2.log" 2>/dev/null && echo true || echo false )"
  check "L2: execution CONTINUED into the git work" \
    "$( grep -q 'CONTINUED_TO_GIT_WORK=1' "$OUT" && echo true || echo false )"
  check "L2: it did NOT abort — nothing aborted/exiting on the way through" \
    "$( ! grep -qiE 'abort|exiting' "$OUT" && echo true || echo false )"
  _stop_holder
}

echo "L3: no contention → lock acquired, no WARN, exit 0"
{
  OUT="$TMP/l3.out"; RC=0
  (
    set -uo pipefail
    export HOME="$TMP"
    LOG="$TMP/l3.log"; : > "$LOG"
    log() { echo "[t] $*" >> "$LOG"; }
    . "$DERIVED"
    repo_lock
    git -C "$MAIN" fetch origin --quiet
    echo "CONTINUED_TO_GIT_WORK=1"
    repo_unlock
  ) > "$OUT" 2>&1 || RC=$?
  vlog "L3 exit=$RC out=$(cat "$OUT")"

  check "L3: exits 0" "$( [[ $RC -eq 0 ]] && echo true || echo false )"
  check "L3: no WARN when the lock is free" \
    "$( ! grep -qF 'WARN: repo lock timeout' "$TMP/l3.log" 2>/dev/null && echo true || echo false )"
  check "L3: git work ran" \
    "$( grep -q 'CONTINUED_TO_GIT_WORK=1' "$OUT" && echo true || echo false )"
}

echo "L4: repo_unlock releases the lock for the next holder"
{
  OUT="$TMP/l4.out"; RC=0
  (
    set -uo pipefail
    export HOME="$TMP"
    LOG="$TMP/l4.log"; : > "$LOG"
    log() { echo "[t] $*" >> "$LOG"; }
    . "$DERIVED"
    repo_lock          # take it
    repo_unlock        # give it back
    ( exec 9>"$LOCK_FILE"; flock -w 2 9 && echo "SECOND_ACQUIRE=ok" || echo "SECOND_ACQUIRE=timeout" )
  ) > "$OUT" 2>&1 || RC=$?
  vlog "L4 exit=$RC out=$(cat "$OUT")"

  check "L4: a second acquire succeeds after repo_unlock" \
    "$( grep -q 'SECOND_ACQUIRE=ok' "$OUT" && echo true || echo false )"
  check "L4: no WARN on either acquire" \
    "$( ! grep -qF 'WARN: repo lock timeout' "$TMP/l4.log" 2>/dev/null && echo true || echo false )"
}

echo ""
printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
