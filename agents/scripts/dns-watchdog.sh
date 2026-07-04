#!/bin/bash
# dns-watchdog.sh — Runs on Agent-06 via daily cron.
# Validates DNS records haven't drifted. Catches wildcard re-creation.
# Usage: bash /home/agent/scripts/dns-watchdog.sh
set -uo pipefail

LOG="/home/agent/logs/dns-watchdog.log"
ALERT_LOG="/home/agent/logs/deploy-alerts.log"
mkdir -p /home/agent/logs

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "" >> "$LOG"
echo "=== DNS WATCHDOG — $TIMESTAMP ===" >> "$LOG"

VERDICT="PASS"
FAILURES=""

# ── Check that domains resolve ────────────────────────────────────────────────
check_dns() {
  local DOMAIN="$1"
  local MUST_CONTAIN="$2"
  local RESULT

  RESULT=$(dig +short "$DOMAIN" 2>/dev/null | head -n 1)

  if [ -z "$RESULT" ]; then
    echo "  $DOMAIN → NXDOMAIN / no record" >> "$LOG"
    VERDICT="FAIL"
    FAILURES="$FAILURES\n- $DOMAIN: no DNS record found (NXDOMAIN)"
    return
  fi

  echo "  $DOMAIN → $RESULT" >> "$LOG"

  if [ -n "$MUST_CONTAIN" ] && ! echo "$RESULT" | grep -qi "$MUST_CONTAIN"; then
    VERDICT="FAIL"
    FAILURES="$FAILURES\n- $DOMAIN resolves to $RESULT (expected to contain '$MUST_CONTAIN')"
  fi
}

echo "[1/3] Checking domain resolution..." >> "$LOG"
check_dns "apps.grotap.com" "vercel"
check_dns "agents.grotap.com" "vercel"
check_dns "agents.grotap.ai" "vercel"
# api.grotap.com points to Railway — just check it resolves
check_dns "api.grotap.com" ""

# ── CRITICAL: Check that wildcard does NOT exist ─────────────────────────────
echo "[2/3] Checking wildcard *.grotap.com..." >> "$LOG"
WILDCARD=$(dig +short "randomtestsubdomain42.grotap.com" 2>/dev/null | head -n 1)

if [ -n "$WILDCARD" ]; then
  echo "  CRITICAL: *.grotap.com wildcard is ACTIVE → $WILDCARD" >> "$LOG"
  echo "  This will route api.grotap.com to Vercel and break the backend!" >> "$LOG"
  VERDICT="CRITICAL"
  FAILURES="$FAILURES\n- CRITICAL: *.grotap.com wildcard is active ($WILDCARD) — will break API routing"
  echo "[$TIMESTAMP] CRITICAL DNS: *.grotap.com wildcard detected → $WILDCARD" >> "$ALERT_LOG"
else
  echo "  *.grotap.com wildcard: ABSENT (correct)" >> "$LOG"
fi

# ── SSL certificate expiry check ─────────────────────────────────────────────
echo "[3/3] Checking SSL certificate expiry..." >> "$LOG"
check_ssl() {
  local DOMAIN="$1"
  local EXPIRY
  EXPIRY=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

  if [ -z "$EXPIRY" ]; then
    echo "  $DOMAIN SSL: could not check" >> "$LOG"
    return
  fi

  local EXPIRY_EPOCH
  EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo "0")
  local NOW_EPOCH
  NOW_EPOCH=$(date +%s)
  local DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

  echo "  $DOMAIN SSL expires: $EXPIRY ($DAYS_LEFT days)" >> "$LOG"

  if [ "$DAYS_LEFT" -lt 7 ]; then
    VERDICT="FAIL"
    FAILURES="$FAILURES\n- $DOMAIN SSL expires in $DAYS_LEFT days ($EXPIRY)"
    echo "[$TIMESTAMP] SSL EXPIRY WARNING: $DOMAIN expires in $DAYS_LEFT days" >> "$ALERT_LOG"
  fi
}

check_ssl "apps.grotap.com"
check_ssl "api.grotap.com"
check_ssl "agents.grotap.com"

# ── VERDICT ───────────────────────────────────────────────────────────────────
echo "" >> "$LOG"
echo "VERDICT: $VERDICT" >> "$LOG"
if [ "$VERDICT" != "PASS" ]; then
  echo "FAILURES:" >> "$LOG"
  echo -e "$FAILURES" >> "$LOG"
fi
echo "=== END DNS WATCHDOG ===" >> "$LOG"
