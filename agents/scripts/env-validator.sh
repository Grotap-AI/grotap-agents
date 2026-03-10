#!/bin/bash
# env-validator.sh — Runs on Agent-06 via daily cron or before deploy.
# Checks Hetzner tokens are valid. Checks critical endpoints respond.
# Usage: bash /home/agent/scripts/env-validator.sh
set -uo pipefail

LOG="/home/agent/logs/env-validator.log"
ALERT_LOG="/home/agent/logs/deploy-alerts.log"
mkdir -p /home/agent/logs

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "" >> "$LOG"
echo "=== ENV VALIDATION — $TIMESTAMP ===" >> "$LOG"

VERDICT="PASS"
FAILURES=""

# ── 1. Validate Hetzner Token 1 ──────────────────────────────────────────────
echo "[1/3] Checking HETZNER_API_TOKEN..." >> "$LOG"
if [ -f /home/agent/.env.deploy ]; then
  source /home/agent/.env.deploy
fi

if [ -n "${HETZNER_API_TOKEN:-}" ]; then
  H1_RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $HETZNER_API_TOKEN" "https://api.hetzner.cloud/v1/servers" 2>/dev/null || echo "000")
  if [ "$H1_RESP" = "200" ]; then
    echo "  HETZNER_API_TOKEN: VALID" >> "$LOG"
  else
    echo "  HETZNER_API_TOKEN: INVALID (HTTP $H1_RESP)" >> "$LOG"
    VERDICT="FAIL"
    FAILURES="$FAILURES\n- HETZNER_API_TOKEN returned HTTP $H1_RESP (expected 200)"
  fi
else
  echo "  HETZNER_API_TOKEN: NOT SET" >> "$LOG"
  VERDICT="FAIL"
  FAILURES="$FAILURES\n- HETZNER_API_TOKEN not set in .env.deploy"
fi

# ── 2. Validate Hetzner Token 2 ──────────────────────────────────────────────
echo "[2/3] Checking HETZNER_API_TOKEN_2..." >> "$LOG"
if [ -n "${HETZNER_API_TOKEN_2:-}" ]; then
  H2_RESP=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $HETZNER_API_TOKEN_2" "https://api.hetzner.cloud/v1/servers" 2>/dev/null || echo "000")
  if [ "$H2_RESP" = "200" ]; then
    echo "  HETZNER_API_TOKEN_2: VALID" >> "$LOG"
  else
    echo "  HETZNER_API_TOKEN_2: INVALID (HTTP $H2_RESP)" >> "$LOG"
    VERDICT="FAIL"
    FAILURES="$FAILURES\n- HETZNER_API_TOKEN_2 returned HTTP $H2_RESP (expected 200)"
  fi
else
  echo "  HETZNER_API_TOKEN_2: NOT SET" >> "$LOG"
  VERDICT="FAIL"
  FAILURES="$FAILURES\n- HETZNER_API_TOKEN_2 not set in .env.deploy"
fi

# ── 3. Validate critical service endpoints respond ───────────────────────────
echo "[3/3] Checking critical endpoints..." >> "$LOG"
ENDPOINTS=("https://api.grotap.com/health" "https://apps.grotap.com")

for URL in "${ENDPOINTS[@]}"; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$URL" 2>/dev/null || echo "000")
  if [ "$STATUS" = "200" ]; then
    echo "  $URL: OK ($STATUS)" >> "$LOG"
  else
    echo "  $URL: FAIL ($STATUS)" >> "$LOG"
    VERDICT="FAIL"
    FAILURES="$FAILURES\n- $URL returned $STATUS"
  fi
done

# ── VERDICT ───────────────────────────────────────────────────────────────────
echo "" >> "$LOG"
echo "VERDICT: $VERDICT" >> "$LOG"
if [ "$VERDICT" != "PASS" ]; then
  echo "FAILURES:" >> "$LOG"
  echo -e "$FAILURES" >> "$LOG"
  echo "[$TIMESTAMP] ENV VALIDATION FAILED" >> "$ALERT_LOG"
  echo -e "$FAILURES" >> "$ALERT_LOG"
  echo "---" >> "$ALERT_LOG"
fi
echo "=== END ENV VALIDATION ===" >> "$LOG"

[ "$VERDICT" = "PASS" ] && exit 0 || exit 1
