#!/bin/bash
# Golden + contract tests for the orchestrator-run.sh wrapper (PR-3).
#
# A fixed team1 payload (the historical shape: no team, no driver) run against
# a stubbed claude must emit the same result object master emitted, plus
# driver_result and log_tag. Cache tokens stay out of the back-compat integer.
#
# No SSH, no network, no Anthropic API. Usage:
#   bash agents/tests/test_orchestrator_run_golden.sh [--verbose]

set -uo pipefail
VERBOSE=0; [[ "${1:-}" == "--verbose" ]] && VERBOSE=1

PASS=0; FAIL=0
TMP=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$SCRIPT_DIR/../scripts/orchestrator-run.sh"
DRIVER="$SCRIPT_DIR/../scripts/drivers/run-claude.sh"
FAKE_DRIVER=""
trap 'rm -f "$FAKE_DRIVER"; rm -rf "$TMP"' EXIT

if ! printf '' | python3 -c 'pass' >/dev/null 2>&1; then
  echo "FATAL: python3 is not a working interpreter" >&2
  exit 2
fi
bash -n "$RUNNER" || { echo "FATAL: wrapper does not parse"; exit 1; }
bash -n "$DRIVER" || { echo "FATAL: claude driver does not parse"; exit 1; }
[ -x "$DRIVER" ] || { echo "FATAL: claude driver is not executable"; exit 1; }

