#!/bin/bash
# sync-all-agents.sh — Pull the latest grotap-agents bootstrap on ALL agent servers.
#
# Doppler is NOT touched here (2026-10-03). Every box now reads its own
# read-only service token from /etc/grotap/doppler/doppler.yaml (installed by
# grotap-platform agents/scripts/install-root-doppler.sh). This script used to
# copy the shared FLEET_DOPPLER_TOKEN from grotap/prd into the agent user's
# Doppler config. That shared token is being revoked, and pushing it after that
# would plant a dead token and break the box's crons. Do not add a Doppler
# token push back; agents/scripts/health-monitor.test.sh fails if one returns.
#
# Run from a machine with the grotap_agents SSH key:
#   bash agents/scripts/sync-all-agents.sh
set -uo pipefail

SSH_KEY="$HOME/.ssh/grotap_agents"

# Active fleet (consolidated 2026-04-29: agent-01/08/09/10/11 retired).
AGENTS=(
  # agent-01..04-claude were deleted (G6b, 2026-09-26..10-03). 5.161.74.39 is
  # openreplay-02 now and the other three addresses are released; this script
  # dials every row as root, so it must never dial them. Do not re-add them.
  # agent-07 went with the cancelled Helsinki account; on 2026-10-03 its old
  # address was on no server, primary IP or floating IP in any of the four
  # Hetzner projects. Do not re-add it.
  "agent-06-claude:5.161.53.103"
)

echo "=== Syncing all agent servers (git bootstrap) ==="
echo ""

for ENTRY in "${AGENTS[@]}"; do
  NAME="${ENTRY%%:*}"
  IP="${ENTRY##*:}"
  echo -n "$NAME ($IP): "

  # 1) Pull the latest grotap-agents bootstrap.
  RESULT=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$IP" \
    "cd /home/agent/grotap-agents && git pull origin master --quiet 2>&1 && git rev-parse --short HEAD" 2>&1)
  if [ $? -eq 0 ]; then
    echo "✓ synced ($RESULT)"
  else
    echo "✗ git sync FAILED — $RESULT"
    continue
  fi
done

echo ""
echo "=== Sync complete ==="
