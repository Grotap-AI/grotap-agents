#!/bin/bash
# sync-all-agents.sh — Pull latest bootstrap on ALL agent servers AND ensure each
# agent's Doppler CLI is configured with the fleet service token.
#
# WHY the Doppler step: the fleet's git remote is HTTPS with a credential helper
# that shells out to `doppler secrets get GITHUB_TOKEN`. If an agent's Doppler is
# unconfigured (fresh reprovision, wiped ~/.doppler, or a rotated token), EVERY
# dispatched task fails at `git push` ("Authentication failed") — a silent
# fleet-wide outage. Re-running this script restores it. See the platform memory
# note project_fleet_dispatch_auth_fix.
#
# Token source (first non-empty wins):
#   1. $FLEET_DOPPLER_TOKEN env (e.g. when run via `doppler run`)
#   2. `doppler secrets get FLEET_DOPPLER_TOKEN` from grotap/prd (canonical store;
#      rotate by updating that one secret, then re-running this script)
# The token is NEVER committed. To rotate: mint a new grotap/prd service token,
# `doppler secrets set FLEET_DOPPLER_TOKEN`, re-run this script.
#
# Run from a machine with per-host fleet SSH keys + Doppler auth:
#   bash agents/scripts/sync-all-agents.sh
set -uo pipefail

# Key resolution goes through ssh-key-for.sh (phase 2b, 2026-09-16) so this
# script stops hardcoding the shared fleet key grotap_agents. Resolved per
# target inside the loop, not once up front -- each host has its own key.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key_for() { bash "$SCRIPT_DIR/ssh-key-for.sh" "$1" 2>/dev/null || printf %s "$HOME/.ssh/grotap_agents"; }

# Active fleet (consolidated 2026-04-29: agent-01/08/09/10/11 retired).
AGENTS=(
  "agent-02:5.161.74.39"
  "agent-03:5.161.81.193"
  "agent-04:178.156.222.220"
  "agent-05:5.161.73.195"
  "agent-06:5.78.178.81"
)
# agent-07 (89.167.66.105) REMOVED 2026-09-16. That address is no longer ours --
# Hetzner released and recycled it to another customer (absent from every Hetzner
# Cloud project and from Robot; its host key no longer matches known_hosts). This
# loop SSHed to it as root with the shared fleet key, which is the single worst
# form of the bare-IP problem: fleet credentials offered to a stranger's machine.
# Do not re-add a host here without confirming ownership via the Hetzner API.

# Resolve the fleet Doppler token once (env override, else from Doppler).
FLEET_TOKEN="${FLEET_DOPPLER_TOKEN:-}"
if [ -z "$FLEET_TOKEN" ] && command -v doppler >/dev/null 2>&1; then
  FLEET_TOKEN="$(doppler secrets get FLEET_DOPPLER_TOKEN --project grotap --config prd --plain 2>/dev/null || true)"
fi
if [ -z "$FLEET_TOKEN" ]; then
  echo "WARNING: FLEET_DOPPLER_TOKEN not available — git-push auth bootstrap will be SKIPPED."
  echo "         Set it via env or 'doppler secrets set FLEET_DOPPLER_TOKEN' (grotap/prd)."
fi

echo "=== Syncing all agent servers (git bootstrap + Doppler push-auth) ==="
echo ""

for ENTRY in "${AGENTS[@]}"; do
  NAME="${ENTRY%%:*}"
  IP="${ENTRY##*:}"
  SSH_KEY="$(key_for "$NAME")"
  echo -n "$NAME ($IP): "

  # 1) Pull the latest grotap-agents bootstrap.
  RESULT=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$IP" \
    "cd /home/agent/grotap-agents && git pull origin master --quiet 2>&1 && git rev-parse --short HEAD" 2>&1)
  if [ $? -eq 0 ]; then
    echo -n "✓ synced ($RESULT)"
  else
    echo "✗ git sync FAILED — $RESULT"
    continue
  fi

  # 2) Ensure the `agent` user's Doppler CLI has the fleet token (push-auth).
  if [ -n "$FLEET_TOKEN" ]; then
    DOP=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$IP" \
      "su - agent -c 'doppler configure set token \"$FLEET_TOKEN\" --scope / --silent >/dev/null 2>&1; doppler secrets get GITHUB_TOKEN --project grotap --config prd --plain 2>&1 | head -c 10'" 2>&1)
    if printf '%s' "$DOP" | grep -q '^github_pat'; then
      echo "  ·  ✓ doppler push-auth OK"
    else
      echo "  ·  ✗ doppler push-auth FAILED ($DOP)"
    fi
  else
    echo "  ·  (doppler bootstrap skipped — no token)"
  fi
done

echo ""
echo "=== Sync complete ==="