assert_eq() {
  local label="$1" got="$2" expected="$3"
  if [[ "$got" == "$expected" ]]; then
    echo "  PASS  $label"; PASS=$(( PASS + 1 ))
  else
    echo "  FAIL  $label"
    echo "        expected: $expected"
    echo "        got:      $got"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ── Static: wrapper does not branch on the tool ────────────────────────────
echo "S1: wrapper dispatches by driver name and does not call claude itself"
assert_eq "S1 no claude -p invocation in the wrapper" \
  "$(grep -v '^[[:space:]]*#' "$RUNNER" | grep -c 'claude -p ' || true)" "0"
# The quoted path appears twice: the executable check, and the one exec.
# There is no third copy and no per-tool command.
dispatch_n=$(grep -cF '"$HERE/drivers/run-${DRIVER}.sh"' "$RUNNER" || true)
assert_eq "S1 driver path is only the check and the one exec" "$dispatch_n" "2"
assert_eq "S1 default claude only appears as the team1 default" \
  "$(grep -c 'DRIVER="claude"' "$RUNNER")" "1"
assert_eq "S1 driver has no retry loop" \
  "$(grep -c '^while ' "$DRIVER" || true)" "0"
assert_eq "S1 driver has the two historical claude -p branches only" \
  "$(grep -c 'claude -p "\$PROMPT"' "$DRIVER")" "2"

# ── Sandbox ────────────────────────────────────────────────────────────────
STUBS="$TMP/stubs"; mkdir -p "$STUBS"
cat > "$STUBS/claude" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then
  echo "claude-stub 0.0.0"
  exit 0
fi
: > "$STATE_DIR/claude.argv"
for a in "$@"; do printf '%s\n' "$a" >> "$STATE_DIR/claude.argv"; done
{
  echo "NODE_SECRET=${NODE_SECRET:-<unset>}"
  echo "GITHUB_TOKEN=${GITHUB_TOKEN:-<unset>}"
} > "$STATE_DIR/claude.env"
mode="${CLAUDE_STUB_MODE:-ok}"
if [[ "$mode" == "err" ]]; then
  echo '{"is_error":true,"result":"boom","usage":{"input_tokens":3,"output_tokens":4},"permission_denials":[]}'
elif [[ "$mode" == "cache" ]]; then
  echo '{"is_error":false,"result":"stub run complete","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":40,"cache_creation_input_tokens":60},"permission_denials":[]}'
elif [[ "$mode" == "denied" ]]; then
  echo '{"is_error":false,"result":"Permission blocked. Allow curl request?","usage":{"input_tokens":10,"output_tokens":5},"permission_denials":[{"tool_name":"Bash","tool_use_id":"t1","tool_input":{"command":"curl -s https://evil.example"}}]}'
elif [[ "$mode" == "commit" ]]; then
  echo '{"is_error":false,"result":"stub run complete","usage":{"input_tokens":10,"output_tokens":5},"permission_denials":[]}'
  echo touched > README-golden.txt
  git -c user.email=t@t.com -c user.name=T add README-golden.txt
  git -c user.email=t@t.com -c user.name=T commit -q -m "agent: golden"
elif [[ "$mode" == "empty" ]]; then
  # error_max_turns: is_error with an empty result string. Master's tab
  # split collapsed that empty field, so tokens came out as 5.
  echo '{"is_error":true,"result":"","subtype":"error_max_turns","usage":{"input_tokens":10,"output_tokens":5},"permission_denials":[]}'
elif [[ "$mode" == "nonjson0" ]]; then
  echo 'not-json'
elif [[ "$mode" == "trunc" ]]; then
  printf '%s' '{"is_error":false,"result":"partial"'
elif [[ "$mode" == "emptycommit" ]]; then
  echo '{"is_error":true,"result":"","usage":{"input_tokens":10,"output_tokens":5},"permission_denials":[]}'
  echo touched > README-golden.txt
  git -c user.email=t@t.com -c user.name=T add README-golden.txt
  git -c user.email=t@t.com -c user.name=T commit -q -m "agent: empty result"
elif [[ "$mode" == "r429text0" ]]; then
  echo '429 Too Many Requests: rate limit exceeded'
elif [[ "$mode" == "credit" ]]; then
  echo '{"is_error":true,"result":"Your credit balance is too low","usage":{"input_tokens":2,"output_tokens":1},"permission_denials":[]}'
else
  echo '{"is_error":false,"result":"stub run complete","usage":{"input_tokens":10,"output_tokens":5},"permission_denials":[]}'
fi
exit 0
EOF
chmod +x "$STUBS/claude"
printf '#!/bin/bash\nexit 1\n' > "$STUBS/doppler"
chmod +x "$STUBS/doppler"

FAKEHOME=""
PIN_BASE=""
AGENTS_TIP=""
PLATFORM_HEAD=""

build_home() {
  FAKEHOME="$TMP/home-$1"
  rm -rf "$FAKEHOME"
  mkdir -p "$FAKEHOME/worktrees" "$FAKEHOME/logs"
  git init --bare "$FAKEHOME/platform-origin.git" -q
  printf 'ref: refs/heads/master\n' > "$FAKEHOME/platform-origin.git/HEAD"
  git clone "$FAKEHOME/platform-origin.git" "$FAKEHOME/grotap-platform" -q 2>/dev/null
  (
    cd "$FAKEHOME/grotap-platform"
    git config user.email t@t.com; git config user.name T
    echo base > base.txt; git add base.txt; git commit -q -m base
    git push -u origin master -q 2>/dev/null
  )
  git init --bare "$FAKEHOME/agents-origin.git" -q
  printf 'ref: refs/heads/master\n' > "$FAKEHOME/agents-origin.git/HEAD"
  git clone "$FAKEHOME/agents-origin.git" "$FAKEHOME/grotap-agents" -q 2>/dev/null
  (
    cd "$FAKEHOME/grotap-agents"
    git config user.email t@t.com; git config user.name T
    mkdir -p agents
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
  PLATFORM_HEAD=$(git -C "$FAKEHOME/grotap-platform" rev-parse HEAD)
  printf '%s\n' "$PIN_BASE" > "$FAKEHOME/grotap-agents/agents/BOOTSTRAP_SHA"
}

# Fixed historical team1 payload: no team, no driver.
TEAM1_PAYLOAD='{"case_id":"CASE-20260915-AAAAAA","branch":"case-20260915-aaaaaa","title":"t","context":"c","requirements":"r","complexity":"simple","attempt":1}'

NO_COMMIT_GOLDEN='{"status": "failed", "branch": "case-20260915-aaaaaa", "exit_code": 1, "errors": "No commits produced on case-20260915-aaaaaa", "summary": "Agent made no committed changes", "tokens": 15, "verify": {"checks": [], "passed": false, "details": ""}}'
SUCCESS_GOLDEN='{"status": "success", "branch": "case-20260915-aaaaaa", "exit_code": 0, "errors": "", "summary": "stub run complete", "tokens": 15, "verify": {"checks": [], "passed": true, "details": ""}}'
ERROR_GOLDEN='{"status": "failed", "branch": "case-20260915-aaaaaa", "exit_code": 0, "errors": "Claude CLI error: boom", "summary": "Agent run failed", "tokens": 7}'

STDOUT_FILE=""; STDERR_FILE=""; RESULT_JSON=""
run() { # payload is $PAYLOAD (global); extra env via "$@"
  mkdir -p "$TMP/state"
  rm -f "$TMP/state/claude.argv" "$TMP/state/claude.env"
  STDOUT_FILE="$TMP/stdout"; STDERR_FILE="$TMP/stderr"
  printf '%s' "$PAYLOAD" | \
    env PATH="$STUBS:$PATH" HOME="$FAKEHOME" STATE_DIR="$TMP/state" \
        ANTHROPIC_API_KEY=test-key NODE_SECRET=node-secret-value \
        DOPPLER_TOKEN=dp.st.fake GITHUB_TOKEN=ghp_fake \
        "$@" bash "$RUNNER" >"$STDOUT_FILE" 2>"$STDERR_FILE" || true
  [[ $VERBOSE -eq 1 ]] && { echo "--- stdout ---"; cat "$STDOUT_FILE"; echo "--- stderr ---"; cat "$STDERR_FILE"; }
  RESULT_JSON=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).read_text().strip().splitlines()[-1] if pathlib.Path(sys.argv[1]).read_text().strip() else "")' "$STDOUT_FILE")
}

