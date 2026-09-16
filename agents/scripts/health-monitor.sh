#!/bin/bash
# health-monitor.sh — Runs on Agent-06 via cron every 5 minutes.
# Polls all production endpoints + agent servers.
# On 3 consecutive failures, triggers deploy-executor.
# Usage: bash /home/agent/scripts/health-monitor.sh
set -uo pipefail

LOG="/home/agent/logs/health-monitor.log"
STATE_DIR="/home/agent/state"
ALERT_LOG="/home/agent/logs/deploy-alerts.log"
mkdir -p /home/agent/logs "$STATE_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
OVERALL="OK"

# ── HTTP endpoint checks ─────────────────────────────────────────────────────
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

# ── Agent server SSH checks ──────────────────────────────────────────────────
# Roster of record is SERVERS.md — keep this list equal to the agent-0N rows there.
# It was wrong in both directions until 2026-09-15: it probed agent-01, deleted
# 2026-06-29 with its IP recycled to supportagents (so the check passed while
# testing a different machine entirely), and it omitted agent-06 — the box whose
# crons must always run, and the box this script itself runs on.
AGENTS=(
  "agent-02:5.161.74.39"
  "agent-03:5.161.81.193"
  "agent-04:178.156.222.220"
  "agent-05:5.161.73.195"
  "agent-06:5.78.178.81"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for ENTRY in "${AGENTS[@]}"; do
  NAME="${ENTRY%%:*}"
  IP="${ENTRY##*:}"
  FAIL_FILE="$STATE_DIR/fail_count_$NAME"

  # Per-host key when this OS user (root, via root's crontab) has one on THIS
  # box (agent-06); falls back to the shared fleet key otherwise. $HOME here
  # is root's — the resolver reads it internally, so root and agent (via
  # sudo -u agent) get the right key from the same call. See ssh-key-for.sh.
  SSH_KEY_FOR_TARGET="$(bash "$SCRIPT_DIR/ssh-key-for.sh" "$NAME" 2>/dev/null || echo "$HOME/.ssh/grotap_agents")"

  if ssh -i "$SSH_KEY_FOR_TARGET" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "root@$IP" "echo ok" >/dev/null 2>&1; then
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
