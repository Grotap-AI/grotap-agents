#!/usr/bin/env bash
# Install skills/library into the skill roots Claude Code and codex-cli 0.157 scan.
# Does not deploy. Does not touch bootstrap. Refuses a grotap-agents checkout
# passed as --repo or --home.
#
# Symlink mode relinks an existing symlink. A real directory with the same
# name is left in place unless --force is set, because ln would nest the
# link inside it (perf/perf). Copy mode replaces freely except under the
# real ~/.claude, ~/.agents, or $CODEX_HOME skill roots, which need --force
# and are backed up first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/library"
MODE="symlink"
REPO=""
HOME_DEST=""
DRY=0
FORCE=0

usage() {
  cat <<'EOF'
usage: sync-skills.sh --mode copy|symlink [--repo DIR] [--home DIR] [--force] [--dry-run]

  --repo DIR   project roots: DIR/.claude/skills and DIR/.agents/skills
  --home DIR   user roots: HOME/.claude/skills, HOME/.agents/skills, HOME/.codex/skills
  --force      back up a blocking real skill directory and replace it
  --dry-run    print actions only

Pass --repo, --home, or both. Refuses a directory that contains agents/GLOBAL.md
next to skills/library (this checkout), whether it is passed as --repo or --home.
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

refuse_agents_checkout() {
  local dir="$1" label="$2"
  if is_agents_checkout "$dir"; then
    echo "refusing to install into the grotap-agents checkout via --${label}: $dir" >&2
    exit 2
  fi
}

canon_dir() {
  local p="$1" parent base
  if [[ -d "$p" ]]; then
    (cd "$p" && pwd -P)
    return 0
  fi
  parent="$(dirname "$p")"
  base="$(basename "$p")"
  if [[ -d "$parent" ]]; then
    printf '%s/%s\n' "$(cd "$parent" && pwd -P)" "$base"
  else
    printf '%s\n' "$p"
  fi
}

is_protected_home_root() {
  local root="$1" canon candidate
  [[ -n "${HOME:-}" ]] || return 1
  canon="$(canon_dir "$root")"
  for candidate in \
    "$HOME/.claude/skills" \
    "$HOME/.agents/skills" \
    "$HOME/.codex/skills" \
    "${CODEX_HOME:-$HOME/.codex}/skills"
  do
    if [[ "$canon" == "$(canon_dir "$candidate")" ]]; then
      return 0
    fi
  done
  return 1
}

if [[ -n "$REPO" ]]; then
  REPO="$(cd "$REPO" && pwd)"
  refuse_agents_checkout "$REPO" repo
fi
if [[ -n "$HOME_DEST" ]]; then
  if [[ ! -d "$HOME_DEST" ]]; then
    if [[ "$DRY" -eq 0 ]]; then
      mkdir -p "$HOME_DEST"
    fi
  fi
  if [[ -d "$HOME_DEST" ]]; then
    HOME_DEST="$(cd "$HOME_DEST" && pwd)"
    refuse_agents_checkout "$HOME_DEST" home
  fi
fi

install_one() {
  local dest_root="$1" name="$2" src="$3" dest bak needs_force
  dest="$dest_root/$name"
  needs_force=0
  if [[ -d "$dest" && ! -L "$dest" ]]; then
    if [[ "$MODE" == "symlink" ]]; then
      needs_force=1
    elif is_protected_home_root "$dest_root"; then
      needs_force=1
    fi
  fi

  if [[ "$needs_force" -eq 1 && "$FORCE" -ne 1 ]]; then
    if [[ "$MODE" == "symlink" ]]; then
      printf 'warning: skip %s (real directory; a symlink would be created inside it). Pass --force to back it up and replace.\n' "$dest" >&2
    else
      printf 'warning: skip %s (real skill directory under a home skill root). Pass --force to back it up and replace.\n' "$dest" >&2
    fi
    return 0
  fi

  if [[ "$needs_force" -eq 1 ]]; then
    bak="${dest}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
    printf 'warning: replacing real skill directory %s\n' "$dest" >&2
    if [[ "$DRY" -eq 1 ]]; then
      printf 'would back up %s -> %s\n' "$dest" "$bak"
    else
      mv "$dest" "$bak"
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
    install_one "$REPO/.claude/skills" "$name" "$src"
    install_one "$REPO/.agents/skills" "$name" "$src"
  fi
  if [[ -n "$HOME_DEST" ]]; then
    install_one "$HOME_DEST/.claude/skills" "$name" "$src"
    install_one "$HOME_DEST/.agents/skills" "$name" "$src"
    install_one "$HOME_DEST/.codex/skills" "$name" "$src"
  fi
done