# Like run(), but keeps the process status. --merge is the only caller:
# deploy.ts treats exit 0 as merged, so a refusal must be non-zero.
RUN_RC=0
run_merge() {
  mkdir -p "$TMP/state"
  rm -f "$TMP/state/claude.argv" "$TMP/state/claude.env"
  STDOUT_FILE="$TMP/stdout"; STDERR_FILE="$TMP/stderr"
  RUN_RC=0
  printf '%s' "$PAYLOAD" | \
    env PATH="$STUBS:$PATH" HOME="$FAKEHOME" STATE_DIR="$TMP/state" \
        ANTHROPIC_API_KEY=test-key NODE_SECRET=node-secret-value \
        DOPPLER_TOKEN=dp.st.fake GITHUB_TOKEN=ghp_fake \
        "$@" bash "$RUNNER" --merge >"$STDOUT_FILE" 2>"$STDERR_FILE" || RUN_RC=$?
  [[ $VERBOSE -eq 1 ]] && { echo "--- rc $RUN_RC ---"; echo "--- stdout ---"; cat "$STDOUT_FILE"; echo "--- stderr ---"; cat "$STDERR_FILE"; }
  RESULT_JSON=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).read_text().strip().splitlines()[-1] if pathlib.Path(sys.argv[1]).read_text().strip() else "")' "$STDOUT_FILE")
}

# Print a python expression over RESULT_JSON. $1 is the expression, d is the object.
j() { printf '%s' "$RESULT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); $1"; }

base_matches() { # $1 golden JSON text
  printf '%s' "$RESULT_JSON" | python3 -c '
import json, sys
got = json.load(sys.stdin)
golden = json.loads(sys.argv[1])
got.pop("driver_result", None)
got.pop("log_tag", None)
print("yes" if got == golden else "no")
' "$1"
}

schema_ok() {
  j '
need = ["schema","team","driver","driver_version","tool_bin","provider","model","profile","status","error_class","summary","errors","tokens","cost","attempts_inside_driver","session_id","started_at","ended_at"]
dr = d["driver_result"]
missing = [k for k in need if k not in dr]
tok = dr["tokens"]
tneed = ["input","cached_input","cache_write_input","output","reasoning","total"]
cneed = ["usd","source","price_table_version","long_context_multiplier_applied"]
bad = missing + [k for k in tneed if k not in tok] + [k for k in cneed if k not in dr["cost"]]
print("yes" if dr.get("schema")=="driver-result/v1" and not bad and tok["cached_input"]<=tok["input"] and tok["cache_write_input"]<=tok["input"] and tok["cached_input"]+tok["cache_write_input"]<=tok["input"] and tok["total"]==tok["input"]+tok["output"] else "no")
'
}

