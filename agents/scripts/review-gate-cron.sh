#!/usr/bin/env bash
# Review gate — runs Claude unattended against the change_review backlog.
#
# Installed on agent-06 as systemd review-gate.timer -> review-gate.service,
# every 15 min (empty queue exits in <5s, so the only real cost is when there
# is actually something to review). The name still says "cron" for continuity
# with every log line and hold that references it.
#
# NOT a crontab entry any more (CASE-20260729-5E756A). Under cron this script's
# claude run lived in cron.service's own cgroup, unbounded: on 2026-07-29 two of
# its pytest processes reached 4.9 GB and 2.3 GB RSS on a 7.6 GB box, and
# `timeout` could not reap the detached grandchildren, so orphans stayed charged
# to cron.service for 27 hours. Each OOM kill stopped the cron DAEMON
# (OOMPolicy=stop) until systemd latched it off — no cron ran on this box for
# 2d 8h, which is how the daily Neon backup silently missed three nights.
# The unit gives it its own cgroup, MemoryMax=5G and KillMode=control-group.
# DO NOT move it back into a crontab.
#
# Manual run: bash /home/agent/grotap-agents/agents/scripts/review-gate-cron.sh
set -uo pipefail

AGENT_HOME="/home/agent"
AGENTS_REPO="${AGENTS_REPO:-$AGENT_HOME/grotap-agents}"
# Dedicated clone, deliberately NOT the shared $AGENT_HOME/grotap-platform tree
# (this script hard-resets it, which is how a peer's in-flight work gets swept).
# Must be AGENT-WRITABLE: the unit runs User=agent and /var/cache is root-owned
# drwxr-xr-x, so the previous /var/cache/review-gate-clone default could never be
# created here — the clone below failed permission-denied and exited 1, taking the
# whole gate down. See CASE-20260809-GATECLONE.
PLATFORM_REPO="${PLATFORM_REPO:-$AGENT_HOME/.cache/review-gate-clone}"
LOCK="${LOCK:-$AGENT_HOME/.review-gate.lock}"
LOG="${LOG:-$AGENT_HOME/logs/review-gate.log}"
TASK="${TASK:-$AGENTS_REPO/agents/scripts/review-gate-task.md}"
TIMEOUT_SECS=7200   # 2h hard cap

mkdir -p "$AGENT_HOME/logs"
exec >>"$LOG" 2>&1
echo "=== review-gate run $(date -u +%FT%TZ) agents=$AGENTS_REPO platform=$PLATFORM_REPO ==="

# Single-flight lock (stale after 3h)
if [ -e "$LOCK" ] && [ "$(( $(date +%s) - $(stat -c %Y "$LOCK") ))" -lt 10800 ]; then
  echo "SKIP: lock held ($(cat "$LOCK" 2>/dev/null))"; exit 0
fi
echo "$$ $(date -u +%FT%TZ)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

fail_hold() {
  curl -s -X POST https://api.grotap.com/human-intervention/ -H "Content-Type: application/json" -d "{
    \"task_id\": \"review-gate-failure-$(date -u +%F)\",
    \"task_title\": \"Review gate cron FAILED on agent-06\",
    \"category\": \"manual_verification\", \"priority\": \"high\", \"created_by\": \"review-gate-cron\",
    \"description\": $(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()[:2500]))')
  }" >/dev/null || true
}

# ── bootstrap sync (CASE-20260725-0374AD / GATEBOOT) ─────────────────────────
# Both repos are synced to origin/master with an escalating-backoff retry.
#
# D1: NO --prune on the hot path. Pruning races concurrent branch recreation —
#     the fleet and orchestrator push/delete case-* branches continuously — and
#     that race is what produced the intermittent "could not sync" holds
#     (2026-07-25 02:30Z and 06:00Z). The gate only needs origin/master to be
#     current; stale remote-tracking refs for deleted case branches are
#     harmless here. Pruning happens at the END of this script (D2), || true.
#     AMENDED 2026-07-30 (CASE-20260730-9B4988): this block used to say we
#     deliberately do NOT classify git's error text, because matching on
#     "cannot lock ref" is brittle. That caution cost more than it saved — with
#     no classification the hold showed raw stderr, a human read "Permission
#     denied" as a permissions bug, was told it was really a race, and the
#     genuine root-ownership fault got waved off twice. classify_sync_failure()
#     (D7) now names the fault, and is written so that an unrecognised message
#     degrades to "unclassified" plus the raw stderr — never to a wrong answer.
# D3: git stderr is captured (no -q on the fetch) and the last 2000 chars go
#     into the hold, so the next failure is diagnosable instead of guessed at.
# D5: the agents-repo sync gets the SAME treatment — it previously had no retry
#     and no failure check at all, so a failed fetch silently continued against
#     a stale agents checkout.
STDERR_FILE="$(mktemp)"
trap 'rm -f "$LOCK" "$STDERR_FILE"' EXIT

