#!/bin/bash
# pre-commit hook for seat repos. Installed at ~/.config/grotap/git-hooks/pre-commit.
# Git runs this because core.hooksPath points at that directory.
#
# The GitGuardian API key is read from Doppler grotap/prd at runtime and exported
# only into this process. It is not written to disk, not placed on a command
# line, and not logged. `env VAR=value` is intentionally not used: that form
# puts the value in argv.

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

_mode="$(ggshield_effective_mode)"
if [[ "$_mode" != "on" ]]; then
  echo "ggshield hook disabled" >&2
  exit 0
fi

if [[ -n "${GROTAP_GGSHIELD_BIN:-}" ]]; then
  _gg_bin="${GROTAP_GGSHIELD_BIN}"
elif [[ -x "$(ggshield_venv_dir)/bin/ggshield" ]]; then
  _gg_bin="$(ggshield_venv_dir)/bin/ggshield"
elif command -v ggshield >/dev/null 2>&1; then
  _gg_bin="$(command -v ggshield)"
else
  echo "ggshield hook warning: ggshield is not installed; allowing commit" >&2
  exit 0
fi

# Discard any key inherited from the parent. The scan uses Doppler only.
unset GITGUARDIAN_API_KEY

_doppler_bin="$(command -v doppler || true)"
if [[ -z "$_doppler_bin" ]]; then
  echo "ggshield hook warning: could not read GITGUARDIAN_API_KEY from Doppler; allowing commit" >&2
  exit 0
fi

set +x
_gg_rc=0
_gg_key="$(env -u SHELLOPTS "$_doppler_bin" secrets get GITGUARDIAN_API_KEY --project grotap --config prd --plain 2>/dev/null)" || _gg_rc=$?
if [[ "$_gg_rc" -ne 0 || -z "${_gg_key}" ]]; then
  unset _gg_key
  echo "ggshield hook warning: could not read GITGUARDIAN_API_KEY from Doppler; allowing commit" >&2
  exit 0
fi
GITGUARDIAN_API_KEY="$_gg_key"
export GITGUARDIAN_API_KEY
unset _gg_key

# Exit 1 is secrets found (fail closed). Every other non-zero status is an
# API, auth, or network failure (fail open). Do not pass --no-fail-on-server-error:
# that turns a server failure into exit 0 and this hook would not log a warning.
# Do not pass --show-secrets.
_scan_rc=0
if command -v timeout >/dev/null 2>&1; then
  timeout --signal=TERM 45 env -u SHELLOPTS "$_gg_bin" secret scan pre-commit || _scan_rc=$?
else
  env -u SHELLOPTS "$_gg_bin" secret scan pre-commit || _scan_rc=$?
fi

case "$_scan_rc" in
  0)
    exit 0
    ;;
  1)
    echo "ggshield hook: secret detected; commit blocked" >&2
    exit 1
    ;;
  *)
    echo "ggshield hook warning: GitGuardian API or network error (exit ${_scan_rc}); allowing commit" >&2
    exit 0
    ;;
esac