framed() {
  local tag; tag="$(j 'print(d["log_tag"])')"
  python3 -c '
import pathlib, sys
err = pathlib.Path(sys.argv[1]).read_text()
tag = sys.argv[2]
begin = "=====RUN-LOG-BEGIN %s=====" % tag
end = "=====RUN-LOG-END====="
b = err.find(begin)
e = err.find(end)
print("yes" if b >= 0 and e > b and "driver_result" not in err else "no")
' "$STDERR_FILE" "$tag"
}

agents_head() { git -C "$FAKEHOME/grotap-agents" rev-parse HEAD 2>/dev/null; }
claude_ran() { [[ -f "$TMP/state/claude.argv" ]] && echo yes || echo no; }

PAYLOAD="$TEAM1_PAYLOAD"

echo "G1: historical team1 payload, no commits — base line matches master"
build_home g1
run
assert_eq "G1 base result unchanged" "$(base_matches "$NO_COMMIT_GOLDEN")" "yes"
assert_eq "G1 schema" "$(schema_ok)" "yes"
assert_eq "G1 log framed on stderr" "$(framed)" "yes"
assert_eq "G1 stdout is one JSON line" "$(wc -l < "$STDOUT_FILE" | tr -d ' ')" "1"
assert_eq "G1 per-run log exists" \
  "$(ls "$FAKEHOME/logs/runs/"*"$(j 'print(d["log_tag"])')".log 2>/dev/null | wc -l | tr -d ' ')" "1"
assert_eq "G1 shared log kept" "$([[ -f "$FAKEHOME/logs/orchestrator-run.log" ]] && echo yes || echo no)" "yes"
assert_eq "G1 ran from the /tmp snapshot" \
  "$(grep -c 'runner snapshot active: /tmp/runner-' "$FAKEHOME/logs/orchestrator-run.log")" "1"
assert_eq "G1 driver is claude/sonnet" "$(j 'print(d["driver_result"]["driver"]+" "+d["driver_result"]["model"])')" "claude claude-sonnet-4-6"
assert_eq "G1 team defaulted to team1" "$(j 'print(d["driver_result"]["team"])')" "team1"
assert_eq "G1 missing host label did not refuse" "$(j 'print(d["errors"].startswith("error_class=infra"))')" "False"
assert_eq "G1 driver error_class null" "$(j 'print(d["driver_result"]["error_class"])')" "None"
assert_eq "G1 re-exec skipped the second fetch" \
  "$(grep -c 'skipping bootstrap fetch' "$FAKEHOME/logs/orchestrator-run.log")" "1"
assert_eq "G1 bootstrap checkout happened once" \
  "$(grep -c 'Bootstrap tree CHECKED OUT' "$FAKEHOME/logs/orchestrator-run.log")" "1"

echo "G2: explicit team=team1 and explicit driver=claude match the same base line"
build_home g2
PAYLOAD='{"case_id":"CASE-20260915-AAAAAA","branch":"case-20260915-aaaaaa","title":"t","context":"c","requirements":"r","complexity":"simple","attempt":1,"team":"team1","driver":"claude"}'
run
assert_eq "G2 base result unchanged" "$(base_matches "$NO_COMMIT_GOLDEN")" "yes"
PAYLOAD="$TEAM1_PAYLOAD"

echo "G3: claude that commits — success line matches master"
build_home g3
run CLAUDE_STUB_MODE=commit
assert_eq "G3 base result unchanged" "$(base_matches "$SUCCESS_GOLDEN")" "yes"
assert_eq "G3 driver status success" "$(j 'print(d["driver_result"]["status"])')" "success"

echo "G4: is_error path matches master (no verify key, exit_code 0, tokens 7)"
build_home g4
run CLAUDE_STUB_MODE=err
assert_eq "G4 base result unchanged" "$(base_matches "$ERROR_GOLDEN")" "yes"
assert_eq "G4 no verify key" "$(j 'print("verify" in d)')" "False"
assert_eq "G4 driver error_class task" "$(j 'print(d["driver_result"]["error_class"])')" "task"

