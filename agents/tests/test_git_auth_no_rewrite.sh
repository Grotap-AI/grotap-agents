#!/bin/bash
# agents/tests/test_git_auth_no_rewrite.sh
#
# ensure_git_auth in agents/scripts/orchestrator-run.sh must NOT write a helper
# file or any git config (2026-10-03: the old version rewrote
# ~/bin/git-credential-doppler and credential.helper on every case and broke
# the claude seat's pushes). It selects the box's root-owned helper for the
# runner process only (GIT_CONFIG_COUNT):
#   T1 agent + fleet helper  -> fleet helper wins over a stale ~/bin helper
#   T2 seat + seat helper    -> seat helper
#   T3 seat pointed at a fleet-named helper -> never the fleet helper; no seat
#      helper installed -> no helper at all (fails closed), WARN logged
#   T4 agent, no fleet helper (ops-01) -> configured helper left alone
#   T5 nothing under $HOME changes; the runner text has no helper writes and
#      no grotap/prd fallback
# Run: bash agents/tests/test_git_auth_no_rewrite.sh   (no network, no secrets)
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT/agents/scripts/orchestrator-run.sh"
PASS=0; FAIL=0
ok()  { echo "  ok   $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
BLOCK="$TMP/block.sh"
sed -n '/^# ── Git auth: choose the box/,/^# ── Bootstrap pin (P1-B)/p' "$RUNNER" > "$BLOCK"
grep -q '^ensure_git_auth()' "$BLOCK" || { echo "FAIL: ensure_git_auth block not found"; exit 1; }

mk_helper() {  # $1 path, $2 password it returns
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\n[ "${1:-get}" = get ] || exit 0\nprintf "username=x-access-token\\npassword=%s\\n"\n' "$2" > "$1"
  chmod +x "$1"
}
FLEET="$TMP/lib/grotap/git-credential-doppler";             mk_helper "$FLEET" FLEET
SEAT="$TMP/lib/grotap-seat/git-credential-seat-doppler";    mk_helper "$SEAT" SEAT

# Each case runs in a fresh fake HOME that already has a STALE helper in its
# global config, like the boxes the old runner left behind.
run_case() {  # $1 name; rest: env assignments
  local name="$1"; shift
  local home="$TMP/home-$name"; mkdir -p "$home/bin" "$home/logs"
  mk_helper "$home/bin/git-credential-doppler" STALE
  printf '[credential]\n\thelper = !%s\n' "$home/bin/git-credential-doppler" > "$home/.gitconfig"
  ( cd "$home" && find . -type f -exec sha256sum {} + | sort ) > "$TMP/$name.before"
  env -i PATH="$PATH" HOME="$home" "$@" bash -c '
    LOG="$HOME/logs/run.log"; log() { echo "$*" >> "$LOG"; }
    source "'"$BLOCK"'"
    ensure_git_auth
    printf "protocol=https\nhost=github.com\n\n" | git credential fill 2>/dev/null | sed -n "s/^password=//p" > "$HOME/../'"$name"'.pw"
    echo "${GIT_CONFIG_COUNT:-unset}" > "$HOME/../'"$name"'.count"
  '
  rm -f "$home/logs/run.log.keep"
  ( cd "$home" && find . -type f ! -path ./logs/run.log -exec sha256sum {} + | sort ) > "$TMP/$name.after"
}

echo "T1 agent with the root fleet helper"
run_case t1 GROTAP_RUN_USER=agent GROTAP_FLEET_GIT_HELPER="$FLEET"
eq "T1 fleet helper answers, stale ~/bin helper does not" "$(cat "$TMP/t1.pw")" "FLEET"
eq "T1 process-local config only" "$(cat "$TMP/t1.count")" "2"

echo "T2 seat with its root seat helper"
run_case t2 GROTAP_RUN_USER=claude GROTAP_SEAT_GIT_HELPER="$SEAT" GROTAP_FLEET_GIT_HELPER="$FLEET"
eq "T2 seat helper answers" "$(cat "$TMP/t2.pw")" "SEAT"

echo "T3 seat pointed at a fleet-named helper, no seat helper installed"
run_case t3 GROTAP_RUN_USER=codex GROTAP_SEAT_GIT_HELPER="$FLEET" GROTAP_FLEET_GIT_HELPER="$FLEET"
eq "T3 no credential at all (fails closed, never FLEET or STALE)" "$(cat "$TMP/t3.pw")" ""
eq "T3 every inherited helper cleared" "$(cat "$TMP/t3.count")" "1"
if grep -q "fail closed" "$TMP/home-t3/logs/run.log" 2>/dev/null; then ok "T3 WARN logged"; else bad "T3 WARN logged"; fi

echo "T4 agent on a box without the fleet helper (ops-01)"
run_case t4 GROTAP_RUN_USER=agent GROTAP_FLEET_GIT_HELPER="$TMP/absent/git-credential-doppler"
eq "T4 configured helper left in charge" "$(cat "$TMP/t4.pw")" "STALE"
eq "T4 no process config injected" "$(cat "$TMP/t4.count")" "unset"

echo "T5 nothing written; no helper writes in the runner"
for c in t1 t2 t3 t4; do
  if diff -q "$TMP/$c.before" "$TMP/$c.after" >/dev/null; then ok "T5 $c: HOME files unchanged"; else bad "T5 $c: HOME files changed"; fi
done
eq "T5 no heredoc helper write"   "$(grep -c 'cat > "\$HOME/bin/git-credential-doppler"' "$RUNNER")" "0"
eq "T5 no credential.helper config writes" "$(grep -E -c 'git (-C [^ ]+ )?config (--global )?--replace-all credential\.helper' "$RUNNER")" "0"
eq "T5 no grotap/prd fallback"    "$(grep -c -- '--project grotap --config prd' "$RUNNER")" "0"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
