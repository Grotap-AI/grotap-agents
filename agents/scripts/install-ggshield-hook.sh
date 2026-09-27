#!/bin/bash
# Install the ggshield pre-commit hook for one seat user.
#
# Seats:
#   agent-21-shared: claude, astra
#   agent-22-shared: codex, grok, monitor
#
# The hook is off after a plain install. --canary turns it on only for
# the codex user on agent-22-shared.
#
# Run as the seat user, or as root with --user SEAT.
# Do not run this on forge-01 or maps-01.

set -euo pipefail

script_dir="$(unset CDPATH; cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${script_dir}/ggshield-lib.sh"

usage() {
  cat <<'EOF'
Usage: install-ggshield-hook.sh [--user USER] [--canary | --disable | --uninstall] [--purge]

Installs pinned ggshield into ~/.local/share/grotap/ggshield-venv and sets
git config --global core.hooksPath to ~/.config/grotap/git-hooks so every
repo that seat commits in runs the hook. Plain install leaves the hook off
(it logs "ggshield hook disabled" and exits 0).

  --user USER   seat to install (root only; re-execs as that user)
  --canary      install and enable the hook (codex on agent-22-shared only)
  --disable     install if needed and set the hook off
  --uninstall   remove the hook and unset core.hooksPath when it is ours
  --purge       with --uninstall, also remove the venv
EOF
}

target_user=""
action="install"
purge=0
mode_flags=0
forward=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      if [[ $# -lt 2 ]]; then
        echo "install-ggshield-hook: --user needs a name" >&2
        exit 2
      fi
      target_user="$2"
      shift 2
      ;;
    --canary)
      action="canary"
      mode_flags=$((mode_flags + 1))
      forward+=("--canary")
      shift
      ;;
    --disable)
      action="disable"
      mode_flags=$((mode_flags + 1))
      forward+=("--disable")
      shift
      ;;
    --uninstall)
      action="uninstall"
      mode_flags=$((mode_flags + 1))
      forward+=("--uninstall")
      shift
      ;;
    --purge)
      purge=1
      forward+=("--purge")
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "install-ggshield-hook: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$mode_flags" -gt 1 ]]; then
  echo "install-ggshield-hook: pass only one of --canary, --disable, --uninstall" >&2
  exit 2
fi

if [[ -n "$target_user" ]]; then
  if [[ ! "$target_user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo "install-ggshield-hook: refusing user name" >&2
    exit 2
  fi
  current_user="$(id -un)"
  if [[ "$current_user" != "$target_user" ]]; then
    if [[ "$current_user" != "root" ]]; then
      echo "install-ggshield-hook: --user requires root" >&2
      exit 1
    fi
    exec sudo -u "$target_user" -H -- bash "$0" "${forward[@]}"
  fi
fi

if [[ "$(id -un)" == "root" ]]; then
  echo "install-ggshield-hook: refusing to install as root; pass --user SEAT" >&2
  exit 1
fi

if [[ "$action" == "canary" ]] && ! ggshield_is_canary_seat; then
  echo "install-ggshield-hook: --canary is only for ${GGSHIELD_CANARY_USER} on ${GGSHIELD_CANARY_HOST} (this seat is $(ggshield_seat_user)@$(ggshield_seat_host))" >&2
  exit 1
fi

uninstall_hook() {
  local hooks current
  hooks="$(ggshield_hooks_dir)"
  current="$(git config --global --get core.hooksPath || true)"
  if [[ "$current" == "$hooks" ]]; then
    git config --global --unset core.hooksPath
  fi
  rm -rf "$hooks"
  rm -f "$(ggshield_mode_file)"
  if [[ "$purge" -eq 1 ]]; then
    rm -rf "$(ggshield_venv_dir)"
  fi
  echo "install-ggshield-hook: removed hook for $(id -un)" >&2
}

install_ggshield() {
  local venv req have
  if [[ "${GROTAP_GGSHIELD_SKIP_PIP:-}" == "1" ]]; then
    echo "install-ggshield-hook: skipping ggshield package install" >&2
    return 0
  fi
  venv="$(ggshield_venv_dir)"
  req="${script_dir}/ggshield-requirements.txt"
  if [[ ! -f "$req" ]]; then
    echo "install-ggshield-hook: missing ${req}" >&2
    exit 1
  fi
  have=""
  if [[ -x "${venv}/bin/ggshield" ]]; then
    have="$("${venv}/bin/ggshield" --version 2>/dev/null || true)"
  fi
  if [[ "$have" == "ggshield, version ${GGSHIELD_VERSION}" ]]; then
    echo "install-ggshield-hook: ggshield ${GGSHIELD_VERSION} already installed" >&2
    return 0
  fi
  mkdir -p "$(dirname "$venv")"
  if ! python3 -m venv "$venv"; then
    echo "install-ggshield-hook: python3 -m venv failed. On this host, as root: apt-get install -y python3-venv" >&2
    exit 1
  fi
  "${venv}/bin/pip" install --disable-pip-version-check --require-hashes -r "$req"
  have="$("${venv}/bin/ggshield" --version 2>/dev/null || true)"
  if [[ "$have" != "ggshield, version ${GGSHIELD_VERSION}" ]]; then
    echo "install-ggshield-hook: expected ggshield ${GGSHIELD_VERSION}, got: ${have}" >&2
    exit 1
  fi
  echo "install-ggshield-hook: installed ggshield ${GGSHIELD_VERSION}" >&2
}

install_hooks() {
  local hooks current
  hooks="$(ggshield_hooks_dir)"
  current="$(git config --global --get core.hooksPath || true)"
  if [[ -n "$current" && "$current" != "$hooks" ]]; then
    echo "install-ggshield-hook: core.hooksPath is already ${current}; refusing to replace it" >&2
    exit 1
  fi
  mkdir -p "$hooks"
  cp "${script_dir}/ggshield-lib.sh" "${hooks}/ggshield-lib.sh"
  cp "${script_dir}/ggshield-pre-commit.sh" "${hooks}/pre-commit"
  chmod 644 "${hooks}/ggshield-lib.sh"
  chmod 755 "${hooks}/pre-commit"
  git config --global core.hooksPath "$hooks"
}

write_mode() {
  local path value dir tmp
  path="$(ggshield_mode_file)"
  dir="$(dirname "$path")"
  mkdir -p "$dir"
  case "$action" in
    canary) value="on" ;;
    disable) value="off" ;;
    *)
      if [[ -f "$path" ]]; then
        return 0
      fi
      value="off"
      ;;
  esac
  tmp="$(mktemp "${dir}/.mode.XXXXXX")"
  printf '%s\n' "$value" >"$tmp"
  chmod 644 "$tmp"
  mv -f "$tmp" "$path"
}

if [[ "$action" == "uninstall" ]]; then
  uninstall_hook
  exit 0
fi

install_ggshield
install_hooks
write_mode
echo "install-ggshield-hook: user=$(id -un) mode=$(ggshield_file_mode) hooks=$(ggshield_hooks_dir)" >&2
