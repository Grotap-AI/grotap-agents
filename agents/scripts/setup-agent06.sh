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

# ── 3. Copy SSH key for agent-to-agent connectivity ──────────────────────────
echo "[3/5] Copying SSH key for agent-to-agent checks..."
$SCP "$HOME/.ssh/grotap_agents" root@$AGENT06:/home/agent/.ssh/grotap_agents
$SSH "chmod 600 /home/agent/.ssh/grotap_agents"

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
