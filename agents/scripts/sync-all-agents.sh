#!/bin/bash
# sync-all-agents.sh — Pull latest bootstrap on ALL agent servers.
# Run from local machine after pushing changes to GitHub.
# Usage: bash agents/scripts/sync-all-agents.sh
set -uo pipefail

SSH_KEY="$HOME/.ssh/grotap_agents"

AGENTS=(
  "agent-01:5.161.189.143"
  "agent-02:5.161.74.39"
  "agent-03:5.161.81.193"
  "agent-04:178.156.222.220"
  "agent-05:5.161.73.195"
  "agent-06:5.78.178.81"
)

echo "=== Syncing all agent servers from GitHub ==="
echo ""

for ENTRY in "${AGENTS[@]}"; do
  NAME="${ENTRY%%:*}"
  IP="${ENTRY##*:}"
  echo -n "$NAME ($IP): "
  RESULT=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$IP" \
    "cd /home/agent/grotap-agents && git pull origin master --quiet 2>&1 && git rev-parse --short HEAD" 2>&1)
  if [ $? -eq 0 ]; then
    echo "✓ synced ($RESULT)"
  else
    echo "✗ FAILED — $RESULT"
  fi
done

echo ""
echo "=== Sync complete ==="
