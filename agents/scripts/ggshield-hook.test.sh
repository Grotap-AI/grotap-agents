#!/bin/bash
# CI tests for the seat ggshield hook. No GitGuardian API key.
# Stubs stand in for doppler and ggshield.
# Run: bash agents/scripts/ggshield-hook.test.sh
set -uo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(unset CDPATH; cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="${SCRIPT_DIR}/install-ggshield-hook.sh"
CANARY="${SCRIPT_DIR}/ggshield-canary.sh"
REQ="${SCRIPT_DIR}/ggshield-requirements.txt"
FAKE_KEY="ci-stub-gitguardian-key"

# Assemble GitGuardian's test token without storing the match in this file.
write_secret() {
  local dest kind body
  dest="$1"
  kind="v"
  body="canary0001"
  printf 'token=%s\n' "ggtt-${kind}-${body}" >"$dest"
}

check() {
  local desc="$1" ok="$2"
  if [[ "$ok" == "true" ]]; then
    PASS=$((PASS + 1))
    printf '  ok   %s\n' "$desc"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL %s\n' "$desc"
  fi
}

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

STUBS="${ROOT}/stubs"
mkdir -p "$STUBS"

cat >"${STUBS}/id" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "-un" ]]; then
  printf '%s\n' "${STUB_ID_USER:?}"
  exit 0
fi
echo "unexpected id args: $*" >&2
exit 1
EOF

cat >"${STUBS}/hostname" <<'EOF'
#!/bin/bash
printf '%s\n' "${STUB_HOSTNAME:?}"
exit 0
EOF

cat >"${STUBS}/doppler" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"${DOPPLER_ARGV_LOG:?}"
if [[ "${STUB_DOPPLER_FAIL:-}" == "1" ]]; then
  echo "doppler stub failed" >&2
  exit 1
fi
if [[ "$*" != "secrets get GITGUARDIAN_API_KEY --project grotap --config prd --plain" ]]; then
  echo "unexpected doppler args" >&2
  exit 1
fi
printf '%s\n' "${STUB_DOPPLER_KEY-}"
exit 0
EOF

cat >"${STUBS}/ggshield" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"${GGSHIELD_ARGV_LOG:?}"
if [[ "$*" == *"${STUB_DOPPLER_KEY-}"* && -n "${STUB_DOPPLER_KEY-}" ]]; then
  echo "key leaked into ggshield argv" >>"${GGSHIELD_ARGV_LOG:?}"
fi
if [[ -n "${GITGUARDIAN_API_KEY:-}" ]]; then
  printf '%s\n' present >>"${GGSHIELD_KEY_STATE:?}"
else
  printf '%s\n' absent >>"${GGSHIELD_KEY_STATE:?}"
fi
if [[ -n "${GGSHIELD_STUB_EXIT:-}" ]]; then
  exit "$GGSHIELD_STUB_EXIT"
fi
if git diff --cached --no-color | grep -F -q 'ggtt-v-'; then
  echo "secret detected by stub" >&2
  exit 1
fi
exit 0
EOF
chmod +x "${STUBS}/id" "${STUBS}/hostname" "${STUBS}/doppler" "${STUBS}/ggshield"

new_home() {
  local name="$1"
  HOME="${ROOT}/homes/${name}"
  rm -rf "$HOME"
  mkdir -p "$HOME/logs"
  export HOME
  export GIT_CONFIG_GLOBAL="${HOME}/.gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  export PATH="${STUBS}:/usr/bin:/bin"
  export STUB_DOPPLER_KEY="$FAKE_KEY"
  export DOPPLER_ARGV_LOG="${HOME}/logs/doppler.argv"
  export GGSHIELD_ARGV_LOG="${HOME}/logs/ggshield.argv"
  export GGSHIELD_KEY_STATE="${HOME}/logs/ggshield.key"
  export GROTAP_GGSHIELD_BIN="${STUBS}/ggshield"
  export GROTAP_GGSHIELD_SKIP_PIP=1
  unset GROTAP_GGSHIELD_HOOK || true
  unset GGSHIELD_STUB_EXIT || true
  unset STUB_DOPPLER_FAIL || true
  : >"$DOPPLER_ARGV_LOG"
  : >"$GGSHIELD_ARGV_LOG"
  : >"$GGSHIELD_KEY_STATE"
  git config --global user.email "hook-test@grotap.local"
  git config --global user.name "hook-test"
  git config --global init.defaultBranch master
}