echo "G5: cache_read/cache_creation are subsets; back-compat tokens stay 15"
build_home g5
run CLAUDE_STUB_MODE=cache
assert_eq "G5 base result unchanged (cache not added to the int)" "$(base_matches "$NO_COMMIT_GOLDEN")" "yes"
assert_eq "G5 token split" \
  "$(j 't=d["driver_result"]["tokens"]; print(t["input"], t["cached_input"], t["cache_write_input"], t["output"], t["total"])')" \
  "110 40 60 5 115"

echo "G6: tool denial is still prepended to the no-commits errors string"
build_home g6
run CLAUDE_STUB_MODE=denied
assert_eq "G6 names the denial" "$(j 'print("TOOL DENIED BY THE RUNNER PERMISSION POLICY" in d["errors"])')" "True"
assert_eq "G6 still says no commits" "$(j 'print("No commits produced" in d["errors"])')" "True"
assert_eq "G6 tokens unchanged" "$(j 'print(d["tokens"])')" "15"

echo "G7: complexity=complex still selects opus (verbatim model choice)"
build_home g7
PAYLOAD='{"case_id":"CASE-20260915-AAAAAA","branch":"case-20260915-aaaaaa","title":"t","context":"c","requirements":"r","complexity":"complex","attempt":1}'
run
assert_eq "G7 opus" "$(grep -x 'claude-opus-4-8' "$TMP/state/claude.argv" >/dev/null && echo yes || echo no)" "yes"
PAYLOAD="$TEAM1_PAYLOAD"

echo "G8: empty result (error_max_turns) keeps input+output — master parse-bug fix"
build_home g8
run CLAUDE_STUB_MODE=empty
assert_eq "G8 tokens are input plus output" "$(j 'print(d["tokens"])')" "15"
assert_eq "G8 error text is not the shifted input count" "$(j 'print(d["errors"])')" "Claude CLI error: "
assert_eq "G8 driver token split" \
  "$(j 't=d["driver_result"]["tokens"]; print(t["input"], t["output"], t["total"])')" "10 5 15"
assert_eq "G8 one JSON line" "$(wc -l < "$STDOUT_FILE" | tr -d ' ')" "1"

# Differential against master's tab-split parser. Master fails all five.
# nonjson0 / trunc: master errors are "Claude CLI error: 0", tokens 0,
#   because the empty fallback field collapsed. We keep the empty result,
#   so the error text is "Claude CLI error: " and tokens stay 0. Both fail.
# emptycommit: master fails before the commit counts, with
#   "Claude CLI error: 10" and tokens 5. We fail the same way with
#   "Claude CLI error: " and tokens 15. The commit must not become success.
# empty: master surfaces "Claude CLI error: 10" (tokens 5), not
#   "No commits produced". We surface "Claude CLI error: " (tokens 15).
# r429text0: master surfaces "Claude CLI error: 0". A delimiter mismatch
#   used to fall through to "No commits produced" or a success. We surface
#   the CLI error and class 429 as infra.
cli_fail() {
  j 'print(d["status"]=="failed" and d["summary"]=="Agent run failed" and d["exit_code"]==0 and d["errors"].startswith("Claude CLI error:") and "No commits produced" not in d["errors"] and "verify" not in d)'
}
echo "X1: nonjson0 fails as on master (CLI error, not success)"
build_home x-nonjson
run CLAUDE_STUB_MODE=nonjson0
assert_eq "X1 nonjson0 failed" "$(cli_fail)" "True"
assert_eq "X1 nonjson0 tokens 0" "$(j 'print(d["tokens"])')" "0"
assert_eq "X1 nonjson0 empty result kept" "$(j 'print(d["errors"])')" "Claude CLI error: "
assert_eq "X1 nonjson0 error_class task" "$(j 'print(d["driver_result"]["error_class"])')" "task"