sync_repo() {
  # $1 = repo path. Fetch ONLY master, then hard-reset onto it.
  #
  # The refspec is written out in full on purpose. Bare `git fetch origin master`
  # only reliably updates refs/remotes/origin/master via git's opportunistic
  # remote-tracking update (verified present on git 2.53, and agent-06 is on
  # 2.43) — but the explicit forced refspec guarantees it on every version, and
  # `git reset --hard origin/master` below reads exactly that ref. The leading +
  # keeps a force-push on master from wedging the gate.
  # cd is redirected too: a missing/renamed checkout is exactly the kind of
  # failure the hold needs to name, and bash's own "No such file or directory"
  # goes to the shell's stderr, not git's.
  #
  # D6 (CASE-20260730-9B4988): the whole fetch→checkout→reset sequence runs
  # under ONE grotap-git-lock hold on the clone. Locking each command
  # separately would be pointless — the */5 watchdog fetch lands between our
  # fetch and our reset and we are racing again. This gate previously used its
  # own ~/.review-gate.lock, which excluded other GATE runs and nothing else;
  # grotap-git-lock is shared with every other writer, root and agent alike.
  grotap-git-lock "$1" /bin/bash -c '
      cd "$1" \
        && git fetch origin +refs/heads/master:refs/remotes/origin/master \
        && git checkout master -q \
        && git reset --hard origin/master -q
    ' _ "$1" 2>>"$STDERR_FILE"
}

# D7 (CASE-20260730-9B4988): say WHICH failure this is.
#
# git reports two unrelated faults in ways that read like each other, and the
# gate used to paste raw stderr into the hold and let a human guess:
#
#   RACE       "cannot lock ref 'refs/...': is at X but expected Y"
#              Intermittent, different SHA each time, gone next tick. Retries help.
#
#   OWNERSHIP  "unable to unlink old '<path>': Permission denied"
#              "unable to create file '<path>': Permission denied"
#              Deterministic — same path, every attempt, for hours. Root wrote
#              into this agent-owned clone. RETRIES CAN NEVER WIN IT.
#
# Guessing wrong costs days: the Permission-denied variant was twice waved off
# as "just the race", so the retry loop got tuned while the actual cause (root
# jobs and root SSH sessions writing into /home/agent/grotap-platform) stayed
# put. Classify at failure time, while the evidence still exists — by the time
# anyone looks, the strays are usually cleaned up and the tree looks innocent.
classify_sync_failure() {
  local repo="$1" me strays
  me="$(id -un)"
  strays="$(find "$repo" -not -user "$me" -not -path '*/node_modules/*' \
              -printf '%u:%g %p\n' 2>/dev/null | head -25)"

  if [ -n "$strays" ]; then
    printf 'CAUSE: OWNERSHIP, NOT A RACE.\n'
    printf '%s holds paths that user "%s" cannot replace. Retrying can never fix\n' "$repo" "$me"
    printf 'this; the writer that created them must stop, or clone-guard must repair them.\n\n'
    printf 'Non-%s paths at failure time:\n%s\n' "$me" "$strays"
  elif grep -q 'cannot lock ref' "$STDERR_FILE" 2>/dev/null; then
    printf 'CAUSE: GIT REF RACE — a concurrent writer moved the same ref.\n'
    printf 'Expected to be transient. If it persists, a writer is bypassing\n'
    printf 'grotap-git-lock. git processes running right now:\n%s\n' \
           "$(pgrep -a git 2>/dev/null | head -10)"
  elif grep -qE 'Permission denied' "$STDERR_FILE" 2>/dev/null; then
    printf 'CAUSE: Permission denied, but every path is %s-owned as of now.\n' "$me"
    printf 'The stray was almost certainly cleaned up between the failure and this\n'
    printf 'check — that is the known signature, not evidence against ownership.\n'
    printf 'See /var/log/grotap-clone-guard.log for what it repaired and when.\n'
  else
    printf 'CAUSE: unclassified — see git stderr below.\n'
  fi
}

