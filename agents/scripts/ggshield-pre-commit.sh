#!/bin/bash
# pre-commit hook for seat repos. Installed at ~/.config/grotap/git-hooks/pre-commit.
# Git runs this because core.hooksPath points at that directory.
#
# The GitGuardian API key is read from Doppler grotap/prd at runtime and exported
# only into this process. It is not written to disk, not placed on a command
# line, and not logged. `env VAR=value` is intentionally not used: that form
# puts the value in argv.
#
# After a scan that allows the commit (pass, or fail-open), this execs the
# repo's own .git/hooks/pre-commit when that file exists and is executable.
# core.hooksPath hides that file from git, which is how `pre-commit install`
# in a repo such as grotap-platform would otherwise stop running.

# Drop inherited xtrace before any secret is assigned. A parent shell that
# exported SHELLOPTS=xtrace would otherwise print the key on stderr.
# Children are started with `env -u SHELLOPTS` so a bash stub or wrapper
# cannot turn xtrace back on and expand GITGUARDIAN_API_KEY. `env -u` does
# not put the key on argv.
set +x
set -uo pipefail

_hook_dir="$(unset CDPATH; cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_hook_dir}/ggshield-lib.sh"

# git's hook cwd is the work tree. rev-parse --git-dir is the repo git dir,
# not core.hooksPath, so this is the hook `pre-commit install` wrote.
ggshield_chain_repo_hook() {
  local git_dir repo_hook
  git_dir="$(git rev-parse --git-dir 2>/dev/null)" || return 0
  repo_hook="${git_dir}/hooks/pre-commit"
  if [[ -f "$repo_hook" && -x "$repo_hook" ]]; then
    unset GITGUARDIAN_API_KEY
    exec "$repo_hook" "$@"
  fi
}

ggshield_repo_path() {
  local repo
  repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$repo" ]]; then
    repo="$(git rev-parse --git-dir 2>/dev/null || true)"
  fi
  if [[ -z "$repo" ]]; then
    repo="unknown"
  fi
  printf '%s\n' "$repo"
}

# Scan could not run or did not return a verdict.
# on: record a fail-open line and allow the commit.
# strict: block. The fail-open log is not written, because the commit did not proceed.
ggshield_on_scan_failure() {
  local reason="$1" scan_exit="$2" message="$3"
  shift 3
  unset GITGUARDIAN_API_KEY
  if [[ "${_mode}" == "strict" ]]; then
    echo "ggshield hook: ${message}; commit blocked" >&2
    exit 1
  fi
  ggshield_record_failopen "$reason" "$scan_exit" "$(ggshield_repo_path)"
  echo "ggshield hook warning: ${message}; allowing commit" >&2
  ggshield_chain_repo_hook "$@"
  exit 0
}

_mode="$(ggshield_effective_mode)"
if [[ "$_mode" != "on" && "$_mode" != "strict" ]]; then
  echo "ggshield hook disabled" >&2
  ggshield_chain_repo_hook "$@"
  exit 0
fi

if [[ -n "${GROTAP_GGSHIELD_BIN:-}" ]]; then
  _gg_bin="${GROTAP_GGSHIELD_BIN}"
elif [[ -x "$(ggshield_venv_dir)/bin/ggshield" ]]; then
  _gg_bin="$(ggshield_venv_dir)/bin/ggshield"
elif command -v ggshield >/dev/null 2>&1; then
  _gg_bin="$(command -v ggshield)"
else
  ggshield_on_scan_failure "ggshield-missing" "-" "ggshield is not installed" "$@"
fi

# Discard any key inherited from the parent. The scan uses Doppler only.
unset GITGUARDIAN_API_KEY

_doppler_bin="$(command -v doppler || true)"
if [[ -z "$_doppler_bin" ]]; then
  ggshield_on_scan_failure "doppler-missing" "-" \
    "could not read GITGUARDIAN_API_KEY from Doppler" "$@"
fi

set +x
_gg_rc=0
_gg_key="$(env -u SHELLOPTS "$_doppler_bin" secrets get GITGUARDIAN_API_KEY --project grotap --config prd --plain 2>/dev/null)" || _gg_rc=$?
if [[ "$_gg_rc" -ne 0 || -z "${_gg_key}" ]]; then
  unset _gg_key
  if [[ "$_gg_rc" -ne 0 ]]; then
    ggshield_on_scan_failure "doppler-error" "-" \
      "could not read GITGUARDIAN_API_KEY from Doppler" "$@"
  fi
  ggshield_on_scan_failure "empty-key" "-" \
    "could not read GITGUARDIAN_API_KEY from Doppler" "$@"
fi
GITGUARDIAN_API_KEY="$_gg_key"
export GITGUARDIAN_API_KEY
unset _gg_key

# Exit 1 is secrets found (fail closed). Every other non-zero status is an
# API, auth, or network failure. Mode on fails open and records it. Mode
# strict fails closed. Do not pass --no-fail-on-server-error: that turns a
# server failure into exit 0 and this hook would not log a warning.
# Do not pass --show-secrets.
_scan_rc=0
if command -v timeout >/dev/null 2>&1; then
  timeout --signal=TERM 45 env -u SHELLOPTS "$_gg_bin" secret scan pre-commit || _scan_rc=$?
else
  env -u SHELLOPTS "$_gg_bin" secret scan pre-commit || _scan_rc=$?
fi
unset GITGUARDIAN_API_KEY

_reason="scan-error"
if [[ "$_scan_rc" -eq 124 ]]; then
  _reason="timeout"
fi

case "$_scan_rc" in
  0)
    ggshield_chain_repo_hook "$@"
    exit 0
    ;;
  1)
    echo "ggshield hook: secret detected; commit blocked" >&2
    exit 1
    ;;
  *)
    ggshield_on_scan_failure "$_reason" "$_scan_rc" \
      "GitGuardian API or network error (exit ${_scan_rc})" "$@"
    ;;
esac
