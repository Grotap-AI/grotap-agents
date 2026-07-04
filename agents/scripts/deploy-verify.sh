#!/bin/bash
# deploy-verify.sh — Runs on Agent-06 after every merge to master.
# Checks Railway + Vercel + health endpoints. Triggers deploy-executor on failure.
# Usage: bash /home/agent/scripts/deploy-verify.sh
set -euo pipefail

LOG="/home/agent/logs/deploy-verify.log"
ALERT_LOG="/home/agent/logs/deploy-alerts.log"
mkdir -p /home/agent/logs

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "" >> "$LOG"
echo "=== DEPLOY VERIFICATION — $TIMESTAMP ===" >> "$LOG"

VERDICT="PASS"
FAILURES=""

# ── 1. Health Check: API backend ──────────────────────────────────────────────
echo "[1/5] Checking api.grotap.com/health..." >> "$LOG"
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://api.grotap.com/health" 2>/dev/null || echo "000")
API_TIME=$(curl -s -o /dev/null -w "%{time_total}" --max-time 10 "https://api.grotap.com/health" 2>/dev/null || echo "timeout")
echo "  api.grotap.com/health: HTTP $API_STATUS (${API_TIME}s)" >> "$LOG"

if [ "$API_STATUS" != "200" ]; then
  VERDICT="FAIL"
  FAILURES="$FAILURES\n- api.grotap.com/health returned $API_STATUS (expected 200)"
fi

# ── 2. Health Check: Frontend ─────────────────────────────────────────────────
echo "[2/5] Checking apps.grotap.com..." >> "$LOG"
FE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://apps.grotap.com" 2>/dev/null || echo "000")
echo "  apps.grotap.com: HTTP $FE_STATUS" >> "$LOG"

if [ "$FE_STATUS" != "200" ]; then
  VERDICT="FAIL"
  FAILURES="$FAILURES\n- apps.grotap.com returned $FE_STATUS (expected 200)"
fi

# ── 3. Health Check: Agents brand ─────────────────────────────────────────────
echo "[3/5] Checking agents.grotap.com..." >> "$LOG"
AG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://agents.grotap.com" 2>/dev/null || echo "000")
echo "  agents.grotap.com: HTTP $AG_STATUS" >> "$LOG"

if [ "$AG_STATUS" != "200" ]; then
  VERDICT="FAIL"
  FAILURES="$FAILURES\n- agents.grotap.com returned $AG_STATUS (expected 200)"
fi

# ── 4. Backend deep check — validate response body ───────────────────────────
echo "[4/5] Deep checking API response body..." >> "$LOG"
API_BODY=$(curl -s --max-time 10 "https://api.grotap.com/health" 2>/dev/null || echo "TIMEOUT")
BODY_LEN=${#API_BODY}
echo "  Response body length: $BODY_LEN chars" >> "$LOG"

if [ "$BODY_LEN" -lt 5 ]; then
  VERDICT="FAIL"
  FAILURES="$FAILURES\n- api.grotap.com/health response body too short ($BODY_LEN chars)"
fi

# Check for error keywords in body
if echo "$API_BODY" | grep -qi "error\|exception\|traceback"; then
  VERDICT="FAIL"
  FAILURES="$FAILURES\n- api.grotap.com/health response contains error keywords"
fi

# ── 5. CORS preflight check ──────────────────────────────────────────────────
echo "[5/5] Checking CORS preflight..." >> "$LOG"
CORS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 -X OPTIONS "https://api.grotap.com/apps" -H "Origin: https://apps.grotap.com" -H "Access-Control-Request-Method: GET" 2>/dev/null || echo "000")
echo "  CORS OPTIONS /apps: HTTP $CORS_STATUS" >> "$LOG"

if [ "$CORS_STATUS" = "000" ] || [ "$CORS_STATUS" = "500" ]; then
  VERDICT="FAIL"
  FAILURES="$FAILURES\n- CORS preflight returned $CORS_STATUS (auth middleware not bypassing OPTIONS)"
fi

# ── VERDICT ───────────────────────────────────────────────────────────────────
echo "" >> "$LOG"
echo "VERDICT: $VERDICT" >> "$LOG"

if [ "$VERDICT" = "FAIL" ]; then
  echo "FAILURES:" >> "$LOG"
  echo -e "$FAILURES" >> "$LOG"
  echo "" >> "$LOG"

  # Write to alert log
  echo "[$TIMESTAMP] DEPLOY VERIFICATION FAILED" >> "$ALERT_LOG"
  echo -e "$FAILURES" >> "$ALERT_LOG"
  echo "---" >> "$ALERT_LOG"

  # Trigger deploy-executor
  echo "Triggering deploy-executor..." >> "$LOG"
  bash /home/agent/scripts/deploy-execute.sh >> "$LOG" 2>&1 || true
fi

echo "=== END DEPLOY VERIFICATION ===" >> "$LOG"

# Exit with appropriate code
if [ "$VERDICT" = "FAIL" ]; then
  exit 1
fi
exit 0
