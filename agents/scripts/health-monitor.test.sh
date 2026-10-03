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
case " $invocations" in
  *" -n "*)
    check "ssh is passed -n so it does not read stdin" true
    ;;
  *)
    check "ssh is passed -n so it does not read stdin (saw: $invocations)" false
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

echo "== missing shared key from the real resolver marks the host key-missing =="
# No per-host file and no grotap_agents. The resolver exits 1 and names
# the missing shared key. health-monitor must skip the host.
EMPTY_HOME="$(mktemp -d)"
mkdir -p "$EMPTY_HOME/.ssh"
rm -rf "$TMP/state" "$TMP/logs"
mkdir -p "$TMP/state" "$TMP/logs"
: > "$TMP/ssh-invocations"
HOME="$EMPTY_HOME" \
HEALTH_MONITOR_LOG="$TMP/logs/health-monitor.log" \
HEALTH_MONITOR_STATE_DIR="$TMP/state" \
HEALTH_MONITOR_ALERT_LOG="$TMP/logs/alerts.log" \
HEALTH_MONITOR_SKIP_HTTP=1 \
HEALTH_MONITOR_AGENTS="agent-04-claude:203.0.113.10" \
HEALTH_MONITOR_SSH_KEY_FOR="$SCRIPT_DIR/ssh-key-for.sh" \
HEALTH_MONITOR_SSH="$TMP/ssh" \
SSH_INVOCATIONS="$TMP/ssh-invocations" \
  bash "$MONITOR"
rm -rf "$EMPTY_HOME"
alerts="$(cat "$TMP/logs/alerts.log")"
invocations="$(cat "$TMP/ssh-invocations")"
status="$(cat "$TMP/state/key_status_agent-04-claude" 2>/dev/null || true)"
if [ ! -s "$TMP/ssh-invocations" ]; then
  check "missing shared key does not invoke ssh" true
else
  check "missing shared key does not invoke ssh (saw: $invocations)" false
fi
case "$alerts" in
  *"AGENT KEY-MISSING: agent-04-claude (203.0.113.10)"*"exited 1"*"does not exist"*"grotap_agents"*)
    check "missing shared key is logged as key-missing" true
    ;;
  *)
    check "missing shared key is logged as key-missing (saw: $alerts)" false
    ;;
esac
if [ "$status" = "key-missing" ]; then
  check "missing shared key marks the host key-missing" true
else
  check "missing shared key marks the host key-missing (saw: $status)" false
fi

echo "== deleted agent-05 is not on a monitor or fleet roster =="
# The default arrays, not HEALTH_MONITOR_AGENTS. A recycled 5.78.178.81
# must not be probed.
roster_block() {
  local file="$1" start="$2"
  awk -v start="$start" '
    index($0, start) == 1 { grab=1 }
    grab { print }
    grab && $0 ~ /^\)/ { exit }
  ' "$file"
}
for pair in \
  "$MONITOR|AGENTS=(" \
  "$SCRIPT_DIR/fleet-load.sh|HOSTS=(" \
  "$SCRIPT_DIR/sync-all-agents.sh|AGENTS=("
 do
  file="${pair%%|*}"
  start="${pair#*|}"
  block="$(roster_block "$file" "$start")"
  case "$block" in
    *agent-05*|*5.78.178.81*)
      check "no agent-05 in $file roster (saw: $block)" false
      ;;
    *agent-06-claude*)
      check "no agent-05 in $file roster" true
      ;;
    *)
      check "no agent-05 in $file roster (block missing agent-06: $block)" false
      ;;
  esac
done

echo "== post-cutover shared hosts are on the health roster =="
# Default AGENTS array only. HEALTH_MONITOR_AGENTS is a test override and
# is not the roster. forge-01, maps-01, and deleted agent-05 stay off it.
health_roster="$(roster_block "$MONITOR" "AGENTS=(")"
for need in \
  "agent-06-claude:5.161.53.103" \
  "agent-21-shared:5.161.119.92" \
  "agent-22-shared:178.156.215.173"
 do
  case "$health_roster" in
    *"$need"*)
      check "$need is on the health roster" true
      ;;
    *)
      check "$need is on the health roster (saw: $health_roster)" false
      ;;
  esac
done
# agent-01..04-claude were deleted (G6b); 5.161.74.39 is openreplay-02 and the
# other three addresses are released.
for banned in forge-01 maps-01 agent-05 178.156.246.81 5.161.107.80 5.78.178.81 \
    agent-01-claude agent-02-claude agent-03-claude agent-04-claude \
    5.161.74.39 5.161.81.193 178.156.222.220 5.161.73.195; do
  case "$health_roster" in
    *"$banned"*)
      check "$banned is absent from the health roster (saw: $health_roster)" false
      ;;
    *)
      check "$banned is absent from the health roster" true
      ;;
  esac
done

echo "== shared-host roster names resolve to the agent-06 root host key =="
# hostname agent-06, caller home standing in for root. The cloud name must
# print grotap_from06_<cloud-name>. claude@agent-21-shared prints the seat
# key and is the form the roster does not use. fleet-aliases.json is the
# repo file; this test does not add a stem.
ROOTISH="$(mktemp -d)"
HOSTBIN="$(mktemp -d)"
SEATDIR="$(mktemp -d)"
mkdir -p "$ROOTISH/.ssh"
printf 'host-21\n' > "$ROOTISH/.ssh/grotap_from06_agent-21-shared"
printf 'host-22\n' > "$ROOTISH/.ssh/grotap_from06_agent-22-shared"
printf 'shared\n' > "$ROOTISH/.ssh/grotap_agents"
printf 'seat-claude\n' > "$SEATDIR/grotap_from06_claude"
cat > "$HOSTBIN/hostname" <<'EOF'
#!/bin/sh
echo agent-06
EOF
chmod +x "$HOSTBIN/hostname"
for pair in \
  "agent-21-shared:grotap_from06_agent-21-shared" \
  "agent-22-shared:grotap_from06_agent-22-shared"
 do
  name="${pair%%:*}"
  want="${pair#*:}"
  rc=0
  got="$(PATH="$HOSTBIN:$PATH" HOME="$ROOTISH" bash "$SCRIPT_DIR/ssh-key-for.sh" "$name" 2>"$TMP/key-err")" || rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "$ROOTISH/.ssh/$want" ]; then
    check "$name resolves to $want" true
  else
    check "$name resolves to $want (rc=$rc got=$got err=$(cat "$TMP/key-err"))" false
  fi
done
rc=0
got="$(PATH="$HOSTBIN:$PATH" HOME="$ROOTISH" GROTAP_SEAT_KEY_DIR="$SEATDIR" bash "$SCRIPT_DIR/ssh-key-for.sh" "claude@agent-21-shared" 2>"$TMP/key-err")" || rc=$?
if [ "$rc" -eq 0 ] && [ "$got" = "$SEATDIR/grotap_from06_claude" ]; then
  check "seat form resolves to the seat key, not the host key" true
else
  check "seat form resolves to the seat key, not the host key (rc=$rc got=$got)" false
fi
case "$health_roster" in
  *claude@*|*astra@*|*codex@*|*grok@*|*monitor@*)
    check "health roster does not use a seat user" false
    ;;
  *)
    check "health roster does not use a seat user" true
    ;;
esac
rm -rf "$ROOTISH" "$HOSTBIN" "$SEATDIR"

echo
printf 'passed=%d failed=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
