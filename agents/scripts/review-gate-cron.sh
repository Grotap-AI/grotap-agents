#!/usr/bin/env bash
# Review gate — runs Claude unattended against the change_review backlog.
# Installed on agent-06: */15 * * * *  (every 15 min; empty queue exits in <5s,
# so the only real cost is when there is actually something to review).
#
# Manual run: bash /home/agent/grotap-agents/agents/scripts/review-gate-cron.sh
set -uo pipefail

AGENT_HOME="/home/agent"
AGENTS_REPO="$AGENT_HOME/grotap-agents"
PLATFORM_REPO="$AGENT_HOME/grotap-platform"
LOCK="$AGENT_HOME/.review-gate.lock"
LOG="$AGENT_HOME/logs/review-gate.log"
TASK="$AGENTS_REPO/agents/scripts/review-gate-task.md"
TIMEOUT_SECS=7200   # 2h hard cap

mkdir -p "$AGENT_HOME/logs"
exec >>"$LOG" 2>&1
echo "=== review-gate run $(date -u +%FT%TZ) ==="

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
#     We deliberately do NOT try to catch/classify git's ref-lock error text:
#     matching on "cannot lock ref" is brittle and silently stops working the
#     moment git rewords it.
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
  cd "$1" 2>>"$STDERR_FILE" \
    && git fetch origin +refs/heads/master:refs/remotes/origin/master 2>>"$STDERR_FILE" \
    && git checkout master -q 2>>"$STDERR_FILE" \
    && git reset --hard origin/master -q 2>>"$STDERR_FILE"
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

GIT STDERR:
$(tail -c 2000 "$STDERR_FILE")"
  return 1
}

sync_with_retry "$AGENTS_REPO"   "grotap-agents"   || exit 1
sync_with_retry "$PLATFORM_REPO" "grotap-platform" || exit 1

# Quick exit when the queue is empty. Must match the task prompt's queue shape:
# change_review PLUS awaiting_human cases parked at the orchestrator human gate
# (latest dispatch row awaiting_review). NB: single quotes — DATABASE_URL must be
# expanded INSIDE the doppler-injected environment, not by this outer shell.
QUEUE=$(doppler run --project grotap --config prd -- sh -c \
  'psql "$DATABASE_URL" -Atc "SELECT count(*) FROM (SELECT case_id FROM pipeline_cases WHERE status='"'"'change_review'"'"' UNION SELECT c.case_id FROM pipeline_cases c WHERE c.status='"'"'awaiting_human'"'"' AND EXISTS (SELECT 1 FROM pipeline_dispatch_log dl WHERE dl.case_id=c.case_id AND dl.status='"'"'awaiting_review'"'"')) q"' 2>/dev/null || echo "?")
echo "queue: $QUEUE reviewable cases (change_review + parked awaiting_review)"
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
  # Leave master untouched on failure paths where claude died mid-merge without pushing.
  cd "$PLATFORM_REPO"
  if ! git diff --quiet origin/master...HEAD 2>/dev/null; then
    echo "resetting unpushed local merges after failure"
    git reset --hard origin/master -q
  fi
  fail_hold "review-gate claude run exited rc=$RC after up-to-2h. Local unpushed merges were reset. See $LOG on agent-06."
fi

# D2: prune AFTER all gate work, never before it, and never able to fail the
# run. A standalone daily janitor (agents/scripts/git-prune-janitor.sh) also
# exists; this is the belt-and-braces pass so refs stay tidy between janitor runs.
for repo in "$AGENTS_REPO" "$PLATFORM_REPO"; do
  (cd "$repo" && git fetch origin --prune -q) || true
done

echo "=== review-gate done $(date -u +%FT%TZ) rc=$RC ==="
exit 0
