#!/bin/bash
# agents/tests/test_orchestrator_run_security.sh
#
# Security regression cover for agents/scripts/orchestrator-run.sh — the LIVE
# fleet runner (orchestrator/src/nodes/execute.ts invokes
# `bash ~/grotap-agents/agents/scripts/orchestrator-run.sh`).
#
#   Permission policy / secret narrowing (CLAUDE_PERMISSION_MODE)
#     T1  bypass (DEFAULT) → claude argv byte-identical to the pre-change argv,
#                            no --settings, no env stripping
#     T2  acceptEdits      → --permission-mode + --settings passed, and
#                            NODE_SECRET / DOPPLER_TOKEN / GITHUB_TOKEN are
#                            absent from claude's environment
#     T3  settings file    → valid JSON, written atomically (no .tmp residue),
#                            and carries the audit's corrections
#
#   Tool-denial visibility
#     T4  a denial in permission_denials is named EXPLICITLY, says it is NOT an
#         API/credit failure, and reaches the emitted result — not just the log
#     T5  no denial → no denial noise
#
#   Bootstrap pin (ORCH_BOOTSTRAP_PIN) — P1-B
#     T6   DEFAULT (detach): the PINNED commit is checked out and run, the tip
#          is not, and the staleness is logged
#     T6b  detach, pin IS the tip → VERIFIED, nothing moves
#     T6c  ancestor mode (legacy detector) → descent verified, TIP is what runs
#     T6d  an unrecognised mode falls back to detach with a warning
#     T7   detach, history rewritten → SECURITY WARNING, blessed tree still
#          runs (a force-push must not become a fleet-wide kill switch)
#     T7b  ancestor mode, history rewritten → ABORT, run never reaches the model
#     T7c  pinned commit absent from the repo → ABORT
#     T8   exact mode, tip moved → ABORT
#     T9   off → loud warning, proceeds
#     T10 pin file absent → loud warning, proceeds (a host must not be bricked)
#
# No SSH, no network, no Anthropic API, no fleet host. Everything runs against a
# sandboxed $HOME with mock git repos and a stubbed claude/doppler.
# Usage: bash agents/tests/test_orchestrator_run_security.sh [--verbose]

set -uo pipefail
VERBOSE=0; [[ "${1:-}" == "--verbose" ]] && VERBOSE=1

PASS=0; FAIL=0
TMP=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$SCRIPT_DIR/../scripts/orchestrator-run.sh"
trap 'rm -rf "$TMP"' EXIT

# The runner emits its result line via python3. On Windows Git Bash `python3`
# usually resolves to the Microsoft Store app-execution alias, which prints
# "Python was not found..." and produces NO output — every result-parsing
# assertion then fails for a reason that has nothing to do with the code under
# test. Detect it and say so, rather than reporting 38 mystery failures.
if ! printf '' | python3 -c 'pass' >/dev/null 2>&1; then
  echo "FATAL: python3 is not a working interpreter here." >&2
  echo "  On Windows this is usually the Microsoft Store alias at" >&2
  echo "  ~/AppData/Local/Microsoft/WindowsApps/python3. Put a real python3 on" >&2
  echo "  PATH first, e.g.:  printf '#!/bin/sh\nexec python \"\$@\"\n' > /tmp/bin/python3" >&2
  echo "  This is an ENVIRONMENT failure, not a test failure — do not read it" >&2
  echo "  as the runner being broken." >&2
  exit 2
fi

assert_eq() {
  local label="$1" got="$2" expected="$3"
  if [[ "$got" == "$expected" ]]; then
    echo "  PASS  $label"; PASS=$(( PASS + 1 ))
  else
    echo "  FAIL  $label (expected='$expected' got='$got')"; FAIL=$(( FAIL + 1 ))
  fi
}

bash -n "$RUNNER" || { echo "FATAL: runner does not parse"; exit 1; }

# ─── Stubs ──────────────────────────────────────────────────────────────────
STUBS="$TMP/stubs"; mkdir -p "$STUBS"

