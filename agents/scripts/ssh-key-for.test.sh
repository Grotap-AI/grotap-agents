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
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/ssh-key-for.sh"

# Resolve against a scratch HOME so the result depends on the resolver's table,
# not on which keys this particular machine happens to have on disk.
FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME"' EXIT
mkdir -p "$FAKE_HOME/.ssh"
for k in grotap_agents grotap_agent-04 grotap_claudecode-01 grotap_cobrowse-01 grotap_maps-01; do
  : > "$FAKE_HOME/.ssh/$k"
done

PASS=0
FAIL=0

# expect <target> <expected-key-basename> <description>
expect() {
  local target="$1" want="$2" desc="$3" got
  got="$(HOME="$FAKE_HOME" bash "$RESOLVER" "$target")"
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
expect "agent-04"                      grotap_agent-04      "fleet name"
expect "178.156.222.220"               grotap_agent-04      "fleet IP"
expect "claudecode.grotap.com"         grotap_claudecode-01 "DNS alias"
expect "5.161.189.143"                 grotap_cobrowse-01   "cobrowse IP"

echo "== non-canonical caller tokens must NOT fall back to the shared key =="
expect "root@178.156.222.220"          grotap_agent-04      "ssh destination"
expect "ROOT@Agent-04"                 grotap_agent-04      "destination + mixed case"
expect "[178.156.222.220]:2222"        grotap_agent-04      "bracketed + port"
expect "178.156.222.220:22"            grotap_agent-04      "port suffix"
expect "Claudecode.Grotap.Com"         grotap_claudecode-01 "mixed-case DNS"
expect "SUPPORTAGENTS.GROTAP.COM:22"   grotap_cobrowse-01   "upper DNS + port"
expect "root@supportagents.grotap.com" grotap_cobrowse-01   "destination + DNS"

echo "== whitespace-padded tokens must NOT fall back to the shared key =="
expect " agent-04 "                    grotap_agent-04      "padded name"
expect "  178.156.222.220"             grotap_agent-04      "leading space on an IP"
expect "root@supportagents.grotap.com " grotap_cobrowse-01  "trailing space on a destination"

echo "== genuinely unknown targets still fall back (deliberate) =="
expect "not-a-host-we-own"             grotap_agents        "unknown name"
expect "198.51.100.7"                  grotap_agents        "unknown IP"
expect "2a01:4f8:2240:195b::1"         grotap_agents        "bare IPv6 literal is not split on ':'"

echo
printf 'passed=%d failed=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
