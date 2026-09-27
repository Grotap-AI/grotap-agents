#!/bin/bash
# health-monitor.sh — Runs on Agent-06 via cron every 5 minutes.
# Polls all production endpoints + agent servers.
# On 3 consecutive failures, triggers deploy-executor.
# Usage: bash /home/agent/scripts/health-monitor.sh
set -uo pipefail

# Defaults are the agent-06 cron paths. The HEALTH_MONITOR_* variables exist
# so a test can point logs, the roster, and ssh/ssh-key-for at stubs.
LOG="${HEALTH_MONITOR_LOG:-/home/agent/logs/health-monitor.log}"
STATE_DIR="${HEALTH_MONITOR_STATE_DIR:-/home/agent/state}"
ALERT_LOG="${HEALTH_MONITOR_ALERT_LOG:-/home/agent/logs/deploy-alerts.log}"
mkdir -p "$(dirname "$LOG")" "$(dirname "$ALERT_LOG")" "$STATE_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
OVERALL="OK"

# ── HTTP endpoint checks ─────────────────────────────────────────────────────
if [ -z "${HEALTH_MONITOR_SKIP_HTTP:-}" ]; then
declare -A ENDPOINTS=(
  ["api.grotap.com/health"]="https://api.grotap.com/health"
  ["apps.grotap.com"]="https://apps.grotap.com"
  ["agents.grotap.com"]="https://agents.grotap.com"
)

for NAME in "${!ENDPOINTS[@]}"; do
  URL="${ENDPOINTS[$NAME]}"
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$URL" 2>/dev/null || echo "000")
  FAIL_FILE="$STATE_DIR/fail_count_$(echo "$NAME" | tr '/.' '_')"

  if [ "$STATUS" = "200" ]; then
    # Reset fail counter
    echo "0" > "$FAIL_FILE"
  else
    # Increment fail counter
    PREV=$(cat "$FAIL_FILE" 2>/dev/null || echo "0")
    COUNT=$((PREV + 1))
    echo "$COUNT" > "$FAIL_FILE"
    OVERALL="DEGRADED"

    if [ "$COUNT" -ge 3 ]; then
      echo "[$TIMESTAMP] CRITICAL: $NAME failed $COUNT consecutive checks (HTTP $STATUS)" >> "$ALERT_LOG"
      OVERALL="DOWN"
    fi
  fi
done
fi

# ── Agent server SSH checks ──────────────────────────────────────────────────
# Roster of record is the live agent-0N rows in SERVERS.md.
# agent-05-claude (former 5.78.178.81) was deleted 2026-09-26. Hetzner can
# reassign that address, so it is not probed. The deployed copy does not
# have it; leaving it here alerts DEGRADED every 5 minutes.
AGENTS=(
  "agent-01-claude:5.161.74.39"
  "agent-02-claude:5.161.81.193"
  "agent-03-claude:178.156.222.220"
  "agent-04-claude:5.161.73.195"
  "agent-06-claude:5.161.53.103"
)

if [ -n "${HEALTH_MONITOR_AGENTS:-}" ]; then
  # shellcheck disable=SC2206
  AGENTS=(${HEALTH_MONITOR_AGENTS})
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_FOR="${HEALTH_MONITOR_SSH_KEY_FOR:-$SCRIPT_DIR/ssh-key-for.sh}"
SSH_BIN="${HEALTH_MONITOR_SSH:-ssh}"

for ENTRY in "${AGENTS[@]}"; do
  NAME="${ENTRY%%:*}"
  IP="${ENTRY##*:}"
  FAIL_FILE="$STATE_DIR/fail_count_$NAME"

  # Host-name targets stay on the resolver's $HOME/.ssh host-key path.
  # ssh-key-for.sh exits 1 when the key it would print is missing or
  # unreadable, including the shared-key fallback. Do not substitute
  # $HOME/.ssh/grotap_agents — that is what this check used to swallow.
  key_rc=0
  key_err="$(mktemp)"
  SSH_KEY_FOR_TARGET="$(bash "$KEY_FOR" "$NAME" 2>"$key_err")" || key_rc=$?
  if [ "$key_rc" -ne 0 ]; then
    key_msg="$(tr '\n' ' ' < "$key_err" 2>/dev/null || true)"
    rm -f "$key_err"
    line="[$TIMESTAMP] AGENT KEY-MISSING: $NAME ($IP) — ssh-key-for.sh exited ${key_rc}; host skipped; shared fleet key not used"
    if [ -n "$key_msg" ]; then
      line="$line; $key_msg"
    fi
    echo "$line" >> "$ALERT_LOG"
    echo "$line" >> "$LOG"
    echo "key-missing" > "$STATE_DIR/key_status_$NAME"
    OVERALL="DEGRADED"
    continue
  fi
  rm -f "$key_err"

  # -n: do not read stdin. A piped run of this script otherwise lets ssh
  # consume the pipe and the rest of the sweep never sees it.
  if "$SSH_BIN" -n -i "$SSH_KEY_FOR_TARGET" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "root@$IP" "echo ok" >/dev/null 2>&1; then
    echo "0" > "$FAIL_FILE"
  else
    PREV=$(cat "$FAIL_FILE" 2>/dev/null || echo "0")
    COUNT=$((PREV + 1))
    echo "$COUNT" > "$FAIL_FILE"

    if [ "$COUNT" -ge 3 ]; then
      echo "[$TIMESTAMP] AGENT UNREACHABLE: $NAME ($IP) — $COUNT consecutive failures" >> "$ALERT_LOG"
      OVERALL="DEGRADED"
    fi
  fi
done

# ── Trigger recovery if DOWN ─────────────────────────────────────────────────
if [ "$OVERALL" = "DOWN" ]; then
  echo "[$TIMESTAMP] Status: DOWN — triggering deploy-executor" >> "$LOG"
  bash /home/agent/scripts/deploy-execute.sh >> "$LOG" 2>&1 || true
else
  # Only log every 12th check (once per hour) when healthy to avoid log bloat
  TICK_FILE="$STATE_DIR/health_tick"
  TICK=$(cat "$TICK_FILE" 2>/dev/null || echo "0")
  TICK=$((TICK + 1))
  echo "$TICK" > "$TICK_FILE"
  if [ "$OVERALL" != "OK" ] || [ $((TICK % 12)) -eq 0 ]; then
    echo "[$TIMESTAMP] Status: $OVERALL" >> "$LOG"
  fi
fi