as_canary() {
  export STUB_ID_USER="codex"
  export STUB_HOSTNAME="agent-22-shared"
}

install_ok() {
  bash "$INSTALLER" "$@" >"${HOME}/logs/install.out" 2>"${HOME}/logs/install.err"
}

key_on_disk() {
  grep -R -I -l -F -- "$FAKE_KEY" "$HOME" 2>/dev/null || true
}

init_repo() {
  local repo="$1"
  git init -q -b master "$repo"
  git -C "$repo" config user.email "hook-test@grotap.local"
  git -C "$repo" config user.name "hook-test"
}

echo "== lock file pins ggshield 1.54.0 with hashes =="
if grep -q '^ggshield==1.54.0' "$REQ" \
  && grep -q -- '--hash=sha256:bde2685bd67c1b766918e9050cb5eff0c1e145629a4fc8d974200d039151266b' "$REQ" \
  && grep -q -- '--require-hashes' "$INSTALLER"; then
  check "requirements pin the manylinux wheel and the installer requires hashes" true
else
  check "requirements pin the manylinux wheel and the installer requires hashes" false
fi
assembled="$(printf '%s%s%s' 'ggtt-' 'v-' 'canary0001')"
if grep -q -F -- "$assembled" "$CANARY" "$INSTALLER" "${SCRIPT_DIR}/ggshield-pre-commit.sh" "${SCRIPT_DIR}/ggshield-lib.sh"; then
  check "sources do not contain the assembled test token" false
else
  check "sources do not contain the assembled test token" true
fi
if grep -q 'env GITGUARDIAN_API_KEY' "${SCRIPT_DIR}/ggshield-pre-commit.sh" \
  || grep -q 'ggshield auth' "${SCRIPT_DIR}/ggshield-pre-commit.sh"; then
  check "hook does not put the key on a command line" false
else
  check "hook does not put the key on a command line" true
fi

echo "== plain install is off and does not replace a foreign hooksPath =="
new_home plain
as_canary
if install_ok; then
  check "plain install exits 0" true
else
  check "plain install exits 0" false
fi
mode="$(tr -d '[:space:]' <"${HOME}/.config/grotap/ggshield-hook.mode")"
if [[ "$mode" == "off" ]]; then
  check "mode file is off" true
else
  check "mode file is off (saw ${mode})" false
fi
hooks="$(git config --global --get core.hooksPath || true)"
if [[ "$hooks" == "${HOME}/.config/grotap/git-hooks" && -x "${hooks}/pre-commit" ]]; then
  check "core.hooksPath points at an executable pre-commit" true
else
  check "core.hooksPath points at an executable pre-commit (saw ${hooks})" false
fi

new_home foreign
as_canary
git config --global core.hooksPath /tmp/not-our-hooks
rc=0
install_ok || rc=$?
current="$(git config --global --get core.hooksPath || true)"
if [[ "$rc" -ne 0 && "$current" == "/tmp/not-our-hooks" ]]; then
  check "foreign core.hooksPath is left alone" true
else
  check "foreign core.hooksPath is left alone (rc=${rc} path=${current})" false
fi

echo "== disabled hook is a no-op =="
new_home disabled
as_canary
install_ok
repo="${HOME}/repo"
init_repo "$repo"
write_secret "${repo}/secret.txt"
git -C "$repo" add -- secret.txt
rc=0
git -C "$repo" commit -q -m "should pass while disabled" >/dev/null 2>"${HOME}/logs/commit.err" || rc=$?
err="$(cat "${HOME}/logs/commit.err")"
if [[ "$rc" -eq 0 && "$err" == *"ggshield hook disabled"* && ! -s "$DOPPLER_ARGV_LOG" && ! -s "$GGSHIELD_ARGV_LOG" ]]; then
  check "off hook logs ggshield hook disabled and does not call doppler" true
else
  check "off hook logs ggshield hook disabled and does not call doppler (rc=${rc} err=${err})" false
fi

