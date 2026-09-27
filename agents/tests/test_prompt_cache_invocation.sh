#!/bin/bash
# Real launch paths for claude-prompt-cache.sh.
#
# A stub claude records its own environment. The review-gate path goes through
# `doppler run`, and the stub doppler re-injects DISABLE_PROMPT_CACHING* after
# any unset in the parent shell. The wrapper path sources the helper from the
# workspace copy, which is what claude-remote-wrapper.sh actually loads.
#
# No SSH, no network, no Anthropic API.
# Usage: bash agents/tests/test_prompt_cache_invocation.sh

set -uo pipefail

PASS=0
FAIL=0
TMP=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER="$REPO/agents/scripts/claude-prompt-cache.sh"
GATE="$REPO/agents/scripts/review-gate-cron.sh"
ORCH="$REPO/agents/scripts/orchestrator-run.sh"
WRAPPER="$REPO/scripts/claudecode/claude-remote-wrapper.sh"
trap 'rm -rf "$TMP"' EXIT

assert_eq() {
  local label="$1" got="$2" expected="$3"
  if [[ "$got" == "$expected" ]]; then
    echo "  PASS  $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL  $label (expected='$expected' got='$got')"
    FAIL=$(( FAIL + 1 ))
  fi
}

DISABLE_NAMES=(
  DISABLE_PROMPT_CACHING
  DISABLE_PROMPT_CACHING_SONNET
  DISABLE_PROMPT_CACHING_OPUS
  DISABLE_PROMPT_CACHING_HAIKU
  DISABLE_PROMPT_CACHING_FABLE
  DISABLE_PROMPT_CACHING_FUTURE
  CLAUDE_CODE_DISABLE_PROMPT_CACHING
  CLAUDE_CODE_DISABLE_PROMPT_CACHING_EXTRA
)

assert_recorded_env() {
  local label="$1" envfile="$2" name
  for name in "${DISABLE_NAMES[@]}"; do
    assert_eq "$label $name unset" "$(grep -c "^${name}=<unset>$" "$envfile")" "1"
  done
  assert_eq "$label KEEP_SENTINEL kept" "$(grep -c '^KEEP_SENTINEL=kept$' "$envfile")" "1"
}

# ── helper, sourced and executed ────────────────────────────────────────────
echo "H1: sourcing the helper clears every exported DISABLE_PROMPT_CACHING* name"
h1=$(
  set -u
  export DISABLE_PROMPT_CACHING=1
  export DISABLE_PROMPT_CACHING_SONNET=1
  export DISABLE_PROMPT_CACHING_OPUS=1
  export DISABLE_PROMPT_CACHING_HAIKU=1
  export DISABLE_PROMPT_CACHING_FABLE=1
  export DISABLE_PROMPT_CACHING_FUTURE=1
  export CLAUDE_CODE_DISABLE_PROMPT_CACHING=1
  export CLAUDE_CODE_DISABLE_PROMPT_CACHING_EXTRA=1
  export KEEP_SENTINEL=kept
  # shellcheck source=/dev/null
  . "$HELPER"
  for name in "${DISABLE_NAMES[@]}"; do
    if [ -n "${!name+x}" ]; then
      echo "still-set $name"
      exit 1
    fi
  done
  . "$HELPER"
  if [ "${KEEP_SENTINEL}" != kept ]; then
    echo sentinel-lost
    exit 1
  fi
  echo ok
)
assert_eq "H1 sourced twice under set -u" "$h1" "ok"

echo "H2: executing the helper unsets, then execs its arguments"
h2=$(
  set -u
  export DISABLE_PROMPT_CACHING_HAIKU=from-parent
  export KEEP_SENTINEL=kept
  bash "$HELPER" bash -c 'if [ -n "${DISABLE_PROMPT_CACHING_HAIKU+x}" ]; then echo haiku-set; exit 1; fi; if [ "${KEEP_SENTINEL}" != kept ]; then echo sentinel-lost; exit 1; fi; echo ok'
)
assert_eq "H2 exec path" "$h2" "ok"