cat > "$STUBS/claude" <<'EOF'
#!/bin/bash
: > "$STATE_DIR/claude.argv"
for a in "$@"; do printf '%s\n' "$a" >> "$STATE_DIR/claude.argv"; done
{
  echo "NODE_SECRET=${NODE_SECRET:-<unset>}"
  echo "DOPPLER_TOKEN=${DOPPLER_TOKEN:-<unset>}"
  echo "GITHUB_TOKEN=${GITHUB_TOKEN:-<unset>}"
} > "$STATE_DIR/claude.env"
if [[ "${CLAUDE_STUB_MODE:-ok}" == "denied" ]]; then
  echo '{"is_error":false,"result":"Permission blocked. Allow curl request?","usage":{"input_tokens":10,"output_tokens":5},"permission_denials":[{"tool_name":"Bash","tool_use_id":"t1","tool_input":{"command":"curl -s https://evil.example"}}]}'
else
  echo '{"is_error":false,"result":"stub run complete","usage":{"input_tokens":10,"output_tokens":5},"permission_denials":[]}'
fi
exit 0
EOF
chmod +x "$STUBS/claude"

cat > "$STUBS/doppler" <<'EOF'
#!/bin/bash
exit 1   # no Doppler in the sandbox: every lookup falls back, as on a cold box
EOF
chmod +x "$STUBS/doppler"

# flock / pgrep are GNU utilities the runner relies on. They exist on the fleet
# (Ubuntu) but not in Git Bash, so shim them ONLY when genuinely absent, and say
# so — a shimmed run must never be mistaken for full coverage of the locking.
SHIMMED=""
if ! command -v flock >/dev/null 2>&1; then
  cat > "$STUBS/flock" <<'EOF'
