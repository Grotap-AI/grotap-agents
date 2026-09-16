#!/bin/bash
# setup-agent06.sh — Run from local machine to deploy all scripts + cron to Agent-06.
# Usage: bash agents/scripts/setup-agent06.sh
set -euo pipefail

AGENT06="5.78.178.81"
SSH_KEY="$HOME/.ssh/grotap_agents"
SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$AGENT06"
SCP="scp -i $SSH_KEY -o StrictHostKeyChecking=no"

echo "=== Setting up Agent-06 ($AGENT06) ==="

# ── 1. Create directory structure ─────────────────────────────────────────────
echo "[1/5] Creating directories..."
$SSH "mkdir -p /home/agent/scripts /home/agent/logs /home/agent/state /home/agent/.ssh"

# ── 2. Copy scripts ──────────────────────────────────────────────────────────
echo "[2/5] Copying scripts..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
$SCP "$SCRIPT_DIR/deploy-verify.sh" root@$AGENT06:/home/agent/scripts/
$SCP "$SCRIPT_DIR/deploy-execute.sh" root@$AGENT06:/home/agent/scripts/
$SCP "$SCRIPT_DIR/health-monitor.sh" root@$AGENT06:/home/agent/scripts/
$SCP "$SCRIPT_DIR/dns-watchdog.sh" root@$AGENT06:/home/agent/scripts/
$SCP "$SCRIPT_DIR/env-validator.sh" root@$AGENT06:/home/agent/scripts/
$SCP "$SCRIPT_DIR/ssh-key-for.sh" root@$AGENT06:/home/agent/scripts/

# ── 3. Per-host SSH keys for agent-to-agent connectivity (phase 2b) ──────────
# This step used to `scp` the SHARED fleet private key (grotap_agents) onto
# Agent-06 so its cron scripts (health-monitor.sh, dns-watchdog.sh, ...) could
# reach the other agent-0X boxes. That put a copy of the one key that unlocks
# the WHOLE fleet onto every monitoring box — exactly what retiring
# grotap_agents is meant to stop. Agent-06's scripts now resolve keys through
# ssh-key-for.sh (copied above), which looks for a per-target key named
# grotap_from06_<target> before ever falling back to the shared key. So
# instead of shipping the fleet-wide private key over the wire, this step
# generates any MISSING per-target keypair directly ON Agent-06 for each
# source user — the private half is created on the box that uses it and
# never travels over SCP.
echo "[3/5] Provisioning per-target keys for agent-to-agent checks..."
FLEET_TARGETS="agent-02 agent-03 agent-04 agent-05"
for TARGET in $FLEET_TARGETS; do
  ROOT_KEY="/root/.ssh/grotap_from06_${TARGET}"
  $SSH "test -f $ROOT_KEY || ssh-keygen -t ed25519 -N '' -C agent06-root-to-${TARGET} -f $ROOT_KEY"
  $SSH "chmod 600 $ROOT_KEY && chmod 644 ${ROOT_KEY}.pub"

  AGENT_KEY="/home/agent/.ssh/grotap_from06_${TARGET}"
  $SSH "test -f $AGENT_KEY || ssh-keygen -t ed25519 -N '' -C agent06-agent-to-${TARGET} -f $AGENT_KEY"
  $SSH "chown agent:agent $AGENT_KEY ${AGENT_KEY}.pub && chmod 600 $AGENT_KEY && chmod 644 ${AGENT_KEY}.pub"
done
echo ""
echo "  NOTE: any newly generated key above still needs its .pub APPENDED"
echo "  (never overwritten) to the matching target's authorized_keys before"
echo "  it will actually authenticate. Print a key with, e.g.:"
echo "    ssh root@$AGENT06 'cat /root/.ssh/grotap_from06_agent-02.pub'"

# ── 4. Make scripts executable ────────────────────────────────────────────────
echo "[4/5] Setting permissions..."
$SSH "chmod +x /home/agent/scripts/*.sh"

# ── 5. Install cron jobs ─────────────────────────────────────────────────────
echo "[5/5] Installing cron jobs..."
$SSH 'cat > /tmp/agent06-cron << "CRON"
# Agent-06 Deployment Ops — automated monitoring
# Health monitor: every 5 minutes
*/5 * * * * /bin/bash /home/agent/scripts/health-monitor.sh
# DNS watchdog: daily at 06:00 UTC
0 6 * * * /bin/bash /home/agent/scripts/dns-watchdog.sh
# Env validator: daily at 05:00 UTC
0 5 * * * /bin/bash /home/agent/scripts/env-validator.sh
# Deploy verification: every 15 minutes
*/15 * * * * /bin/bash /home/agent/scripts/deploy-verify.sh
CRON
crontab /tmp/agent06-cron && rm /tmp/agent06-cron'

echo ""
echo "=== Agent-06 setup complete ==="
echo ""
echo "Cron installed:"
$SSH "crontab -l"
echo ""
echo "IMPORTANT: You still need to create /home/agent/.env.deploy with:"
echo "  VERCEL_TOKEN=<token>"
echo "  HETZNER_API_TOKEN=<token>"
echo "  HETZNER_API_TOKEN_2=<token>"
echo ""
echo "Run: ssh -i ~/.ssh/grotap_agents root@$AGENT06 'cat > /home/agent/.env.deploy << EOF"
echo "VERCEL_TOKEN=\$(doppler secrets get VERCEL_TOKEN --project grotap --config prd --plain)"
echo "HETZNER_API_TOKEN=\$(doppler secrets get HETZNER_API_TOKEN --project grotap --config dev --plain)"
echo "HETZNER_API_TOKEN_2=\$(doppler secrets get HETZNER_API_TOKEN_2 --project grotap --config dev --plain)"
echo "EOF'"
