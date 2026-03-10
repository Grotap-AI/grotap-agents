#!/bin/bash
# post-task-reload.sh — Runs on every agent after task completion.
# Pulls latest bootstrap from GitHub, validates MD structure, signals ready.
# dispatch.sh should call this after "=== TASK DONE ===" is detected.
# Usage: bash /home/agent/grotap-agents/agents/scripts/post-task-reload.sh
set -uo pipefail

AGENT_DIR="/home/agent/grotap-agents"
LOG="/home/agent/logs/reload.log"
mkdir -p /home/agent/logs

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOSTNAME=$(hostname)

echo "[$TIMESTAMP] $HOSTNAME — Post-task reload starting" >> "$LOG"

# ── 1. Pull latest from GitHub ────────────────────────────────────────────────
cd "$AGENT_DIR"
git fetch origin master --quiet 2>> "$LOG"
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/master)

if [ "$LOCAL" != "$REMOTE" ]; then
  echo "  Pulling updates ($LOCAL → $REMOTE)..." >> "$LOG"
  git pull origin master --quiet 2>> "$LOG"
else
  echo "  Already up to date ($LOCAL)" >> "$LOG"
fi

NEW_COMMIT=$(git rev-parse HEAD)

# ── 2. Validate MD structure ─────────────────────────────────────────────────
REQUIRED=(
  "agents/GLOBAL.md"
  "agents/registry.md"
  "agents/OWNERS.md"
)

VALID=true
for f in "${REQUIRED[@]}"; do
  if [ ! -f "$AGENT_DIR/$f" ]; then
    echo "  ERROR: Missing $f" >> "$LOG"
    VALID=false
  fi
done

# Check own server file exists
OWN_SERVER_FILE="agents/servers/$HOSTNAME.md"
if [ -f "$AGENT_DIR/$OWN_SERVER_FILE" ]; then
  echo "  Server config: $OWN_SERVER_FILE ✓" >> "$LOG"
else
  echo "  WARNING: No server config at $OWN_SERVER_FILE" >> "$LOG"
fi

# ── 3. Write ready signal ────────────────────────────────────────────────────
cat > /home/agent/.agent-status.json << EOF
{
  "hostname": "$HOSTNAME",
  "status": "ready",
  "commit": "$NEW_COMMIT",
  "reloaded_at": "$TIMESTAMP",
  "md_valid": $VALID,
  "task": null,
  "task_started": null
}
EOF

echo "[$TIMESTAMP] $HOSTNAME — Ready (commit: $NEW_COMMIT, valid: $VALID)" >> "$LOG"