# D4: 4 attempts (initial + 15s / 45s / 90s) ≈ 2.5 min worst case. The */15
# cron still leaves ~12 min of cycle even if every retry is used.
sync_with_retry() {
  local repo="$1" label="$2" delay
  for delay in 0 15 45 90; do
    [ "$delay" -gt 0 ] && { echo "$label sync failed — retrying in ${delay}s"; sleep "$delay"; }
    echo "--- $label sync attempt (after ${delay}s) ---" >>"$STDERR_FILE"
    if sync_repo "$repo"; then
      return 0
    fi
  done
  fail_hold "bootstrap failed: could not sync $label to origin/master (after 4 attempts)

$(classify_sync_failure "$repo")

GIT STDERR:
$(tail -c 2000 "$STDERR_FILE")"
  return 1
}

# ── dedicated platform clone bootstrap ────────────────────────────────────────
# If PLATFORM_REPO does not yet exist, clone it now. Explicit exit-status
# checking — || true would silently continue against a missing tree and the
# subsequent sync_with_retry would then fail with a confusing "No such file"
# rather than a clear clone error.
mkdir -p "$(dirname "$PLATFORM_REPO")"
if [ ! -d "$PLATFORM_REPO/.git" ]; then
  echo "bootstrapping dedicated platform checkout → $PLATFORM_REPO"
  if ! git clone https://github.com/Grotap-AI/grotap-platform.git "$PLATFORM_REPO" 2>>"$STDERR_FILE"; then
    fail_hold "bootstrap: git clone to $PLATFORM_REPO failed.

GIT STDERR:
$(tail -c 2000 "$STDERR_FILE")"
    exit 1
  fi
  echo "clone complete"
fi

sync_with_retry "$AGENTS_REPO"   "grotap-agents"   || exit 1
sync_with_retry "$PLATFORM_REPO" "grotap-platform" || exit 1

# Quick exit when the queue is empty. Must match the task prompt's queue shape:
# change_review PLUS awaiting_human cases parked at the orchestrator human gate
# (latest dispatch row awaiting_review). db.py prints a header row then the value;
# tail -1 extracts the count.
QUEUE=$(cd "$PLATFORM_REPO" && doppler run --project grotap --config prd -- \
  python3 scripts/db.py "SELECT count(*) FROM (SELECT case_id FROM pipeline_cases WHERE status='change_review' UNION SELECT c.case_id FROM pipeline_cases c WHERE c.status='awaiting_human' AND EXISTS (SELECT 1 FROM pipeline_dispatch_log dl WHERE dl.case_id=c.case_id AND dl.status='awaiting_review')) q" \
  2>/dev/null | tail -1 || echo "?")
echo "queue: $QUEUE reviewable cases (change_review + parked awaiting_review)"
[[ "$QUEUE" =~ ^[0-9]+$ ]] || { echo "FATAL: QUEUE is non-numeric ('$QUEUE') — accessor broken"; exit 1; }
if [ "$QUEUE" = "0" ]; then echo "queue empty — nothing to do"; exit 0; fi

# Run Claude with the standing task. Doppler injects DATABASE_URL etc. for the
# psql/API calls the task makes. Bypass permissions: this box is a headless runner.
cd "$PLATFORM_REPO"
timeout "$TIMEOUT_SECS" doppler run --project grotap --config prd -- \
  claude -p "$(cat "$TASK")" \
    --permission-mode bypassPermissions \
    --max-turns 400
RC=$?
echo "claude exit: $RC"

if [ "$RC" -ne 0 ]; then
  # Leave master untouched on failure paths where claude died mid-merge without
  # pushing. Under the lock (D6) — this is a hard reset of the shared clone and
  # is exactly the kind of write that used to collide with the */5 watchdog.
  grotap-git-lock "$PLATFORM_REPO" /bin/bash -c '
      cd "$1" || exit 0
      if ! git diff --quiet origin/master...HEAD 2>/dev/null; then
        echo "resetting unpushed local merges after failure"
        git reset --hard origin/master -q
      fi
    ' _ "$PLATFORM_REPO"
  fail_hold "review-gate claude run exited rc=$RC after up-to-2h. Local unpushed merges were reset. See $LOG on agent-06."
fi

# D2: prune AFTER all gate work, never before it, and never able to fail the
# run. A standalone daily janitor (agents/scripts/git-prune-janitor.sh) also
# exists; this is the belt-and-braces pass so refs stay tidy between janitor runs.
# Under the lock too (D6): --prune rewrites many refs at once, so it is the most
# collision-prone operation the gate performs, not the least.
for repo in "$AGENTS_REPO" "$PLATFORM_REPO"; do
  grotap-git-lock "$repo" /bin/bash -c 'cd "$1" && git fetch origin --prune -q' _ "$repo" || true
done

echo "=== review-gate done $(date -u +%FT%TZ) rc=$RC ==="
exit 0