echo "== --canary is one seat only =="
new_home wrong-user
export STUB_ID_USER="grok"
export STUB_HOSTNAME="agent-22-shared"
rc=0
install_ok --canary || rc=$?
if [[ "$rc" -ne 0 && ! -f "${HOME}/.config/grotap/ggshield-hook.mode" ]]; then
  check "canary refused for grok and does not write the mode file" true
else
  check "canary refused for grok and does not write the mode file (rc=${rc})" false
fi

new_home wrong-host
export STUB_ID_USER="codex"
export STUB_HOSTNAME="agent-21-shared"
rc=0
install_ok --canary || rc=$?
if [[ "$rc" -ne 0 && ! -f "${HOME}/.config/grotap/ggshield-hook.mode" ]]; then
  check "canary refused on agent-21-shared" true
else
  check "canary refused on agent-21-shared (rc=${rc})" false
fi

new_home not-root
as_canary
rc=0
install_ok --user grok || rc=$?
if [[ "$rc" -ne 0 ]]; then
  check "--user from a non-root caller fails" true
else
  check "--user from a non-root caller fails" false
fi

echo "== canary seat blocks the test token and allows a clean file =="
new_home canary
as_canary
install_ok --canary
mode="$(tr -d '[:space:]' <"${HOME}/.config/grotap/ggshield-hook.mode")"
if [[ "$mode" == "on" ]]; then
  check "--canary writes on for codex@agent-22-shared" true
else
  check "--canary writes on for codex@agent-22-shared (saw ${mode})" false
fi
install_ok
mode="$(tr -d '[:space:]' <"${HOME}/.config/grotap/ggshield-hook.mode")"
if [[ "$mode" == "on" ]]; then
  check "reinstall does not turn the canary off" true
else
  check "reinstall does not turn the canary off (saw ${mode})" false
fi
: >"$DOPPLER_ARGV_LOG"
: >"$GGSHIELD_ARGV_LOG"
: >"$GGSHIELD_KEY_STATE"
canary_out="${HOME}/logs/canary.out"
canary_err="${HOME}/logs/canary.err"
rc=0
bash "$CANARY" >"$canary_out" 2>"$canary_err" || rc=$?
out="$(tr -d '[:space:]' <"$canary_out")"
if [[ "$rc" -eq 0 && "$out" == "PASS" ]]; then
  check "canary prints PASS" true
else
  check "canary prints PASS (rc=${rc} out=${out} err=$(cat "$canary_err"))" false
fi
argv_bad=0
while IFS= read -r line; do
  if [[ "$line" != "secrets get GITGUARDIAN_API_KEY --project grotap --config prd --plain" ]]; then
    argv_bad=1
  fi
done <"$DOPPLER_ARGV_LOG"
if [[ "$argv_bad" -eq 0 && -s "$DOPPLER_ARGV_LOG" ]]; then
  check "doppler is called with project grotap config prd and no key in argv" true
else
  check "doppler is called with project grotap config prd and no key in argv" false
fi
if grep -q '^present$' "$GGSHIELD_KEY_STATE" && ! grep -q '^absent$' "$GGSHIELD_KEY_STATE"; then
  check "ggshield receives the key in the environment" true
else
  check "ggshield receives the key in the environment" false
fi
leaks="$(key_on_disk)"
if [[ -z "$leaks" ]]; then
  check "API key is not written under HOME" true
else
  check "API key is not written under HOME (${leaks})" false
fi

echo "== xtrace does not print the key =="
new_home xtrace
as_canary
install_ok --canary
repo="${HOME}/repo"
init_repo "$repo"
write_secret "${repo}/secret.txt"
git -C "$repo" add -- secret.txt
rc=0
env SHELLOPTS=xtrace git -C "$repo" commit -q -m "traced" >/dev/null 2>"${HOME}/logs/trace.err" || rc=$?
trace="$(cat "${HOME}/logs/trace.err")"
if [[ "$rc" -ne 0 && "$trace" != *"$FAKE_KEY"* && "$trace" != *"GITGUARDIAN_API_KEY="* && "$trace" == *"secret detected"* ]]; then
  check "xtrace blocks the secret without printing the API key" true