echo "X2: emptycommit fails as on master (the commit does not make it a success)"
build_home x-emptycommit
run CLAUDE_STUB_MODE=emptycommit
assert_eq "X2 emptycommit failed" "$(cli_fail)" "True"
assert_eq "X2 emptycommit tokens are input plus output" "$(j 'print(d["tokens"])')" "15"
assert_eq "X2 emptycommit surfaces the CLI error" "$(j 'print(d["errors"])')" "Claude CLI error: "

echo "X3: trunc fails as on master"
build_home x-trunc
run CLAUDE_STUB_MODE=trunc
assert_eq "X3 trunc failed" "$(cli_fail)" "True"
assert_eq "X3 trunc tokens 0" "$(j 'print(d["tokens"])')" "0"
assert_eq "X3 trunc empty result kept" "$(j 'print(d["errors"])')" "Claude CLI error: "

echo "X4: empty surfaces the CLI error, not 'No commits produced'"
build_home x-empty
run CLAUDE_STUB_MODE=empty
assert_eq "X4 empty is a CLI error" "$(cli_fail)" "True"
assert_eq "X4 empty tokens are input plus output" "$(j 'print(d["tokens"])')" "15"
assert_eq "X4 empty error text" "$(j 'print(d["errors"])')" "Claude CLI error: "

echo "X5: r429text0 surfaces the CLI error as infra, not 'No commits produced'"
build_home x-429
run CLAUDE_STUB_MODE=r429text0
assert_eq "X5 r429text0 is a CLI error" "$(cli_fail)" "True"
assert_eq "X5 r429text0 tokens 0" "$(j 'print(d["tokens"])')" "0"
assert_eq "X5 r429text0 error_class infra" "$(j 'print(d["driver_result"]["error_class"])')" "infra"

echo "X6: credit exhaustion is infra, not task"
build_home x-credit
run CLAUDE_STUB_MODE=credit
assert_eq "X6 credit is a CLI error" "$(cli_fail)" "True"
assert_eq "X6 credit text kept" "$(j 'print("credit balance" in d["errors"])')" "True"
assert_eq "X6 credit error_class infra" "$(j 'print(d["driver_result"]["error_class"])')" "infra"

echo "H1: host label mismatch refuses before any repo access"
build_home h1
LABEL="$FAKEHOME/label.json"
printf '%s\n' '{"team":"team5"}' > "$LABEL"
HEAD_BEFORE="$(agents_head)"
run ORCH_HOST_LABEL_FILE="$LABEL"
assert_eq "H1 infra" "$(j 'print(d["status"]=="failed" and d["errors"].startswith("error_class=infra host label mismatch"))')" "True"
assert_eq "H1 claude never ran" "$(claude_ran)" "no"
assert_eq "H1 agents HEAD unchanged" "$(agents_head)" "$HEAD_BEFORE"
assert_eq "H1 platform HEAD unchanged" "$(git -C "$FAKEHOME/grotap-platform" rev-parse HEAD)" "$PLATFORM_HEAD"
assert_eq "H1 no worktree" "$([[ -d "$FAKEHOME/worktrees/CASE-20260915-AAAAAA" ]] && echo yes || echo no)" "no"
assert_eq "H1 error_class on the result" "$(j 'print(d["driver_result"]["error_class"])')" "infra"

echo "H2: empty payload.team on a team5 host is a mismatch (team1 default)"
build_home h2
printf '%s\n' '{"team":"team5"}' > "$FAKEHOME/label.json"
HEAD_BEFORE="$(agents_head)"
run ORCH_HOST_LABEL_FILE="$FAKEHOME/label.json"
assert_eq "H2 refused" "$(j 'print(d["errors"].startswith("error_class=infra"))')" "True"
assert_eq "H2 HEAD unchanged" "$(agents_head)" "$HEAD_BEFORE"

echo "H3: missing label warns and proceeds; ORCH_REQUIRE_HOST_LABEL=1 refuses"
build_home h3
run ORCH_HOST_LABEL_FILE="$FAKEHOME/no-such-label.json"
assert_eq "H3 proceeded" "$(claude_ran)" "yes"
assert_eq "H3 warned" "$(grep -c 'host label missing' "$FAKEHOME/logs/orchestrator-run.log")" "2"
build_home h3b
HEAD_BEFORE="$(agents_head)"
run ORCH_HOST_LABEL_FILE="$FAKEHOME/no-such-label.json" ORCH_REQUIRE_HOST_LABEL=1
assert_eq "H3b refused" "$(j 'print(d["errors"].startswith("error_class=infra host label required"))')" "True"
assert_eq "H3b claude never ran" "$(claude_ran)" "no"
assert_eq "H3b HEAD unchanged" "$(agents_head)" "$HEAD_BEFORE"

