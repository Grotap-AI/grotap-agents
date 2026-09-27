#!/bin/bash
# Tests for ssh-key-for.sh — the single authority for per-target SSH key
# selection (phase 2b of retiring the shared fleet key, 2026-09-16).
#
# The property under test is one-directional and safety-critical: a target that
# names a host we own must NEVER resolve to the shared fleet key, whatever form
# the caller's token happens to take. Every miss falls back to the shared key
# silently, so a canonicalization gap does not look like a bug at the call
# site — it looks like everything working, on fleet-wide credentials.
#
# Run: bash agents/scripts/ssh-key-for.test.sh
# The file under test is a TWIN kept byte-identical in grotap-platform and
# grotap-agents; run this after changing either copy.
# This grotap-agents copy stages fleet-aliases.json under a tmpdir. The
# platform test reads the committed agents/fleet-aliases.json instead.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The twin is byte-identical to grotap-platform and looks for
# <parent-of-script>/fleet-aliases.json only when that file exists.
# grotap-agents does not ship that platform file. Stage a byte copy of the
# in-repo twin plus a fixture so these assertions do not depend on it and
# the twin itself stays unmodified.
_STAGE="$(mktemp -d)"
mkdir -p "$_STAGE/scripts"
cp "$SCRIPT_DIR/ssh-key-for.sh" "$_STAGE/scripts/ssh-key-for.sh"
cat > "$_STAGE/fleet-aliases.json" <<'EOF'
{
  "remove_after": "2026-10-03",
  "aliases": {
    "agent-01": "agent-01-claude",
    "agent-02": "agent-02-claude",
    "agent-03": "agent-03-claude",
    "agent-04": "agent-04-claude",
    "agent-05": "agent-05-claude",
    "agent-06": "agent-06-claude",
    "agent-06-ash": "agent-06-claude",
    "grotap-agent-06-ash": "agent-06-claude",
    "agent-20": "agent-10-codex",
    "agent-40": "monitor-01-deepseek",
    "cobrowse-01": "openreplay-01",
    "grotap-cobrowse-01": "openreplay-01",
    "runner-01": "openreplay-ai-support",
    "grotap-runner-01": "openreplay-ai-support"
  },
  "key_file_stems": {
    "agent-01-claude": ["agent-01"],
    "agent-02-claude": ["agent-02"],
    "agent-03-claude": ["agent-03"],
    "agent-04-claude": ["agent-04"],
    "agent-05-claude": ["agent-05"],
    "agent-06-claude": ["agent-06"],
    "agent-10-codex": ["agent-20"],
    "monitor-01-deepseek": ["agent-40"],
    "openreplay-01": ["cobrowse-01"],
    "openreplay-ai-support": ["runner-01"]
  }
}
EOF
RESOLVER="$_STAGE/scripts/ssh-key-for.sh"

# Resolve against a scratch HOME so the result depends on the resolver's table,
# not on which keys this particular machine happens to have on disk.
FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME" "$_STAGE"' EXIT
mkdir -p "$FAKE_HOME/.ssh"
for k in grotap_agents grotap_agent-01 grotap_agent-02 grotap_agent-03 grotap_agent-04 grotap_agent-05 grotap_claudecode-01 grotap_prompt-01-claude grotap_cobrowse-01 grotap_maps-01 grotap_forge-01; do
  : > "$FAKE_HOME/.ssh/$k"
done

PASS=0
FAIL=0

# expect <target> <expected-key-basename> <description>
expect() {
  local target="$1" want="$2" desc="$3" got
  got="$(HOME="$FAKE_HOME" GROTAP_SEAT_KEY_DIR="$FAKE_HOME/.ssh" bash "$RESOLVER" "$target")"
  got="${got##*/}"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    printf '  ok   %-34s -> %s\n' "$target" "$got"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL %-34s -> %s (want %s) [%s]\n' "$target" "$got" "$want" "$desc"
  fi
}

