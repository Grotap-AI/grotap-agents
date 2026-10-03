#!/bin/bash
# Shared paths for the seat ggshield pre-commit hook.
# Source this file. Do not execute it.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "ggshield-lib.sh: source this file; do not execute it" >&2
  exit 1
fi

# Pinned in agents/scripts/ggshield-requirements.txt.
# Used by install-ggshield-hook.sh.
# shellcheck disable=SC2034
GGSHIELD_VERSION="1.54.0"

# Canary is one seat: the codex user on the shared codex/grok/monitor box.
# That box was renamed agent-22-shared -> team-codex-grok-monitor-01 on
# 2026-10-02; both hostnames are the same seat. GROTAP_GGSHIELD_CANARY_HOST
# replaces the list with one host (e.g. for a later rename).
GGSHIELD_CANARY_USER="codex"
if [[ -n "${GROTAP_GGSHIELD_CANARY_HOST:-}" ]]; then
  GGSHIELD_CANARY_HOSTS=("${GROTAP_GGSHIELD_CANARY_HOST}")
else
  GGSHIELD_CANARY_HOSTS=("team-codex-grok-monitor-01" "agent-22-shared")
fi
# Display name for messages (first entry).
GGSHIELD_CANARY_HOST="${GGSHIELD_CANARY_HOSTS[0]}"

ggshield_mode_file() {
  printf '%s\n' "${HOME}/.config/grotap/ggshield-hook.mode"
}

ggshield_hooks_dir() {
  printf '%s\n' "${HOME}/.config/grotap/git-hooks"
}

ggshield_venv_dir() {
  printf '%s\n' "${HOME}/.local/share/grotap/ggshield-venv"
}

ggshield_seat_user() {
  id -un
}

ggshield_seat_host() {
  hostname -s 2>/dev/null || hostname
}

ggshield_is_canary_seat() {
  local user host
  user="$(ggshield_seat_user)"
  host="$(ggshield_seat_host)"
  [[ "$user" == "$GGSHIELD_CANARY_USER" ]] || return 1
  local h
  for h in "${GGSHIELD_CANARY_HOSTS[@]}"; do
    [[ "$host" == "$h" ]] && return 0
  done
  return 1
}

# Prints on or off. A missing or unrecognized file is off.
ggshield_file_mode() {
  local path line
  path="$(ggshield_mode_file)"
  if [[ ! -f "$path" ]]; then
    printf '%s\n' off
    return 0
  fi
  line="$(tr -d '[:space:]' <"$path" || true)"
  case "$line" in
    on|off) printf '%s\n' "$line" ;;
    *) printf '%s\n' off ;;
  esac
}

# GROTAP_GGSHIELD_HOOK overrides the mode file when it is set.
# Unset means "use the file". Empty, off, or any value other than on is off.
ggshield_effective_mode() {
  if [[ -n "${GROTAP_GGSHIELD_HOOK+x}" ]]; then
    case "${GROTAP_GGSHIELD_HOOK}" in
      on) printf '%s\n' on ;;
      *) printf '%s\n' off ;;
    esac
    return 0
  fi
  ggshield_file_mode
}