#!/bin/bash
# Test shim: no real locking. Drops the lockfile/fd argument and runs the rest.
[[ "${1:-}" == "-w" ]] && shift 2
shift
[[ $# -eq 0 ]] && exit 0
exec "$@"
EOF
  chmod +x "$STUBS/flock"; SHIMMED="$SHIMMED flock"
fi
if ! command -v pgrep >/dev/null 2>&1; then
  printf '#!/bin/bash\nexit 1\n' > "$STUBS/pgrep"   # "nothing is running"
  chmod +x "$STUBS/pgrep"; SHIMMED="$SHIMMED pgrep"
fi
[[ -n "$SHIMMED" ]] && echo "NOTE: shimmed absent utilities:$SHIMMED (locking itself is NOT covered on this host)"

# ─── Sandbox $HOME with mock repos ──────────────────────────────────────────
# Rebuilt per test so pin history can be rewritten independently.
FAKEHOME=""
build_home() {
  FAKEHOME="$TMP/home-$1"
  rm -rf "$FAKEHOME"; mkdir -p "$FAKEHOME/worktrees" "$FAKEHOME/logs"

  # grotap-platform: bare origin + working clone with a master commit.
  git init --bare "$FAKEHOME/platform-origin.git" -q
  printf 'ref: refs/heads/master\n' > "$FAKEHOME/platform-origin.git/HEAD"
  git clone "$FAKEHOME/platform-origin.git" "$FAKEHOME/grotap-platform" -q 2>/dev/null
  (
    cd "$FAKEHOME/grotap-platform"
    git config user.email t@t.com; git config user.name T
    echo base > base.txt; git add base.txt; git commit -q -m base
    git push -u origin master -q 2>/dev/null
  )

  # grotap-agents: bare origin + clone. PIN_BASE is the first commit; a second
  # commit is layered on so ancestor mode has something to descend from.
  git init --bare "$FAKEHOME/agents-origin.git" -q
  printf 'ref: refs/heads/master\n' > "$FAKEHOME/agents-origin.git/HEAD"
  git clone "$FAKEHOME/agents-origin.git" "$FAKEHOME/grotap-agents" -q 2>/dev/null
  (
    cd "$FAKEHOME/grotap-agents"
    git config user.email t@t.com; git config user.name T
    mkdir -p agents/scripts
    echo one > agents/one.txt; git add -A; git commit -q -m one
    git push -u origin master -q 2>/dev/null
  )
  PIN_BASE=$(git -C "$FAKEHOME/grotap-agents" rev-parse HEAD)
  (
    cd "$FAKEHOME/grotap-agents"
    echo two > agents/two.txt; git add -A; git commit -q -m two
    git push origin master -q 2>/dev/null
  )
  AGENTS_TIP=$(git -C "$FAKEHOME/grotap-agents" rev-parse HEAD)
  PIN_FILE="$FAKEHOME/grotap-agents/agents/BOOTSTRAP_SHA"
}

# Rewrite grotap-agents origin/master onto an unrelated root — the force-push /
# history-rewrite case the pin exists to catch.
rewrite_agents_history() {
  local wt="$TMP/rewrite"; rm -rf "$wt"
  git clone "$FAKEHOME/agents-origin.git" "$wt" -q 2>/dev/null
  (
    cd "$wt"
    git config user.email e@e.com; git config user.name E
    git checkout --orphan evil -q
    git rm -rf . -q 2>/dev/null || true
    mkdir -p agents; echo pwned > agents/one.txt
    git add -A; git commit -q -m "unrelated root"
    git push origin evil:master --force -q 2>/dev/null
  )
}

PAYLOAD='{"case_id":"CASE-20260915-AAAAAA","branch":"case-20260915-aaaaaa","title":"t","context":"c","requirements":"r","complexity":"simple","attempt":1}'

run() { # env KEY=VAL ... → sets OUT, RESULT_JSON
  mkdir -p "$TMP/state"; rm -f "$TMP/state/claude.argv" "$TMP/state/claude.env"
  OUT=$(printf '%s' "$PAYLOAD" | \
    env PATH="$STUBS:$PATH" HOME="$FAKEHOME" USERPROFILE="$FAKEHOME" STATE_DIR="$TMP/state" \
        ANTHROPIC_API_KEY=test-key NODE_SECRET=node-secret-value \
        DOPPLER_TOKEN=dp.st.fake GITHUB_TOKEN=ghp_fake \
        "$@" bash "$RUNNER" 2>&1)
  [[ $VERBOSE -eq 1 ]] && printf '%s\n' "--- out ---" "$OUT" "--- log ---" "$(cat "$FAKEHOME/logs/orchestrator-run.log" 2>/dev/null)" "-----------"
  RESULT_JSON=$(printf '%s\n' "$OUT" | python3 -c '
import sys, json
last = ""
for line in sys.stdin.read().splitlines():
    line = line.strip()
    if line.startswith("{") and line.endswith("}"):
        try:
            json.loads(line); last = line
        except ValueError:
            pass
print(last)')
  return 0
}
rfield() { printf '%s' "$RESULT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$1',''))" 2>/dev/null; }
argv_has() { grep -qxF -- "$1" "$TMP/state/claude.argv" 2>/dev/null && echo yes || echo no; }
argv_flags() { tr '\n' ' ' < "$TMP/state/claude.argv" 2>/dev/null | sed 's/ $//'; }
logged() { local n; n=$(grep -c -- "$1" "$FAKEHOME/logs/orchestrator-run.log" 2>/dev/null); echo "${n:-0}"; }
atleast1() { [[ "${1:-0}" -ge 1 ]] && echo yes || echo no; }

# ═══ Permission policy ══════════════════════════════════════════════════════
echo "T1: CLAUDE_PERMISSION_MODE default (bypass) → argv unchanged, env intact"
build_home t1; printf '%s\n' "$PIN_BASE" > "$PIN_FILE"
run
assert_eq "T1 claude invoked" "$([[ -f "$TMP/state/claude.argv" ]] && echo yes || echo no)" "yes"
assert_eq "T1 keeps --dangerously-skip-permissions" "$(argv_has '--dangerously-skip-permissions')" "yes"
assert_eq "T1 no --settings" "$(argv_has '--settings')" "no"
assert_eq "T1 no --permission-mode" "$(argv_has '--permission-mode')" "no"
assert_eq "T1 NODE_SECRET still inherited" "$(grep -c '^NODE_SECRET=node-secret-value$' "$TMP/state/claude.env")" "1"
assert_eq "T1 GITHUB_TOKEN still inherited" "$(grep -c '^GITHUB_TOKEN=ghp_fake$' "$TMP/state/claude.env")" "1"

echo "T2: acceptEdits → policy passed and credentials stripped"
build_home t2; printf '%s\n' "$PIN_BASE" > "$PIN_FILE"
run CLAUDE_PERMISSION_MODE=acceptEdits
assert_eq "T2 --permission-mode passed" "$(argv_has '--permission-mode')" "yes"
assert_eq "T2 mode value" "$(argv_has 'acceptEdits')" "yes"
assert_eq "T2 --settings passed" "$(argv_has '--settings')" "yes"
assert_eq "T2 no --dangerously-skip-permissions" "$(argv_has '--dangerously-skip-permissions')" "no"
assert_eq "T2 NODE_SECRET stripped" "$(grep -c '^NODE_SECRET=<unset>$' "$TMP/state/claude.env")" "1"
assert_eq "T2 DOPPLER_TOKEN stripped" "$(grep -c '^DOPPLER_TOKEN=<unset>$' "$TMP/state/claude.env")" "1"
assert_eq "T2 GITHUB_TOKEN stripped" "$(grep -c '^GITHUB_TOKEN=<unset>$' "$TMP/state/claude.env")" "1"

echo "T3: settings file is valid JSON, written atomically, and audit-corrected"
SETTINGS="$FAKEHOME/.config/orchestrator/claude-settings.json"
assert_eq "T3 settings file exists" "$([[ -f "$SETTINGS" ]] && echo yes || echo no)" "yes"
assert_eq "T3 no .tmp residue" "$(ls "$FAKEHOME/.config/orchestrator/" | grep -c '\.tmp$')" "0"
# Read via stdin, not by path: bash resolves the sandbox path, a Windows python
# would not understand the MSYS form.
setting_q() { python3 -c "$1" < "$SETTINGS" 2>/dev/null; }
assert_eq "T3 valid JSON" \
  "$(setting_q "import sys,json;json.load(sys.stdin);print('ok')")" "ok"
assert_eq "T3 WebFetch denied (acceptEdits does not gate it via allow)" \
  "$(setting_q "import sys,json;print('WebFetch' in json.load(sys.stdin)['permissions']['deny'])")" "True"
assert_eq "T3 direct push to master denied" \
  "$(setting_q "import sys,json;print('Bash(git push origin master)' in json.load(sys.stdin)['permissions']['deny'])")" "True"
assert_eq "T3 Grep allowed explicitly" \
  "$(setting_q "import sys,json;print('Grep' in json.load(sys.stdin)['permissions']['allow'])")" "True"
assert_eq "T3 no launcher smuggled into allow" \
  "$(setting_q "
import sys, json
allow = json.load(sys.stdin)['permissions']['allow']
verbs = [x.split('(')[1].split(' ')[0].rstrip(')') for x in allow if '(' in x]
print([v for v in verbs if v in ('bash','sh','xargs','timeout','tar','make','docker','nohup','setsid')])")" "[]"

# ═══ Tool-denial visibility ═════════════════════════════════════════════════
echo "T4: a denied tool is named explicitly and reaches the result"
build_home t4; printf '%s\n' "$PIN_BASE" > "$PIN_FILE"
run CLAUDE_PERMISSION_MODE=acceptEdits CLAUDE_STUB_MODE=denied
assert_eq "T4 named in the run log" "$(atleast1 "$(logged 'TOOL DENIED BY THE RUNNER PERMISSION POLICY')")" "yes"
assert_eq "T4 log names the command" "$(atleast1 "$(logged 'curl -s https://evil.example')")" "yes"
assert_eq "T4 log says NOT an API failure" "$(atleast1 "$(logged 'NOT an Anthropic API or credit failure')")" "yes"
assert_eq "T4 carried into the emitted errors" \
  "$(printf '%s' "$(rfield errors)" | grep -c 'TOOL DENIED BY THE RUNNER PERMISSION POLICY')" "1"
assert_eq "T4 emitted errors still say no commits" \
  "$(printf '%s' "$(rfield errors)" | grep -c 'No commits produced')" "1"

echo "T5: no denial → no denial noise"
build_home t5; printf '%s\n' "$PIN_BASE" > "$PIN_FILE"
run CLAUDE_PERMISSION_MODE=acceptEdits
assert_eq "T5 silent" "$(logged 'TOOL DENIED BY THE RUNNER PERMISSION POLICY')" "0"

# ═══ Bootstrap pin ══════════════════════════════════════════════════════════
# The DEFAULT is now `detach`: the runner checks the PINNED commit out and runs
# it, instead of verifying ancestry and then running the tip. The mock repo has
# PIN_BASE (first commit, carries agents/one.txt) and AGENTS_TIP (second commit,
# adds agents/two.txt), so "did the pin actually decide what is on disk?" is
# answerable from the working tree: pinned at PIN_BASE => two.txt must NOT exist.
bhead() { git -C "$FAKEHOME/grotap-agents" rev-parse HEAD 2>/dev/null; }

echo "T6: DEFAULT (detach), pin behind the tip → the PIN is checked out, not the tip"
build_home t6; printf '%s\n' "$PIN_BASE" > "$PIN_FILE"
run
assert_eq "T6 HEAD is the pinned commit" "$(bhead)" "$PIN_BASE"
assert_eq "T6 tip content is NOT on disk" \
  "$([[ -f "$FAKEHOME/grotap-agents/agents/two.txt" ]] && echo present || echo absent)" "absent"
assert_eq "T6 says it is pinned and names the staleness" \
  "$(atleast1 "$(logged 'Bootstrap tree PINNED at')")" "yes"
assert_eq "T6 detach is logged" "$(atleast1 "$(logged 'CHECKED OUT detached at pinned')")" "yes"
# The sandbox cannot complete a real run on Windows (the runner fails later at
# "Could not trust worktree"), so assert the PIN did not abort it, not that the
# whole run succeeded.
assert_eq "T6 the pin did NOT abort the run" "$(printf '%s' "$(rfield errors)" | grep -c 'bootstrap pin')" "0"

echo "T6b: DEFAULT (detach), pin IS the tip → verified, nothing moves"
build_home t6b
printf '%s\n' "$AGENTS_TIP" > "$PIN_FILE"
run
assert_eq "T6b HEAD is the pinned tip" "$(bhead)" "$AGENTS_TIP"
assert_eq "T6b VERIFIED line names detach mode" \
  "$(atleast1 "$(logged 'VERIFIED at pinned .* (mode=detach')")" "yes"

echo "T6c: ORCH_BOOTSTRAP_PIN=ancestor → legacy detector, runs the TIP"
build_home t6c; printf '%s\n' "$PIN_BASE" > "$PIN_FILE"
run ORCH_BOOTSTRAP_PIN=ancestor
assert_eq "T6c descent logged" "$(atleast1 "$(logged 'descends from pinned')")" "yes"
assert_eq "T6c HEAD is the TIP, not the pin" "$(bhead)" "$AGENTS_TIP"

echo "T6d: an unrecognised mode falls back to detach, loudly (a typo must not disable the pin)"
build_home t6d; printf '%s\n' "$PIN_BASE" > "$PIN_FILE"
run ORCH_BOOTSTRAP_PIN=ancestorr
assert_eq "T6d warns about the unrecognised value" \
  "$(atleast1 "$(logged 'unrecognised ORCH_BOOTSTRAP_PIN')")" "yes"
assert_eq "T6d still enforced the pin" "$(bhead)" "$PIN_BASE"

echo "T7: detach mode, history rewritten → the BLESSED tree still runs, loudly"
# A force-push cannot be allowed to stop the fleet: what runs is the pinned
# commit, which the rewrite did not change. It must be flagged, not obeyed.
build_home t7; printf '%s\n' "$PIN_BASE" > "$PIN_FILE"
rewrite_agents_history
run
assert_eq "T7 rewrite is called out as a SECURITY WARNING" \
  "$(atleast1 "$(logged 'SECURITY WARNING')")" "yes"
assert_eq "T7 HEAD is the pinned commit, not the rewrite" "$(bhead)" "$PIN_BASE"
assert_eq "T7 bootstrap tree NOT reset onto the rewrite" \
  "$(cat "$FAKEHOME/grotap-agents/agents/one.txt")" "one"
assert_eq "T7 dispatch was NOT bricked by someone else's force-push" "$(printf '%s' "$(rfield errors)" | grep -c 'bootstrap pin')" "0"

echo "T7b: ancestor mode, history rewritten → ABORT before anything lands"
build_home t7b; printf '%s\n' "$PIN_BASE" > "$PIN_FILE"
rewrite_agents_history
rm -f "$TMP/state/claude.argv"
run ORCH_BOOTSTRAP_PIN=ancestor
assert_eq "T7b status failed" "$(rfield status)" "failed"
assert_eq "T7b names the broken pin" "$(printf '%s' "$(rfield errors)" | grep -c 'bootstrap pin')" "1"
assert_eq "T7b model NEVER ran" "$([[ -f "$TMP/state/claude.argv" ]] && echo yes || echo no)" "no"
assert_eq "T7b bootstrap tree NOT reset onto the rewrite" \
  "$(cat "$FAKEHOME/grotap-agents/agents/one.txt")" "one"

echo "T7c: pinned commit does not exist here at all → ABORT (nothing blessed to run)"
build_home t7c
printf '%s\n' "0123456789abcdef0123456789abcdef01234567" > "$PIN_FILE"
rm -f "$TMP/state/claude.argv"
run
assert_eq "T7c status failed" "$(rfield status)" "failed"
assert_eq "T7c says the pinned commit does not exist" \
  "$(printf '%s' "$(rfield errors)" | grep -c 'does not exist')" "1"
assert_eq "T7c model NEVER ran" "$([[ -f "$TMP/state/claude.argv" ]] && echo yes || echo no)" "no"

echo "T8: exact mode, tip moved past the pin → ABORT"
build_home t8; printf '%s\n' "$PIN_BASE" > "$PIN_FILE"
rm -f "$TMP/state/claude.argv"
run ORCH_BOOTSTRAP_PIN=exact
assert_eq "T8 status failed" "$(rfield status)" "failed"
assert_eq "T8 says MISMATCH (exact)" "$(printf '%s' "$(rfield errors)" | grep -c 'MISMATCH (exact)')" "1"
assert_eq "T8 model NEVER ran" "$([[ -f "$TMP/state/claude.argv" ]] && echo yes || echo no)" "no"

echo "T9: ORCH_BOOTSTRAP_PIN=off → warn, proceed"
build_home t9; printf '%s\n' "$PIN_BASE" > "$PIN_FILE"
rewrite_agents_history   # even with a broken pin, off must not block
run ORCH_BOOTSTRAP_PIN=off
assert_eq "T9 warns" "$(atleast1 "$(logged 'bootstrap pin DISABLED')")" "yes"
assert_eq "T9 nothing is pinned — the tree follows origin" \
  "$(cat "$FAKEHOME/grotap-agents/agents/one.txt")" "pwned"

echo "T10: pin file absent → warn, proceed (host must not be bricked)"
build_home t10   # no pin file written
run
assert_eq "T10 warns UNPINNED" "$(atleast1 "$(logged 'UNPINNED')")" "yes"
assert_eq "T10 tree follows origin (nothing detached)" "$(bhead)" "$AGENTS_TIP"
# The negative half of T11, and the one that protects the fresh host: the
# fail-open path must NOT stamp the seen-marker. If it did, a first run on an
# unpinned host would stamp, and the NEXT run — pin file still absent for the
# same innocent reason — would hard-fail and brick exactly the host the
# fail-open exists to protect.
assert_eq "T10 fail-open does NOT stamp the marker"   "$([[ -f "$FAKEHOME/.grotap_bootstrap_pin_seen" ]] && echo yes || echo no)" "no"
run   # second run, pin still absent: must STILL warn-and-proceed, not brick
assert_eq "T10 second run still proceeds" "$(printf '%s' "$(rfield errors)" | grep -c 'bootstrap pin')" "0"

echo "T10b: ORCH_BOOTSTRAP_PIN=off must not stamp either"
build_home t10b; printf '%s\n' "$PIN_BASE" > "$PIN_FILE"
run ORCH_BOOTSTRAP_PIN=off
assert_eq "T10b off does NOT stamp the marker"   "$([[ -f "$FAKEHOME/.grotap_bootstrap_pin_seen" ]] && echo yes || echo no)" "no"

echo "T11: successful verify stamps the seen-marker outside the git tree"
build_home t11; printf '%s\n' "$PIN_BASE" > "$PIN_FILE"
run
assert_eq "T11 marker created" "$([[ -f "$FAKEHOME/.grotap_bootstrap_pin_seen" ]] && echo yes || echo no)" "yes"
assert_eq "T11 marker is outside the repo"   "$([[ -e "$FAKEHOME/grotap-agents/.grotap_bootstrap_pin_seen" ]] && echo inside || echo outside)" "outside"

echo "T12: pin DELETED after a previous verify → fail closed (not warn-and-proceed)"
build_home t12; printf '%s\n' "$PIN_BASE" > "$PIN_FILE"
run                                   # first run verifies and stamps the marker
assert_eq "T12 marker present after first run"   "$([[ -f "$FAKEHOME/.grotap_bootstrap_pin_seen" ]] && echo yes || echo no)" "yes"
rm -f "$PIN_FILE"                     # one ordinary commit deletes the pin
rm -f "$TMP/state/claude.argv"        # forget that the model ran the first time
run
assert_eq "T12 status failed" "$(rfield status)" "failed"
assert_eq "T12 says WENT MISSING" "$(printf '%s' "$(rfield errors)" | grep -c 'WENT MISSING')" "1"
assert_eq "T12 model NEVER ran" "$([[ -f "$TMP/state/claude.argv" ]] && echo yes || echo no)" "no"

echo "T13: pin CORRUPTED after a previous verify → fail closed"
build_home t13; printf '%s\n' "$PIN_BASE" > "$PIN_FILE"
run
rm -f "$TMP/state/claude.argv"
printf 'not-a-sha\n' > "$PIN_FILE"
run
assert_eq "T13 status failed" "$(rfield status)" "failed"
assert_eq "T13 says CORRUPT" "$(printf '%s' "$(rfield errors)" | grep -c 'CORRUPT')" "1"
assert_eq "T13 model NEVER ran" "$([[ -f "$TMP/state/claude.argv" ]] && echo yes || echo no)" "no"

# ─── Pin PARSING against a realistic file ───────────────────────────────────
# Every test above writes a pin file that is one bare SHA and nothing else. The
# file that actually ships is ~100 lines of comment header with the SHA last,
# and a reader that folds it onto a single line (tr -d '\n' instead of '\r')
# finds NO line matching ^[0-9a-f]{40}$ and silently reports "UNPINNED" — the
# control off, with nothing louder than a log line. These two bind the parser to
# a file shaped like the real one, on both source paths.
_write_realistic_pin() {   # $1 = path, $2 = SHA, $3 = lf|crlf
  local path="$1" sha="$2" kind="${3:-lf}"
  local l1='# agents/BOOTSTRAP_SHA — supply-chain pin (P1-B)'
  local l2='#'
  local l3='# ROTATION: resolve the tip from the remote, review the diff,'
  local l4='# replace the SHA line below, commit, push. Modes: detach/ancestor/exact/off.'
  if [[ "$kind" == "crlf" ]]; then
    printf '%s\r\n%s\r\n%s\r\n%s\r\n%s\r\n' "$l1" "$l2" "$l3" "$l4" "$sha" > "$path"
  else
    printf '%s\n%s\n%s\n%s\n%s\n'           "$l1" "$l2" "$l3" "$l4" "$sha" > "$path"
  fi
}

echo "T14: a real commented pin file (CRLF) parses from the working tree"
build_home t14
_write_realistic_pin "$PIN_FILE" "$PIN_BASE" crlf
run
assert_eq "T14 not reported as unpinned" "$(logged 'UNPINNED')" "0"
assert_eq "T14 the commented CRLF pin was enforced" "$(bhead)" "$PIN_BASE"

echo "T15: a real commented pin file COMMITTED to master parses from origin/master"
build_home t15
_write_realistic_pin "$PIN_FILE" "$PIN_BASE" lf
(
  cd "$FAKEHOME/grotap-agents"
  git add agents/BOOTSTRAP_SHA >/dev/null 2>&1
  git commit -q -m "pin" >/dev/null 2>&1
  git push -q origin master >/dev/null 2>&1
)
run
assert_eq "T15 read from the fetched remote, not the working tree" \
  "$(atleast1 "$(logged 'Bootstrap pin source: origin/master')")" "yes"
assert_eq "T15 not reported as unpinned" "$(logged 'UNPINNED')" "0"
assert_eq "T15 the commented pin was enforced" "$(bhead)" "$PIN_BASE"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