echo "H3: launch scripts do not carry their own unset copies"
for path in "$ORCH" "$GATE" "$WRAPPER"; do
  code=$(grep -v '^[[:space:]]*#' "$path" || true)
  if printf '%s\n' "$code" | grep -q 'unset DISABLE_PROMPT_CACHING'; then
    assert_eq "H3 $(basename "$path") has no inline unset" "present" "absent"
  else
    assert_eq "H3 $(basename "$path") has no inline unset" "absent" "absent"
  fi
done
gate_code=$(grep -v '^[[:space:]]*#' "$GATE" || true)
if printf '%s\n' "$gate_code" | grep -q 'bash "$_CACHE_SH"'; then
  assert_eq "H3 review-gate execs the helper" "yes" "yes"
else
  assert_eq "H3 review-gate execs the helper" "no" "yes"
fi
if printf '%s\n' "$gate_code" | grep -q '\. "$_CACHE_SH"'; then
  assert_eq "H3 review-gate does not source the helper in the parent" "sourced" "not-sourced"
else
  assert_eq "H3 review-gate does not source the helper in the parent" "not-sourced" "not-sourced"
fi

# ── shared claude stub ──────────────────────────────────────────────────────
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
cat > "$STUBS/claude" <<'EOF'
#!/bin/bash
mkdir -p "$STATE_DIR"
: > "$STATE_DIR/claude.argv"
for a in "$@"; do printf '%s\n' "$a" >> "$STATE_DIR/claude.argv"; done
{
  for name in \
    DISABLE_PROMPT_CACHING \
    DISABLE_PROMPT_CACHING_SONNET \
    DISABLE_PROMPT_CACHING_OPUS \
    DISABLE_PROMPT_CACHING_HAIKU \
    DISABLE_PROMPT_CACHING_FABLE \
    DISABLE_PROMPT_CACHING_FUTURE \
    CLAUDE_CODE_DISABLE_PROMPT_CACHING \
    CLAUDE_CODE_DISABLE_PROMPT_CACHING_EXTRA \
    KEEP_SENTINEL
  do
    if [ -n "${!name+x}" ]; then
      printf '%s=%s\n' "$name" "${!name}"
    else
      printf '%s=<unset>\n' "$name"
    fi
  done
} > "$STATE_DIR/claude.env"
printf 'stub-ok\n'
exit 0
EOF
chmod +x "$STUBS/claude"

# doppler re-injects the disable switches, then execs the command after `--`.
# A parent unset is therefore not enough: the helper has to run inside this child.
cat > "$STUBS/doppler" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${STATE_DIR}/doppler.argv"
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--" ]]; then
    shift
    break
  fi
  shift
done
if [[ "${1:-}" == "python3" ]]; then
  joined="$*"
  if [[ "$joined" == *"SELECT count"* ]]; then
    printf 'col\n1\n'
  else
    printf 'UPDATE 0\n'
  fi
  exit 0
fi
export DISABLE_PROMPT_CACHING=from-doppler
export DISABLE_PROMPT_CACHING_SONNET=from-doppler
export DISABLE_PROMPT_CACHING_OPUS=from-doppler
export DISABLE_PROMPT_CACHING_HAIKU=from-doppler
export DISABLE_PROMPT_CACHING_FABLE=from-doppler
export DISABLE_PROMPT_CACHING_FUTURE=from-doppler
export CLAUDE_CODE_DISABLE_PROMPT_CACHING=from-doppler
export CLAUDE_CODE_DISABLE_PROMPT_CACHING_EXTRA=from-doppler
export KEEP_SENTINEL=kept
exec "$@"
EOF
chmod +x "$STUBS/doppler"

cat > "$STUBS/grotap-git-lock" <<'EOF'
#!/bin/bash
shift
exec "$@"
EOF
chmod +x "$STUBS/grotap-git-lock"

seed_repo() {
  local origin="$1" work="$2"
  git init --bare "$origin" -q
  printf 'ref: refs/heads/master\n' > "$origin/HEAD"
  git clone "$origin" "$work" -q
  git -C "$work" config user.email t@t.com
  git -C "$work" config user.name T
  echo base > "$work/base.txt"
  git -C "$work" add base.txt
  git -C "$work" commit -q -m base
  git -C "$work" push -u origin master -q
}