echo "H4: a team1 label matches a historical payload"
build_home h4
printf '%s\n' '{"team":"team1"}' > "$FAKEHOME/label.json"
run ORCH_HOST_LABEL_FILE="$FAKEHOME/label.json"
assert_eq "H4 base result unchanged" "$(base_matches "$NO_COMMIT_GOLDEN")" "yes"

echo "D1: team2 without a driver is infra and does not touch the repo"
build_home d1
PAYLOAD='{"case_id":"CASE-20260915-AAAAAA","branch":"case-20260915-aaaaaa","title":"t","context":"c","requirements":"r","complexity":"simple","attempt":1,"team":"team2"}'
HEAD_BEFORE="$(agents_head)"
run
assert_eq "D1 driver required" "$(j 'print("driver required" in d["errors"] and d["errors"].startswith("error_class=infra"))')" "True"
assert_eq "D1 claude never ran" "$(claude_ran)" "no"
assert_eq "D1 HEAD unchanged" "$(agents_head)" "$HEAD_BEFORE"
PAYLOAD="$TEAM1_PAYLOAD"

echo "D2: unknown driver name is infra"
build_home d2
PAYLOAD='{"case_id":"CASE-20260915-AAAAAA","branch":"case-20260915-aaaaaa","title":"t","context":"c","requirements":"r","complexity":"simple","attempt":1,"driver":"nope"}'
HEAD_BEFORE="$(agents_head)"
run
assert_eq "D2 unknown" "$(j 'print(d["errors"].startswith("error_class=infra unknown driver"))')" "True"
assert_eq "D2 claude never ran" "$(claude_ran)" "no"
assert_eq "D2 HEAD unchanged" "$(agents_head)" "$HEAD_BEFORE"
PAYLOAD='{"case_id":"CASE-20260915-AAAAAA","branch":"case-20260915-aaaaaa","title":"t","context":"c","requirements":"r","complexity":"simple","attempt":1,"driver":"../../tmp"}'
run
assert_eq "D2 path traversal rejected" "$(j 'print(d["errors"].startswith("error_class=infra unknown driver"))')" "True"
PAYLOAD="$TEAM1_PAYLOAD"

echo "D3: an explicit non-claude driver is dispatched with no tool branch"
build_home d3
FAKE_DRIVER="$SCRIPT_DIR/../scripts/drivers/run-costprobe.sh"
cat > "$FAKE_DRIVER" <<'EOF'
#!/bin/bash
python3 - "$3" <<'PY'
import json, sys
json.dump({
  "schema": "driver-result/v1",
  "team": "team2", "driver": "costprobe", "driver_version": "0",
  "tool_bin": "/bin/true", "provider": "openrouter", "model": "x", "profile": None,
  "status": "success", "error_class": None, "summary": "priced nothing", "errors": "",
  "tokens": {"input": 1, "cached_input": 0, "cache_write_input": 0, "output": 1, "reasoning": 0, "total": 2},
  "cost": {"usd": None, "source": "unknown", "price_table_version": None, "long_context_multiplier_applied": False},
  "attempts_inside_driver": 1, "session_id": None, "started_at": "t", "ended_at": "t",
}, open(sys.argv[1], "w"))
PY
exit 0
EOF
chmod +x "$FAKE_DRIVER"
PAYLOAD='{"case_id":"CASE-20260915-AAAAAA","branch":"case-20260915-aaaaaa","title":"t","context":"c","requirements":"r","complexity":"simple","attempt":1,"team":"team2","driver":"costprobe"}'
run
assert_eq "D3 claude was not the tool" "$(claude_ran)" "no"
assert_eq "D3 unknown cost fails closed" \
  "$(j 'print(d["status"]=="failed" and d["errors"].startswith("error_class=cost_unknown") and d["driver_result"]["error_class"]=="cost_unknown")')" "True"
