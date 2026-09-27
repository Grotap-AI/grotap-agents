#!/bin/bash
# On the canary seat, prove the pre-commit hook blocks GitGuardian's
# documented test token and allows a clean file. Prints PASS or FAIL.
#
# The token is the GitGuardian Test Token Checked pattern (ggtt-v- plus 10
# lowercase letters or digits). It is not a live credential. The pieces are
# assembled at runtime so this file does not itself contain a match.
#
# https://docs.gitguardian.com/secrets-detection/secrets-detection-engine/detectors/specifics/gitguardian_test_token_checked

set -uo pipefail

script_dir="$(unset CDPATH; cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/ggshield-lib.sh"

fail() {
  echo "ggshield canary: $1" >&2
  printf '%s\n' FAIL
  exit 1
}

if ! ggshield_is_canary_seat; then
  fail "this seat is not the canary (${GGSHIELD_CANARY_USER} on ${GGSHIELD_CANARY_HOST}; this seat is $(ggshield_seat_user)@$(ggshield_seat_host))"
fi

if [[ "$(ggshield_effective_mode)" != "on" ]]; then
  fail "hook is not enabled on this seat"
fi

hooks="$(git config --global --get core.hooksPath || true)"
if [[ "$hooks" != "$(ggshield_hooks_dir)" || ! -x "${hooks}/pre-commit" ]]; then
  fail "pre-commit hook is not installed"
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

repo="${tmpdir}/repo"
git init -q -b master "$repo"
git -C "$repo" config user.email "ggshield-canary@grotap.local"
git -C "$repo" config user.name "ggshield-canary"

# GitGuardian Test Token Checked, validity status "valid". Not a real secret.
kind="v"
body="canary0001"
token="ggtt-${kind}-${body}"

printf 'token=%s\n' "$token" >"${repo}/secret.txt"
git -C "$repo" add -- secret.txt
secret_rc=0
git -C "$repo" commit -q -m "canary secret" >/dev/null 2>"${tmpdir}/secret.err" || secret_rc=$?
if [[ "$secret_rc" -eq 0 ]]; then
  cat "${tmpdir}/secret.err" >&2
  fail "secret commit was not blocked"
fi

git -C "$repo" rm -q --cached --ignore-unmatch -- secret.txt
rm -f "${repo}/secret.txt"
printf '%s\n' "clean file for ggshield canary" >"${repo}/clean.txt"
git -C "$repo" add -- clean.txt
clean_rc=0
git -C "$repo" commit -q -m "canary clean" >/dev/null 2>"${tmpdir}/clean.err" || clean_rc=$?
if [[ "$clean_rc" -ne 0 ]]; then
  cat "${tmpdir}/clean.err" >&2
  fail "clean commit was blocked"
fi

printf '%s\n' PASS
exit 0
