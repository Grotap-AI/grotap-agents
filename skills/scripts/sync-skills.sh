#!/usr/bin/env bash
# Install skills/library into the skill roots Claude Code and codex-cli 0.157 scan.
# Does not deploy. Does not touch bootstrap. Refuses this grotap-agents checkout.
# Idempotent: symlink mode relinks; copy mode replaces the destination skill dir.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/library"
MODE="symlink"
REPO=""
HOME_DEST=""
DRY=0

usage() {
  cat <<'EOF'
usage: sync-skills.sh --mode copy|symlink [--repo DIR] [--home DIR] [--dry-run]

  --repo DIR   project roots: DIR/.claude/skills and DIR/.agents/skills
  --home DIR   user roots: HOME/.claude/skills, HOME/.agents/skills, HOME/.codex/skills
  --dry-run    print actions only

Pass --repo, --home, or both. Refuses a repo that contains agents/GLOBAL.md
next to skills/library (this checkout).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --home) HOME_DEST="${2:-}"; shift 2 ;;
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

if [[ -n "$REPO" ]]; then
  REPO="$(cd "$REPO" && pwd)"
  if [[ -f "$REPO/agents/GLOBAL.md" && -d "$REPO/skills/library" ]]; then
    echo "refusing to install into the grotap-agents checkout" >&2
    exit 2
  fi
fi

install_one() {
  local dest_root="$1" name="$2" src="$3" dest
  dest="$dest_root/$name"
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