echo "== canonical forms =="
# Desktop key grotap_agent-0N matches alias agent-0N. No offset.
expect "agent-01"                      grotap_agent-01      "alias agent-01"
expect "5.161.74.39"                   grotap_agent-01      "agent-01 IP"
expect "agent-02"                      grotap_agent-02      "alias agent-02"
expect "5.161.81.193"                  grotap_agent-02      "agent-02 IP"
expect "agent-03"                      grotap_agent-03      "alias agent-03"
expect "178.156.222.220"               grotap_agent-03      "agent-03 IP"
expect "agent-04"                      grotap_agent-04      "alias agent-04"
expect "5.161.73.195"                  grotap_agent-04      "agent-04 IP"
expect "claudecode.grotap.com"         grotap_agents        "deleted jump seat DNS"
expect "178.156.246.81"                grotap_forge-01      "forge-01 IP"
expect "forge-01"                      grotap_forge-01      "forge-01 name"
expect "5.78.178.81"                   grotap_agents        "retired agent-05 stays unmapped"
expect "178.156.209.112"               grotap_agents        "retired prompt-01 stays unmapped"
expect "5.161.189.143"                 grotap_cobrowse-01   "cobrowse IP"

echo "== non-canonical caller tokens must NOT fall back to the shared key =="
expect "root@178.156.222.220"          grotap_agent-03      "ssh destination"
expect "ROOT@Agent-03"                 grotap_agent-03      "destination + mixed case"
expect "[178.156.222.220]:2222"        grotap_agent-03      "bracketed + port"
expect "178.156.222.220:22"            grotap_agent-03      "port suffix"
expect "Claudecode.Grotap.Com"         grotap_agents        "deleted jump seat DNS mixed case"
expect "SUPPORTAGENTS.GROTAP.COM:22"   grotap_cobrowse-01   "upper DNS + port"
expect "root@supportagents.grotap.com" grotap_cobrowse-01   "destination + DNS"

echo "== whitespace-padded tokens must NOT fall back to the shared key =="
expect " agent-03 "                    grotap_agent-03      "padded name"
expect "  178.156.222.220"             grotap_agent-03      "leading space on an IP"
expect "root@supportagents.grotap.com " grotap_cobrowse-01  "trailing space on a destination"

echo "== Astra is per-host even when the key file is not minted yet =="
# FAKE_HOME has grotap_agents and not the Astra files. These must not pick it.
expect "5.161.243.18"                 grotap_prompt-01-astra       "astra prompt IP"
expect "prompt-01-astra"              grotap_prompt-01-astra       "astra prompt name"
expect "5.161.80.75"                  grotap_agent-team-01-astra   "astra agent IP"
expect "agent-team-01-astra"          grotap_agent-team-01-astra   "astra agent name"
expect "5.161.119.92"                 grotap_agent-21-shared       "shared host IP"
expect "agent-21-shared"              grotap_agent-21-shared       "shared host name"
expect "178.156.215.173"              grotap_agent-22-shared       "agent-22-shared IP"
expect "agent-22-shared"              grotap_agent-22-shared       "agent-22-shared name"

echo "== Team Grok is per-host even when the key file is not minted yet =="
# Same rule as Astra. FAKE_HOME has grotap_agents and not the Grok files.
expect "5.161.83.78"                  grotap_agent-01-grok         "grok 01 IP"
expect "agent-01-grok"                grotap_agent-01-grok         "grok 01 name"
expect "5.161.82.78"                  grotap_agent-02-grok         "grok 02 IP"
expect "agent-02-grok"                grotap_agent-02-grok         "grok 02 name"

echo "== Hetzner stem wins when that key file exists; forge-01 is unchanged =="
: > "$FAKE_HOME/.ssh/grotap_agent-01-claude"
expect "agent-01"                      grotap_agent-01-claude "alias prefers the Hetzner key file"
expect "agent-01-claude"               grotap_agent-01-claude "Hetzner name"
expect "5.161.74.39"                   grotap_agent-01-claude "IP prefers the Hetzner key file"
expect "178.156.246.81"                grotap_forge-01        "forge-01 IP still the forge key"
expect "forge-01"                      grotap_forge-01        "forge-01 name still the forge key"
expect "5.78.178.81"                   grotap_agents          "deleted Hillsboro agent-05 stays unmapped"

