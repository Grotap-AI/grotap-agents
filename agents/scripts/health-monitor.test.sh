#!/bin/bash
# health-monitor.sh must not swallow a non-zero ssh-key-for.sh by switching
# to the shared fleet key. The resolver stub exits 1; ssh must not run.
# No network, no fleet host.
# Run: bash agents/scripts/health-monitor.test.sh
set -uo pipefail

PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR="$SCRIPT_DIR/health-monitor.sh"

check() {
  local desc="$1" ok="$2"
  if [ "$ok" = "true" ]; then
    PASS=$((PASS + 1))
    printf '  ok   %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL %s\n' "$desc"
  fi
}

cat > "$TMP/ssh-key-for-fail.sh" <<'EOF'
#!/bin/bash
echo "ssh-key-for: no key file for user claude in /home/agent/.ssh" >&2
exit 1
EOF
cat > "$TMP/ssh-key-for-ok.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$STUB_KEY_PATH"
exit 0
EOF
cat > "$TMP/ssh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SSH_INVOCATIONS"
exit 0
EOF
chmod +x "$TMP/ssh-key-for-fail.sh" "$TMP/ssh-key-for-ok.sh" "$TMP/ssh"

run_monitor() {
  local key_for="$1"
  rm -rf "$TMP/state" "$TMP/logs"
  mkdir -p "$TMP/state" "$TMP/logs"
  : > "$TMP/ssh-invocations"
  HEALTH_MONITOR_LOG="$TMP/logs/health-monitor.log" \
  HEALTH_MONITOR_STATE_DIR="$TMP/state" \
  HEALTH_MONITOR_ALERT_LOG="$TMP/logs/alerts.log" \
  HEALTH_MONITOR_SKIP_HTTP=1 \
  HEALTH_MONITOR_AGENTS="agent-04-claude:203.0.113.10" \
  HEALTH_MONITOR_SSH_KEY_FOR="$key_for" \
  HEALTH_MONITOR_SSH="$TMP/ssh" \
  SSH_INVOCATIONS="$TMP/ssh-invocations" \
  STUB_KEY_PATH="$TMP/seat-key" \
    bash "$MONITOR"
}

echo "== non-zero ssh-key-for.sh is not replaced with the shared key =="
run_monitor "$TMP/ssh-key-for-fail.sh"
alerts="$(cat "$TMP/logs/alerts.log")"
health="$(cat "$TMP/logs/health-monitor.log")"
invocations="$(cat "$TMP/ssh-invocations")"
status="$(cat "$TMP/state/key_status_agent-04-claude" 2>/dev/null || true)"
if [ ! -s "$TMP/ssh-invocations" ]; then
  check "ssh is not invoked" true
else
  check "ssh is not invoked (saw: $invocations)" false
fi
case "$alerts" in
  *"AGENT KEY-MISSING: agent-04-claude (203.0.113.10)"*"exited 1"*"shared fleet key not used"*)
    check "alert names the host and refuses the shared key" true
    ;;
  *)
    check "alert names the host and refuses the shared key (saw: $alerts)" false
    ;;
esac
case "$alerts$health$invocations" in
  *grotap_agents*)
    check "shared key path is absent from the skip path" false
    ;;
  *)
    check "shared key path is absent from the skip path" true
    ;;
esac
# The alert text says "shared fleet key not used" and must not contain the path.
case "$alerts" in
  *"/.ssh/grotap_agents"*)
    check "alert does not cite the shared key path" false
    ;;
  *)
    check "alert does not cite the shared key path" true
    ;;
esac
if [ "$status" = "key-missing" ]; then
  check "host is marked key-missing" true
else
  check "host is marked key-missing (saw: $status)" false
fi
case "$health" in
  *"Status: DEGRADED"*)
    check "health output is DEGRADED" true
    ;;
  *)
    check "health output is DEGRADED (saw: $health)" false
    ;;
esac
if [ ! -f "$TMP/state/fail_count_agent-04-claude" ]; then
  check "skipped host is not counted as an SSH failure" true
else
  check "skipped host is not counted as an SSH failure" false
fi

echo "== a printed key is what ssh -i receives =="
printf 'not-the-shared-key\n' > "$TMP/seat-key"
run_monitor "$TMP/ssh-key-for-ok.sh"
invocations="$(cat "$TMP/ssh-invocations")"
case "$invocations" in
  *"-i $TMP/seat-key "*)
    check "ssh -i uses the resolver path" true
    ;;
  *)
    check "ssh -i uses the resolver path (saw: $invocations)" false
    ;;
esac
case "$invocations" in
  *grotap_agents*)
    check "success path does not pass the shared key" false
    ;;
  *)
    check "success path does not pass the shared key" true
    ;;
esac
if [ "$(cat "$TMP/state/fail_count_agent-04-claude")" = "0" ]; then
  check "reachable host resets the fail count" true
else
  check "reachable host resets the fail count" false
fi

echo
printf 'passed=%d failed=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