echo "G1: review-gate doppler injection is cleared inside the command doppler runs"
GSTATE="$TMP/gate-state"
mkdir -p "$GSTATE"
seed_repo "$TMP/agents-origin.git" "$TMP/agents"
seed_repo "$TMP/platform-origin.git" "$TMP/platform"
printf 'standing task\n' > "$TMP/task.md"
GATE_LOG="$TMP/review-gate.log"
set +e
timeout 60 env \
  PATH="$STUBS:$PATH" \
  STATE_DIR="$GSTATE" \
  AGENTS_REPO="$TMP/agents" \
  PLATFORM_REPO="$TMP/platform" \
  LOCK="$TMP/review-gate.lock" \
  LOG="$GATE_LOG" \
  TASK="$TMP/task.md" \
  DISABLE_PROMPT_CACHING=from-parent \
  DISABLE_PROMPT_CACHING_SONNET=from-parent \
  DISABLE_PROMPT_CACHING_OPUS=from-parent \
  DISABLE_PROMPT_CACHING_HAIKU=from-parent \
  DISABLE_PROMPT_CACHING_FABLE=from-parent \
  DISABLE_PROMPT_CACHING_FUTURE=from-parent \
  CLAUDE_CODE_DISABLE_PROMPT_CACHING=from-parent \
  CLAUDE_CODE_DISABLE_PROMPT_CACHING_EXTRA=from-parent \
  KEEP_SENTINEL=from-parent \
  bash "$GATE"
gate_rc=$?
if [[ "$gate_rc" -ne 0 ]]; then
  echo "  review-gate rc=$gate_rc; log follows" >&2
  tail -n 80 "$GATE_LOG" >&2 || true
  echo "--- doppler argv ---" >&2
  cat "$GSTATE/doppler.argv" >&2 || true
fi
assert_eq "G1 review-gate exit" "$gate_rc" "0"
assert_eq "G1 claude saw -p" "$(grep -qxF -- '-p' "$GSTATE/claude.argv" && echo yes || echo no)" "yes"
assert_recorded_env "G1" "$GSTATE/claude.env"
assert_eq "G1 log records claude exit 0" "$(grep -c 'claude exit: 0' "$GATE_LOG")" "1"

echo "W1: remote-control wrapper clears the switches before claude inherits them"
WSTATE="$TMP/wrap-state"
mkdir -p "$WSTATE"
WHOME="$TMP/wrap-home"
mkdir -p "$WHOME/workspace/grotap/agents/scripts" "$WHOME/workspace/grotap/platform"
ln -s "$HELPER" "$WHOME/workspace/grotap/agents/scripts/claude-prompt-cache.sh"
git init -q "$WHOME/workspace/grotap"
git init -q "$WHOME/workspace/grotap/platform"
set +e
env \
  PATH="$STUBS:$PATH" \
  HOME="$WHOME" \
  STATE_DIR="$WSTATE" \
  CLAUDE_REMOTE_LABEL=testseat \
  RAPID_EXIT_SECS=30 \
  DISABLE_PROMPT_CACHING=from-parent \
  DISABLE_PROMPT_CACHING_SONNET=from-parent \
  DISABLE_PROMPT_CACHING_OPUS=from-parent \
  DISABLE_PROMPT_CACHING_HAIKU=from-parent \
  DISABLE_PROMPT_CACHING_FABLE=from-parent \
  DISABLE_PROMPT_CACHING_FUTURE=from-parent \
  CLAUDE_CODE_DISABLE_PROMPT_CACHING=from-parent \
  CLAUDE_CODE_DISABLE_PROMPT_CACHING_EXTRA=from-parent \
  KEEP_SENTINEL=kept \
  bash "$WRAPPER"
wrap_rc=$?
if [[ "$wrap_rc" -ne 0 ]]; then
  echo "  wrapper rc=$wrap_rc" >&2
  cat "$WHOME/.claude-remote/current.log" >&2 || true
fi
assert_eq "W1 wrapper exit" "$wrap_rc" "0"
assert_eq "W1 claude saw remote-control" "$(grep -qxF -- 'remote-control' "$WSTATE/claude.argv" && echo yes || echo no)" "yes"
assert_recorded_env "W1" "$WSTATE/claude.env"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