else
  check "xtrace blocks the secret without printing the API key (rc=${rc})" false
fi
leaks="$(key_on_disk)"
if [[ -z "$leaks" ]]; then
  check "xtrace run does not leave the API key on disk" true
else
  check "xtrace run does not leave the API key on disk (${leaks})" false
fi

echo "== API and network errors fail open; secrets stay fail closed =="
new_home doppler-down
as_canary
install_ok --canary
export STUB_DOPPLER_FAIL=1
repo="${HOME}/repo"
init_repo "$repo"
printf '%s\n' "clean" >"${repo}/clean.txt"
git -C "$repo" add -- clean.txt
rc=0
git -C "$repo" commit -q -m "doppler down" >/dev/null 2>"${HOME}/logs/commit.err" || rc=$?
err="$(cat "${HOME}/logs/commit.err")"
if [[ "$rc" -eq 0 && "$err" == *"could not read GITGUARDIAN_API_KEY from Doppler"* && ! -s "$GGSHIELD_ARGV_LOG" ]]; then
  check "doppler failure allows the commit and does not run ggshield" true
else
  check "doppler failure allows the commit and does not run ggshield (rc=${rc} err=${err})" false
fi

new_home empty-key
as_canary
install_ok --canary
export STUB_DOPPLER_KEY=""
repo="${HOME}/repo"
init_repo "$repo"
printf '%s\n' "clean" >"${repo}/clean.txt"
git -C "$repo" add -- clean.txt
rc=0
git -C "$repo" commit -q -m "empty key" >/dev/null 2>"${HOME}/logs/commit.err" || rc=$?
err="$(cat "${HOME}/logs/commit.err")"
if [[ "$rc" -eq 0 && "$err" == *"could not read GITGUARDIAN_API_KEY from Doppler"* ]]; then
  check "empty Doppler value allows the commit" true
else
  check "empty Doppler value allows the commit (rc=${rc} err=${err})" false
fi

new_home network
as_canary
install_ok --canary
export STUB_DOPPLER_KEY="$FAKE_KEY"
export GGSHIELD_STUB_EXIT=4
repo="${HOME}/repo"
init_repo "$repo"
printf '%s\n' "clean" >"${repo}/clean.txt"
git -C "$repo" add -- clean.txt
rc=0
git -C "$repo" commit -q -m "api down" >/dev/null 2>"${HOME}/logs/commit.err" || rc=$?
err="$(cat "${HOME}/logs/commit.err")"
if [[ "$rc" -eq 0 && "$err" == *"GitGuardian API or network error (exit 4); allowing commit"* ]]; then
  check "ggshield exit 4 allows the commit and logs a warning" true
else
  check "ggshield exit 4 allows the commit and logs a warning (rc=${rc} err=${err})" false
fi
if grep -q '^present$' "$GGSHIELD_KEY_STATE"; then
  check "network failure still passed the key only via the environment" true
else
  check "network failure still passed the key only via the environment" false
fi

new_home secrets
as_canary
install_ok --canary
unset GGSHIELD_STUB_EXIT || true
export STUB_DOPPLER_KEY="$FAKE_KEY"
repo="${HOME}/repo"
init_repo "$repo"
write_secret "${repo}/secret.txt"
git -C "$repo" add -- secret.txt
rc=0
git -C "$repo" commit -q -m "secret" >/dev/null 2>"${HOME}/logs/commit.err" || rc=$?
err="$(cat "${HOME}/logs/commit.err")"
if [[ "$rc" -ne 0 && "$err" == *"secret detected; commit blocked"* ]]; then
  check "detected secret blocks the commit" true
else
  check "detected secret blocks the commit (rc=${rc} err=${err})" false
fi

echo "== env off overrides the canary file, and --disable / --uninstall roll back =="
new_home env-off
as_canary
install_ok --canary
export GROTAP_GGSHIELD_HOOK=off
repo="${HOME}/repo"
init_repo "$repo"
write_secret "${repo}/secret.txt"
git -C "$repo" add -- secret.txt
rc=0
git -C "$repo" commit -q -m "env off" >/dev/null 2>"${HOME}/logs/commit.err" || rc=$?
err="$(cat "${HOME}/logs/commit.err")"
if [[ "$rc" -eq 0 && "$err" == *"ggshield hook disabled"* ]]; then
  check "GROTAP_GGSHIELD_HOOK=off is a no-op even when the file says on" true
