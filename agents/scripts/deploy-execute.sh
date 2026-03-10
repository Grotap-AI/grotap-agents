#!/bin/bash
# deploy-execute.sh — Runs on Agent-06. Executes Vercel frontend deploy
# and checks Railway backend status. Called by deploy-verify.sh on failure
# or manually when needed.
# Usage: bash /home/agent/scripts/deploy-execute.sh
set -euo pipefail

LOG="/home/agent/logs/deploy-execute.log"
mkdir -p /home/agent/logs

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "" >> "$LOG"
echo "=== DEPLOY EXECUTION — $TIMESTAMP ===" >> "$LOG"

# ── 1. Check if Vercel frontend is stale ─────────────────────────────────────
echo "[1/3] Checking if frontend needs deploy..." >> "$LOG"

FE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://apps.grotap.com" 2>/dev/null || echo "000")

if [ "$FE_STATUS" != "200" ]; then
  echo "  Frontend is DOWN ($FE_STATUS). Deploying via Vercel CLI..." >> "$LOG"

  if [ -f /home/agent/.env.deploy ]; then
    source /home/agent/.env.deploy
  fi

  if [ -z "${VERCEL_TOKEN:-}" ]; then
    echo "  ERROR: VERCEL_TOKEN not set. Cannot deploy frontend." >> "$LOG"
    echo "  Set it in /home/agent/.env.deploy" >> "$LOG"
  else
    cd /home/agent/grotap-platform/frontend 2>/dev/null || {
      echo "  ERROR: grotap-platform not cloned. Cloning..." >> "$LOG"
      cd /home/agent
      git clone https://github.com/Grotap-AI/grotap-platform.git grotap-platform 2>> "$LOG"
      cd /home/agent/grotap-platform/frontend
    }
    git pull origin master --quiet 2>> "$LOG" || true
    npx vercel --token "$VERCEL_TOKEN" --prod --yes >> "$LOG" 2>&1 && {
      echo "  Vercel deploy: SUCCESS" >> "$LOG"
    } || {
      echo "  Vercel deploy: FAILED" >> "$LOG"
    }
  fi
else
  echo "  Frontend is UP ($FE_STATUS). No Vercel deploy needed." >> "$LOG"
fi

# ── 2. Check Railway backend ─────────────────────────────────────────────────
echo "[2/3] Checking Railway backend status..." >> "$LOG"

API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://api.grotap.com/health" 2>/dev/null || echo "000")

if [ "$API_STATUS" != "200" ]; then
  echo "  Backend is DOWN ($API_STATUS)." >> "$LOG"
  echo "  Railway auto-deploy may have failed." >> "$LOG"
  echo "  Manual intervention required — redeploy via Railway CLI or API." >> "$LOG"
  echo "  Command: cd platform/backend && doppler run --project grotap --config dev -- railway up --detach --service grotap-backend" >> "$LOG"

  # Log alert
  echo "[$TIMESTAMP] BACKEND DOWN — manual Railway redeploy needed" >> /home/agent/logs/deploy-alerts.log
else
  echo "  Backend is UP ($API_STATUS). No Railway redeploy needed." >> "$LOG"
fi

# ── 3. Post-execution verification ───────────────────────────────────────────
echo "[3/3] Waiting 30s then re-verifying..." >> "$LOG"
sleep 30

RECHECK_API=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://api.grotap.com/health" 2>/dev/null || echo "000")
RECHECK_FE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://apps.grotap.com" 2>/dev/null || echo "000")

echo "  Re-check: api=$RECHECK_API, frontend=$RECHECK_FE" >> "$LOG"

if [ "$RECHECK_API" = "200" ] && [ "$RECHECK_FE" = "200" ]; then
  echo "  All services UP after deploy execution." >> "$LOG"
else
  echo "  STILL DOWN after deploy execution. Human intervention required." >> "$LOG"
  echo "[$TIMESTAMP] DEPLOY EXECUTION FAILED — services still down after retry" >> /home/agent/logs/deploy-alerts.log
fi

echo "=== END DEPLOY EXECUTION ===" >> "$LOG"
