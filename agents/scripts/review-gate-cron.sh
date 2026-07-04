#!/usr/bin/env bash
# Daily review gate — runs Claude unattended against the change_review backlog.
# Installed on agent-06: 0 10 * * *  (2h before the noon dispatch so merges land
# first and released awaiting_deps children ride the noon window).
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
    \"description\": $(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()[:1500]))')
  }" >/dev/null || true
}

# Sync both repos to latest master
cd "$AGENTS_REPO"   && git fetch origin -q && git reset --hard origin/master -q
cd "$PLATFORM_REPO" && git fetch origin --prune -q && git checkout master -q && git reset --hard origin/master -q \
  || { fail_hold "bootstrap failed: could not sync grotap-platform to origin/master"; exit 1; }

# Quick exit when the queue is empty
QUEUE=$(doppler run --project grotap --config prd -- psql "$DATABASE_URL" -Atc \
  "SELECT count(*) FROM pipeline_cases WHERE status='change_review'" 2>/dev/null || echo "?")
echo "queue: $QUEUE change_review cases"
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
echo "=== review-gate done $(date -u +%FT%TZ) rc=$RC ==="
exit 0