else
  check "GROTAP_GGSHIELD_HOOK=off is a no-op even when the file says on (rc=${rc} err=${err})" false
fi
unset GROTAP_GGSHIELD_HOOK || true

new_home rollback
as_canary
install_ok --canary
install_ok --disable
mode="$(tr -d '[:space:]' <"${HOME}/.config/grotap/ggshield-hook.mode")"
if [[ "$mode" == "off" ]]; then
  check "--disable sets the mode file off" true
else
  check "--disable sets the mode file off (saw ${mode})" false
fi
install_ok --uninstall
hooks="$(git config --global --get core.hooksPath || true)"
if [[ -z "$hooks" && ! -e "${HOME}/.config/grotap/git-hooks" && ! -e "${HOME}/.config/grotap/ggshield-hook.mode" ]]; then
  check "--uninstall removes the hook and core.hooksPath" true
else
  check "--uninstall removes the hook and core.hooksPath (hooks=${hooks})" false
fi

new_home keep-foreign
as_canary
git config --global core.hooksPath /tmp/not-our-hooks
install_ok --uninstall
current="$(git config --global --get core.hooksPath || true)"
if [[ "$current" == "/tmp/not-our-hooks" ]]; then
  check "--uninstall does not unset a foreign core.hooksPath" true
else
  check "--uninstall does not unset a foreign core.hooksPath (saw ${current})" false
fi

new_home canary-off
as_canary
install_ok
rc=0
bash "$CANARY" >"${HOME}/logs/canary.out" 2>"${HOME}/logs/canary.err" || rc=$?
out="$(tr -d '[:space:]' <"${HOME}/logs/canary.out")"
if [[ "$rc" -ne 0 && "$out" == "FAIL" ]]; then
  check "canary FAILs when the hook is off" true
else
  check "canary FAILs when the hook is off (rc=${rc} out=${out})" false
fi

echo "== canary host rename (agent-22-shared -> team-codex-grok-monitor-01) =="
new_home renamed-canary
export STUB_ID_USER="codex"
export STUB_HOSTNAME="team-codex-grok-monitor-01"
rc=0
install_ok --canary || rc=$?
if [[ "$rc" -eq 0 && "$(tr -d '[:space:]' <"${HOME}/.config/grotap/ggshield-hook.mode" 2>/dev/null)" == "on" ]]; then
  check "--canary accepted for codex@team-codex-grok-monitor-01" true
else
  check "--canary accepted for codex@team-codex-grok-monitor-01 (rc=${rc})" false
fi

new_home renamed-wrong-host
export STUB_ID_USER="codex"
export STUB_HOSTNAME="team-claude-01"
rc=0
install_ok --canary || rc=$?
if [[ "$rc" -ne 0 && ! -f "${HOME}/.config/grotap/ggshield-hook.mode" ]]; then
  check "canary refused on team-claude-01" true
else
  check "canary refused on team-claude-01 (rc=${rc})" false
fi

new_home canary-override
export STUB_ID_USER="codex"
export STUB_HOSTNAME="agent-22-shared"
rc=0
GROTAP_GGSHIELD_CANARY_HOST="some-future-name" install_ok --canary || rc=$?
if [[ "$rc" -ne 0 && ! -f "${HOME}/.config/grotap/ggshield-hook.mode" ]]; then
  check "GROTAP_GGSHIELD_CANARY_HOST replaces the host list" true
else
  check "GROTAP_GGSHIELD_CANARY_HOST replaces the host list (rc=${rc})" false
fi
export STUB_HOSTNAME="some-future-name"
rc=0
GROTAP_GGSHIELD_CANARY_HOST="some-future-name" install_ok --canary || rc=$?
if [[ "$rc" -eq 0 ]]; then
  check "GROTAP_GGSHIELD_CANARY_HOST host is accepted" true
else
  check "GROTAP_GGSHIELD_CANARY_HOST host is accepted (rc=${rc})" false
fi

echo
printf 'passed=%s failed=%s\n' "$PASS" "$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
exit 0