rm -f "$FAKE_DRIVER"; FAKE_DRIVER=""
PAYLOAD="$TEAM1_PAYLOAD"

echo "D5: a malformed driver result still emits one valid JSON line"
build_home d5
FAKE_DRIVER="$SCRIPT_DIR/../scripts/drivers/run-badjson.sh"
cat > "$FAKE_DRIVER" <<'EOF'
#!/bin/bash
printf '%s\n' 'this is not json {' > "$3"
exit 0
EOF
chmod +x "$FAKE_DRIVER"
PAYLOAD='{"case_id":"CASE-20260915-AAAAAA","branch":"case-20260915-aaaaaa","title":"t","context":"c","requirements":"r","complexity":"simple","attempt":1,"team":"team2","driver":"badjson"}'
run
assert_eq "D5 one JSON line" "$(wc -l < "$STDOUT_FILE" | tr -d ' ')" "1"
assert_eq "D5 parses and is an infra failure" \
  "$(j 'print(d["status"]=="failed" and d["errors"].startswith("error_class=infra") and "malformed" in d["errors"] and d["driver_result"]["status"]=="failed" and d["driver_result"]["error_class"]=="infra")')" "True"
rm -f "$FAKE_DRIVER"; FAKE_DRIVER=""
PAYLOAD="$TEAM1_PAYLOAD"

echo "M1: a refused merge (host label mismatch) is non-zero with merged:false"
build_home m1
printf '%s\n' '{"team":"team5"}' > "$FAKEHOME/label.json"
ORIGIN_BEFORE="$(git -C "$FAKEHOME/platform-origin.git" rev-parse master)"
AGENTS_BEFORE="$(agents_head)"
PAYLOAD="$TEAM1_PAYLOAD"
run_merge ORCH_HOST_LABEL_FILE="$FAKEHOME/label.json"
assert_eq "M1 exit non-zero" "$([[ "$RUN_RC" -ne 0 ]] && echo yes || echo no)" "yes"
assert_eq "M1 merged false" \
  "$(j 'print(d.get("merged") is False and "status" not in d and "host label mismatch" in d.get("error",""))')" "True"
assert_eq "M1 one JSON line" "$(wc -l < "$STDOUT_FILE" | tr -d ' ')" "1"
assert_eq "M1 origin untouched" "$(git -C "$FAKEHOME/platform-origin.git" rev-parse master)" "$ORIGIN_BEFORE"
assert_eq "M1 agents HEAD unchanged" "$(agents_head)" "$AGENTS_BEFORE"
assert_eq "M1 claude never ran" "$(claude_ran)" "no"

echo "M2: invalid JSON in merge mode is non-zero with merged:false"
build_home m2
ORIGIN_BEFORE="$(git -C "$FAKEHOME/platform-origin.git" rev-parse master)"
PAYLOAD='not-json'
run_merge
assert_eq "M2 exit non-zero" "$([[ "$RUN_RC" -ne 0 ]] && echo yes || echo no)" "yes"
assert_eq "M2 merged false" \
  "$(j 'print(d.get("merged") is False and "not valid JSON" in d.get("error",""))')" "True"
assert_eq "M2 one JSON line" "$(wc -l < "$STDOUT_FILE" | tr -d ' ')" "1"
assert_eq "M2 origin untouched" "$(git -C "$FAKEHOME/platform-origin.git" rev-parse master)" "$ORIGIN_BEFORE"
PAYLOAD="$TEAM1_PAYLOAD"

echo "D4: team2 with driver=claude still reaches claude (wrapper does not special-case the tool)"
build_home d4
PAYLOAD='{"case_id":"CASE-20260915-AAAAAA","branch":"case-20260915-aaaaaa","title":"t","context":"c","requirements":"r","complexity":"simple","attempt":1,"team":"team2","driver":"claude"}'
run
assert_eq "D4 claude ran" "$(claude_ran)" "yes"
assert_eq "D4 not an unknown-driver infra error" "$(j 'print("unknown driver" in d["errors"])')" "False"
PAYLOAD="$TEAM1_PAYLOAD"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