echo "== alias map is ignored after 2026-10-03 =="
: > "$FAKE_HOME/.ssh/grotap_agent-04-claude"
err="$(mktemp)"
got="$(HOME="$FAKE_HOME" FLEET_ALIAS_TODAY=2026-10-03 bash "$RESOLVER" agent-04 2>"$err")"
got="${got##*/}"
if [[ "$got" == "grotap_agent-04-claude" ]]; then
  PASS=$((PASS + 1))
  printf '  ok   %-34s -> %s\n' "agent-04 on 2026-10-03" "$got"
else
  FAIL=$((FAIL + 1))
  printf '  FAIL %-34s -> %s (want grotap_agent-04-claude)\n' "agent-04 on 2026-10-03" "$got"
fi
got="$(HOME="$FAKE_HOME" FLEET_ALIAS_TODAY=2026-10-04 bash "$RESOLVER" agent-04 2>"$err")"
got="${got##*/}"
if [[ "$got" == "grotap_agent-04" && "$(cat "$err")" == *"ignoring alias map"* ]]; then
  PASS=$((PASS + 1))
  printf '  ok   %-34s -> %s\n' "agent-04 after 2026-10-03" "$got"
else
  FAIL=$((FAIL + 1))
  printf '  FAIL %-34s -> %s (want grotap_agent-04) stderr=%s\n' "agent-04 after 2026-10-03" "$got" "$(cat "$err")"
fi
rm -f "$err" "$FAKE_HOME/.ssh/grotap_agent-04-claude" "$FAKE_HOME/.ssh/grotap_agent-01-claude"

echo "== a dedicated team user never borrows another team's key =="
# astra_ed25519 and grotap_agents are on disk. A missing claude key must
# exit non-zero and print nothing — not claude_ed25519, not grotap_agents.
: > "$FAKE_HOME/.ssh/astra_ed25519"
expect_closed() {
  local target="$1" desc="$2" got rc=0
  got="$(HOME="$FAKE_HOME" GROTAP_SEAT_KEY_DIR="$FAKE_HOME/.ssh" bash "$RESOLVER" "$target" 2>/dev/null)" || rc=$?
  if [[ -z "$got" && "$rc" -ne 0 && "$got" != *grotap_agents* ]]; then
    PASS=$((PASS + 1))
    printf '  ok   %-34s -> exit %s (no path)\n' "$target" "$rc"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL %-34s -> [%s] rc=%s (%s)\n' "$target" "$got" "$rc" "$desc"
  fi
}
expect_closed "claude@"                 "user with no host is refused"
expect_closed "claude@agent-21-shared" "missing team key exits non-zero"
expect_closed "claude@10.0.0.21"       "user@ip missing key"
expect_closed "../x@agent-21-shared"   "traversal user is refused"
expect_closed "claude/../../etc@host"  "slash in the user is refused"
: > "$FAKE_HOME/.ssh/claude_ed25519"
expect "claude@agent-21-shared"        claude_ed25519       "present team key"
expect "claude@10.0.0.21"              claude_ed25519       "user@ip"
expect "Claude@Agent-21-Shared"        claude_ed25519       "mixed case is lowercased"
expect "agent@agent-01"                grotap_agent-01      "agent@ stays on the host key"
expect "root@5.161.74.39"              grotap_agent-01      "root@ stays on the host key"
expect "agent-11-codex"                grotap_agent-11-codex "codex box does not take the shared key"
expect "agent-13-monitor"              grotap_agent-13-monitor "monitor box does not take the shared key"
expect "forge-01"                      grotap_forge-01      "forge name uses the workstation file when that file exists"
expect "5.78.178.81"                   grotap_agents        "released agent-05 address is not mapped"
expect "178.156.209.112"               grotap_agents        "released prompt-01-claude address is not mapped"

