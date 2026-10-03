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
# Display name for messages (first entry). Used by install-ggshield-hook.sh
# and ggshield-canary.sh.
# shellcheck disable=SC2034
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

# Per-user fail-open record. Mode 0600. Never written with a secret.
ggshield_failopen_log() {
  printf '%s\n' "${HOME}/.local/state/grotap/ggshield-failopen.log"
}

# One line: timestamp, user, reason, ggshield exit, repo.
# reason and ggshield_exit are fixed tokens. repo is a path. The API key
# is not an argument and is not read from the environment.
ggshield_record_failopen() {
  local reason="$1" scan_exit="$2" repo="$3"
  local log dir ts user line
  reason="${reason//$'\n'/}"
  reason="${reason//$'\r'/}"
  scan_exit="${scan_exit//$'\n'/}"
  scan_exit="${scan_exit//$'\r'/}"
  repo="${repo//$'\n'/}"
  repo="${repo//$'\r'/}"
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  user="$(ggshield_seat_user)"
  user="${user//$'\n'/}"
  user="${user//$'\r'/}"
  log="$(ggshield_failopen_log)"
  dir="$(dirname -- "$log")"
  line="$(printf '%s user=%s reason=%s ggshield_exit=%s repo=%s' \
    "$ts" "$user" "$reason" "$scan_exit" "$repo")"
  (
    umask 077
    mkdir -p -- "$dir"
    if [[ ! -e "$log" ]]; then
      : >"$log"
    fi
    chmod 0600 "$log"
    printf '%s\n' "$line" >>"$log"
  )
}

# Count records whose UTC timestamp is >= cutoff. A missing file is 0.
ggshield_count_failopens() {
  local file="$1" cutoff="$2"
  if [[ ! -f "$file" ]]; then
    printf '%s\n' 0
    return 0
  fi
  awk -v cutoff="$cutoff" '
    $1 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/ && $1 >= cutoff { n++ }
    END { print n + 0 }
  ' "$file"
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

# Prints on, off, or strict. A missing or unrecognized file is off.
# strict is never the default. Install and --canary do not write it.
ggshield_file_mode() {
  local path line
  path="$(ggshield_mode_file)"
  if [[ ! -f "$path" ]]; then
    printf '%s\n' off
    return 0
  fi
  line="$(tr -d '[:space:]' <"$path" || true)"
  case "$line" in
    on|off|strict) printf '%s\n' "$line" ;;
    *) printf '%s\n' off ;;
  esac
}

# GROTAP_GGSHIELD_HOOK overrides the mode file when it is set.
# Unset means "use the file". on and strict are honored.
# Empty, off, or any other value is off.
ggshield_effective_mode() {
  if [[ -n "${GROTAP_GGSHIELD_HOOK+x}" ]]; then
    case "${GROTAP_GGSHIELD_HOOK}" in
      on|strict) printf '%s\n' "${GROTAP_GGSHIELD_HOOK}" ;;
      *) printf '%s\n' off ;;
    esac
    return 0
  fi
  ggshield_file_mode
}
