#!/usr/bin/env bash
# Install skills/library into the skill roots Claude Code and codex-cli 0.157 scan.
# Does not deploy. Does not touch bootstrap.
#
# Refuses a grotap-agents checkout (agents/GLOBAL.md next to skills/library),
# including when --repo or --home is a subdirectory of that checkout.
#
# A real skill directory is left in place unless --force is set, in both
# symlink and copy mode, and under every --repo and --home root. Symlink mode
# would otherwise nest the link (perf/perf). Copy mode would otherwise delete
# it. An identical copy is skipped, with no backup and no rewrite.
#
# --force moves the old directory outside every scanned skill root:
#   ${XDG_STATE_HOME:-$HOME/.local/state}/grotap-skills/backup/<run>/<root-label>/<name>
# <run> is unique per invocation. Only the last 5 runs are kept.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/library"
MODE="symlink"
REPO=""
HOME_DEST=""
DRY=0
FORCE=0
BACKUP_KEEP=5
RUN_BACKUP_DIR=""

usage() {
  cat <<'EOF'
usage: sync-skills.sh --mode copy|symlink [--repo DIR] [--home DIR] [--force] [--dry-run]

  --repo DIR   project roots: DIR/.claude/skills and DIR/.agents/skills
  --home DIR   user roots: HOME/.claude/skills, HOME/.agents/skills, HOME/.codex/skills
  --force      back up a differing real skill directory and replace it
  --dry-run    print actions only

Pass --repo, --home, or both. Refuses a grotap-agents checkout (a directory
that contains agents/GLOBAL.md next to skills/library), including when the
path is a subdirectory of that checkout.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --home) HOME_DEST="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$MODE" != "copy" && "$MODE" != "symlink" ]]; then
  echo "mode must be copy or symlink" >&2
  exit 2
fi
if [[ -z "$REPO" && -z "$HOME_DEST" ]]; then
  usage
  exit 2
fi
if [[ ! -d "$LIB" ]]; then
  echo "missing library: $LIB" >&2
  exit 2
fi

is_agents_checkout() {
  local dir="$1"
  [[ -f "$dir/agents/GLOBAL.md" && -d "$dir/skills/library" ]]
}

# Print the checkout root if dir is that checkout or a directory inside it.
checkout_containing() {
  local dir="$1"
  while [[ ! -d "$dir" ]]; do
    dir="$(dirname "$dir")"
    [[ "$dir" == "/" ]] && break
  done
  if [[ -d "$dir" ]]; then
    dir="$(cd "$dir" && pwd -P)"
  fi
  while [[ "$dir" != "/" ]]; do
    if is_agents_checkout "$dir"; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

refuse_agents_checkout() {
  local dir="$1" label="$2" found
  if found="$(checkout_containing "$dir")"; then
    echo "refusing to install into the grotap-agents checkout via --${label}: $dir (checkout $found)" >&2
    exit 2
  fi
}

state_parent() {
  if [[ -n "${XDG_STATE_HOME:-}" ]]; then
    printf '%s/grotap-skills/backup\n' "$XDG_STATE_HOME"
    return 0
  fi
  if [[ -z "${HOME:-}" ]]; then
    echo "HOME is unset; set HOME or XDG_STATE_HOME so backups stay outside skill roots" >&2
    exit 2
  fi
  printf '%s/.local/state/grotap-skills/backup\n' "$HOME"
}

prune_backups() {
  local parent="$1" keep="$2" n=0 path
  [[ -d "$parent" ]] || return 0
  n=0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    n=$((n + 1))
    if [[ "$n" -gt "$keep" ]]; then
      rm -rf "$path"
    fi
  done < <(find "$parent" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | cut -d' ' -f2-)
}

ensure_run_backup_dir() {
  local parent
  if [[ -n "$RUN_BACKUP_DIR" ]]; then
    return 0
  fi
  parent="$(state_parent)"
  mkdir -p "$parent"
  RUN_BACKUP_DIR="$(mktemp -d "${parent}/$(date -u +%Y%m%dT%H%M%SZ)-$$-XXXXXX")"
  prune_backups "$parent" "$BACKUP_KEEP"
}

backup_move() {
  local dest="$1" label="$2" name="$3" bak
  ensure_run_backup_dir
  mkdir -p "$RUN_BACKUP_DIR/$label"
  bak="$RUN_BACKUP_DIR/$label/$name"
  mv "$dest" "$bak"
  printf '%s\n' "$bak"
}

prepare_target() {
  local kind="$1" path="$2"
  refuse_agents_checkout "$path" "$kind"
  if [[ ! -d "$path" ]]; then
    if [[ "$DRY" -eq 0 ]]; then
      mkdir -p "$path"
    fi
  fi
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd)
  else
    printf '%s\n' "$path"
  fi
}

if [[ -n "$REPO" ]]; then
  REPO="$(prepare_target repo "$REPO")"
fi
if [[ -n "$HOME_DEST" ]]; then
  HOME_DEST="$(prepare_target home "$HOME_DEST")"
fi

install_one() {
  local dest_root="$1" name="$2" src="$3" label="$4" dest bak
  dest="$dest_root/$name"

  if [[ "$MODE" == "copy" && -e "$dest" ]] && diff -rq "$src" "$dest" >/dev/null 2>&1; then
    printf 'skip %s (already identical to source)\n' "$dest"
    return 0
  fi

  if [[ -d "$dest" && ! -L "$dest" ]]; then
    if [[ "$FORCE" -ne 1 ]]; then
      if [[ "$MODE" == "symlink" ]]; then
        printf 'warning: skip %s (real directory; a symlink would be created inside it). Pass --force to back it up and replace.\n' "$dest" >&2
      else
        printf 'warning: skip %s (real skill directory differs from the library). Pass --force to back it up and replace.\n' "$dest" >&2
      fi
      return 0
    fi
    printf 'warning: replacing real skill directory %s\n' "$dest" >&2
    if [[ "$DRY" -eq 1 ]]; then
      printf 'would back up %s outside scanned skill roots (%s)\n' "$dest" "$label"
    else
      bak="$(backup_move "$dest" "$label" "$name")"
      printf 'backed up %s -> %s\n' "$dest" "$bak"
    fi
  fi

  if [[ "$DRY" -eq 1 ]]; then
    printf 'would install %s -> %s (%s)\n' "$src" "$dest" "$MODE"
    return 0
  fi
  mkdir -p "$dest_root"
  if [[ "$MODE" == "symlink" ]]; then
    ln -sfn "$src" "$dest"
  else
    rm -rf "$dest"
    cp -a "$src" "$dest"
  fi
  printf 'installed %s (%s)\n' "$dest" "$MODE"
}

mapfile -t NAMES < <(find "$LIB" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
if [[ "${#NAMES[@]}" -eq 0 ]]; then
  echo "no skills in $LIB" >&2
  exit 2
fi

for name in "${NAMES[@]}"; do
  src="$LIB/$name"
  if [[ ! -f "$src/SKILL.md" ]]; then
    echo "skip $name (no SKILL.md)" >&2
    continue
  fi
  if [[ -n "$REPO" ]]; then
    install_one "$REPO/.claude/skills" "$name" "$src" "repo-claude"
    install_one "$REPO/.agents/skills" "$name" "$src" "repo-agents"
  fi
  if [[ -n "$HOME_DEST" ]]; then
    install_one "$HOME_DEST/.claude/skills" "$name" "$src" "home-claude"
    install_one "$HOME_DEST/.agents/skills" "$name" "$src" "home-agents"
    install_one "$HOME_DEST/.codex/skills" "$name" "$src" "home-codex"
  fi
done