echo "== genuinely unknown targets still fall back (deliberate) =="
expect "not-a-host-we-own"             grotap_agents        "unknown name"
expect "198.51.100.7"                  grotap_agents        "unknown IP"
expect "2a01:4f8:2240:195b::1"         grotap_agents        "bare IPv6 literal is not split on ':'"

echo "== forge-01 has no own key deployed, so it stays on the shared key =="
# The rows above see grotap_forge-01 because this fixture mints it. Nothing
# in the fleet has that file. Without it, the name, the address, and an
# ssh destination all use grotap_agents (header: forge-01 keeps the shared key).
rm -f "$FAKE_HOME/.ssh/grotap_forge-01"
expect "forge-01"                      grotap_agents        "forge name, no own key"
expect "178.156.246.81"                grotap_agents        "forge IP, no own key"
expect "root@178.156.246.81"           grotap_agents        "forge destination, no own key"

echo "== pre-rename key files on agent-06 stay selected after 2026-10-03 =="
# Layout from the header (grotap_from06_agent-0{2,3,4,5}) plus the stems
# status-server.js tries when the Hetzner-named file is absent. Those
# Hetzner-named files are not created. forge-01 has no own key.
KEY_HOME="$(mktemp -d)"
mkdir -p "$KEY_HOME/.ssh"
: > "$KEY_HOME/.ssh/grotap_agents"
for stem in agent-01 agent-02 agent-03 agent-04 agent-05 agent-06 agent-20 agent-40; do
  : > "$KEY_HOME/.ssh/grotap_from06_${stem}"
done
HOSTBIN="$(mktemp -d)"
cat > "$HOSTBIN/hostname" <<'EOF'
#!/bin/sh
echo agent-06
EOF
chmod +x "$HOSTBIN/hostname"
expect_same_day() {
  local day="$1" target="$2" want="$3" got
  got="$(PATH="$HOSTBIN:$PATH" HOME="$KEY_HOME" FLEET_ALIAS_TODAY="$day" bash "$RESOLVER" "$target")"
  got="${got##*/}"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    printf '  ok   %-34s -> %s\n' "$day $target" "$got"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL %-34s -> %s (want %s)\n' "$day $target" "$got" "$want"
  fi
}
for day in 2026-10-03 2026-10-04; do
  expect_same_day "$day" "5.161.74.39"          grotap_from06_agent-01
  expect_same_day "$day" "agent-01-claude"      grotap_from06_agent-01
  expect_same_day "$day" "5.161.81.193"         grotap_from06_agent-02
  expect_same_day "$day" "agent-02-claude"      grotap_from06_agent-02
  expect_same_day "$day" "178.156.222.220"      grotap_from06_agent-03
  expect_same_day "$day" "agent-03-claude"      grotap_from06_agent-03
  expect_same_day "$day" "5.161.73.195"         grotap_from06_agent-04
  expect_same_day "$day" "agent-04-claude"      grotap_from06_agent-04
  expect_same_day "$day" "5.161.53.103"         grotap_from06_agent-06
  expect_same_day "$day" "agent-06-claude"      grotap_from06_agent-06
  expect_same_day "$day" "87.99.148.22"         grotap_from06_agent-20
  expect_same_day "$day" "agent-10-codex"       grotap_from06_agent-20
  expect_same_day "$day" "178.156.219.232"      grotap_from06_agent-40
  expect_same_day "$day" "monitor-01-deepseek"  grotap_from06_agent-40
  expect_same_day "$day" "forge-01"             grotap_agents
  expect_same_day "$day" "178.156.246.81"       grotap_agents
done
rm -rf "$KEY_HOME" "$HOSTBIN"

echo "== python3 is required to load key_file_stems =="
# The staged fleet-aliases.json sits next to the resolver copy. Without
# python3 the stem table cannot be built; the call must fail and print no
# key path.
# PATH keeps the rest of the OS tools and omits every python interpreter.
nopy="$(mktemp -d)"
for dir in /usr/bin /bin; do
  for bin in "$dir"/*; do
    base="${bin##*/}"
    case "$base" in
      python|python3|python3.*) continue ;;
    esac
    if [[ ! -e "$nopy/$base" ]]; then
      ln -s "$bin" "$nopy/$base"
    fi
  done
done
py_rc=0
py_out="$(PATH="$nopy" HOME="$FAKE_HOME" FLEET_ALIAS_TODAY="2026-09-27" bash "$RESOLVER" "agent-01-claude" 2>"$nopy/err")" || py_rc=$?
py_err="$(cat "$nopy/err")"
if [[ "$py_rc" -ne 0 && -z "$py_out" && "$py_err" == *"python3 is required to load fleet aliases and key_file_stems"* ]]; then
  PASS=$((PASS + 1))
  printf '  ok   missing python3 exits 1 and names the dependency\n'
else
  FAIL=$((FAIL + 1))
  printf '  FAIL missing python3 rc=%s stdout=%q stderr=%q\n' "$py_rc" "$py_out" "$py_err"
fi
rm -rf "$nopy"

echo "== seat keys use one directory for root and agent callers =="
# Dispatch on agent-06 is root. The seat authorizes only the agent user's
# key. A decoy under the caller's own home must not be selected.
SEAT_CANON="$(mktemp -d)"
SEAT_ROOTISH="$(mktemp -d)"
SEAT_AGENTISH="$(mktemp -d)"
SEAT_HOSTBIN="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME" "$_STAGE" "$SEAT_CANON" "$SEAT_ROOTISH" "$SEAT_AGENTISH" "$SEAT_HOSTBIN"' EXIT
mkdir -p "$SEAT_ROOTISH/.ssh" "$SEAT_AGENTISH/.ssh"
printf 'decoy-root\n' > "$SEAT_ROOTISH/.ssh/grotap_from06_claude"
printf 'decoy-root\n' > "$SEAT_ROOTISH/.ssh/claude_ed25519"
printf 'decoy-agent\n' > "$SEAT_AGENTISH/.ssh/grotap_from06_claude"
printf 'decoy-agent\n' > "$SEAT_AGENTISH/.ssh/claude_ed25519"
printf 'canonical\n' > "$SEAT_CANON/grotap_from06_claude"
chmod 600 "$SEAT_CANON/grotap_from06_claude"
cat > "$SEAT_HOSTBIN/hostname" <<'EOF'
#!/bin/sh
echo agent-06
EOF
chmod +x "$SEAT_HOSTBIN/hostname"
seat_ok() {
  local desc="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1))
    printf '  ok   %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL %s -> [%s] (want %s)\n' "$desc" "$got" "$want"
  fi
}
for _seat_pair in "root:$SEAT_ROOTISH" "agent:$SEAT_AGENTISH"; do
  _seat_label="${_seat_pair%%:*}"
  _seat_home="${_seat_pair#*:}"
  _seat_got="$(PATH="$SEAT_HOSTBIN:$PATH" HOME="$_seat_home" GROTAP_SEAT_KEY_DIR="$SEAT_CANON" bash "$RESOLVER" "claude@agent-21-shared")"
  seat_ok "$_seat_label caller uses the canonical from06 key" "$_seat_got" "$SEAT_CANON/grotap_from06_claude"
  case "$_seat_got" in
    "$_seat_home"/*) seat_ok "$_seat_label caller ignores its own home" "used-home" "canonical" ;;
    *) seat_ok "$_seat_label caller ignores its own home" "canonical" "canonical" ;;
  esac
done

echo "== a missing seat key fails closed and names the canonical dir =="
rm -f "$SEAT_CANON/grotap_from06_claude" "$SEAT_CANON/claude_ed25519" "$SEAT_CANON/grotap_claude"
_seat_err="$(mktemp)"
_seat_rc=0
_seat_got="$(PATH="$SEAT_HOSTBIN:$PATH" HOME="$SEAT_ROOTISH" GROTAP_SEAT_KEY_DIR="$SEAT_CANON" bash "$RESOLVER" "claude@agent-21-shared" 2>"$_seat_err")" || _seat_rc=$?
if [[ -z "$_seat_got" && "$_seat_rc" -ne 0 && "$(cat "$_seat_err")" == *"$SEAT_CANON"* && "$(cat "$_seat_err")" != *"$SEAT_ROOTISH"* ]]; then
  PASS=$((PASS + 1))
  printf '  ok   missing key names %s\n' "$SEAT_CANON"
else
  FAIL=$((FAIL + 1))
  printf '  FAIL missing key got=[%s] rc=%s stderr=%s\n' "$_seat_got" "$_seat_rc" "$(cat "$_seat_err")"
fi
_seat_rc=0
_seat_got="$(HOME="$SEAT_ROOTISH" env -u GROTAP_SEAT_KEY_DIR PATH="$SEAT_HOSTBIN:$PATH" bash "$RESOLVER" "seatprobe@agent-21-shared" 2>"$_seat_err")" || _seat_rc=$?
if [[ -z "$_seat_got" && "$_seat_rc" -ne 0 && "$(cat "$_seat_err")" == *"/home/agent/.ssh"* && "$(cat "$_seat_err")" != *"$SEAT_ROOTISH"* ]]; then
  PASS=$((PASS + 1))
  printf '  ok   unset GROTAP_SEAT_KEY_DIR names /home/agent/.ssh\n'
else
  FAIL=$((FAIL + 1))
  printf '  FAIL default dir got=[%s] rc=%s stderr=%s\n' "$_seat_got" "$_seat_rc" "$(cat "$_seat_err")"
fi
_seat_rc=0
_seat_got="$(HOME="$SEAT_AGENTISH" GROTAP_SEAT_KEY_DIR='' PATH="$SEAT_HOSTBIN:$PATH" bash "$RESOLVER" "seatprobe@agent-21-shared" 2>"$_seat_err")" || _seat_rc=$?
if [[ -z "$_seat_got" && "$_seat_rc" -ne 0 && "$(cat "$_seat_err")" == *"/home/agent/.ssh"* && "$(cat "$_seat_err")" != *"$SEAT_AGENTISH"* ]]; then
  PASS=$((PASS + 1))
  printf '  ok   empty GROTAP_SEAT_KEY_DIR names /home/agent/.ssh\n'
else
  FAIL=$((FAIL + 1))
  printf '  FAIL empty dir got=[%s] rc=%s stderr=%s\n' "$_seat_got" "$_seat_rc" "$(cat "$_seat_err")"
fi

echo "== an unreadable seat key does not fall through =="
printf 'secret\n' > "$SEAT_CANON/grotap_from06_claude"
printf 'weaker\n' > "$SEAT_CANON/claude_ed25519"
chmod 600 "$SEAT_CANON/claude_ed25519"
if [[ "$(id -u)" -eq 0 ]]; then
  # root can read mode 000. A non-file still fails the regular-file check.
  rm -f "$SEAT_CANON/grotap_from06_claude"
  mkdir "$SEAT_CANON/grotap_from06_claude"
else
  chmod 000 "$SEAT_CANON/grotap_from06_claude"
fi
_seat_rc=0
_seat_got="$(PATH="$SEAT_HOSTBIN:$PATH" HOME="$SEAT_ROOTISH" GROTAP_SEAT_KEY_DIR="$SEAT_CANON" bash "$RESOLVER" "claude@agent-21-shared" 2>"$_seat_err")" || _seat_rc=$?
if [[ -z "$_seat_got" && "$_seat_rc" -eq 1 && "$(cat "$_seat_err")" == *"not readable"* && "$_seat_got" != *claude_ed25519* && "$(cat "$_seat_err")" != *claude_ed25519* ]]; then
  PASS=$((PASS + 1))
  printf '  ok   unreadable key fails closed\n'
else
  FAIL=$((FAIL + 1))
  printf '  FAIL unreadable got=[%s] rc=%s stderr=%s\n' "$_seat_got" "$_seat_rc" "$(cat "$_seat_err")"
fi
rm -f "$_seat_err"
rm -rf "$SEAT_CANON" "$SEAT_ROOTISH" "$SEAT_AGENTISH" "$SEAT_HOSTBIN"

echo
printf 'passed=%d failed=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
