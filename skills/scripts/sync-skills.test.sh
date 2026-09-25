#!/usr/bin/env bash
# Dry-run and temp-dir checks for sync-skills.sh. Does not touch a real home.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$ROOT/scripts/sync-skills.sh"
LIB="$ROOT/library"
fail=0

assert() {
  local name="$1" cond="$2"
  if eval "$cond"; then
    printf 'ok %s\n' "$name"
  else
    printf 'FAIL %s\n' "$name" >&2
    fail=1
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

checkout="$tmp/grotap-agents"
mkdir -p "$checkout/agents" "$checkout/skills/library"
printf 'x\n' > "$checkout/agents/GLOBAL.md"
set +e
out="$(bash "$SYNC" --mode symlink --home "$checkout" --dry-run 2>&1)"
code=$?
set -e
assert "refuse --home grotap checkout" "[[ $code -eq 2 && '$out' == *'via --home'* ]]"
set +e
out="$(bash "$SYNC" --mode symlink --repo "$checkout" --dry-run 2>&1)"
code=$?
set -e
assert "refuse --repo grotap checkout" "[[ $code -eq 2 && '$out' == *'via --repo'* ]]"

# Real directory must not become perf/perf.
nest="$tmp/nest-repo"
mkdir -p "$nest/.claude/skills/perf"
printf 'keep\n' > "$nest/.claude/skills/perf/marker"
set +e
out="$(bash "$SYNC" --mode symlink --repo "$nest" --dry-run 2>"$tmp/nest.err")"
code=$?
set -e
assert "dry-run symlink skip exits 0" "[[ $code -eq 0 ]]"
assert "dry-run warns instead of nesting" "grep -q 'real directory' '$tmp/nest.err'"
assert "dry-run does not nest" "[[ ! -e '$nest/.claude/skills/perf/perf' && ! -L '$nest/.claude/skills/perf/perf' ]]"
assert "dry-run keeps marker" "[[ \$(cat '$nest/.claude/skills/perf/marker') == keep ]]"

bash "$SYNC" --mode symlink --repo "$nest" >"$tmp/nest-install.out" 2>"$tmp/nest-install.err"
assert "install skips real perf" "grep -q 'skip .*/perf ' '$tmp/nest-install.err'"
assert "install does not nest" "[[ ! -e '$nest/.claude/skills/perf/perf' && ! -L '$nest/.claude/skills/perf/perf' ]]"
assert "marker survives skip" "[[ \$(cat '$nest/.claude/skills/perf/marker') == keep ]]"

bash "$SYNC" --mode symlink --repo "$nest" --force >"$tmp/force.out" 2>"$tmp/force.err"
assert "force backs up" "grep -q 'backed up ' '$tmp/force.out'"
assert "force result is a symlink" "[[ -L '$nest/.claude/skills/perf' ]]"
assert "force did not nest" "[[ ! -e '$nest/.claude/skills/perf/perf' ]]"
bak="$(find "$nest/.claude/skills" -maxdepth 1 -type d -name 'perf.bak.*' | head -n 1)"
assert "backup has marker" "[[ -n '$bak' && \$(cat '$bak/marker') == keep ]]"

# Second symlink run relinks without nesting.
bash "$SYNC" --mode symlink --repo "$nest" >"$tmp/relink.out" 2>"$tmp/relink.err"
assert "relink stays a symlink" "[[ -L '$nest/.claude/skills/perf' ]]"
assert "relink does not nest" "[[ ! -L '$nest/.claude/skills/perf/perf' && ! -d '$nest/.claude/skills/perf/perf' ]]"

# Copy mode into a real home skill root requires --force.
fake_home="$tmp/home"
export HOME="$fake_home"
unset CODEX_HOME || true
mkdir -p "$fake_home/.claude/skills/perf"
printf 'home-keep\n' > "$fake_home/.claude/skills/perf/marker"
safe_repo="$tmp/copy-repo"
mkdir -p "$safe_repo"
set +e
bash "$SYNC" --mode copy --home "$fake_home" >"$tmp/copy.out" 2>"$tmp/copy.err"
code=$?
set -e
assert "copy without force exits 0" "[[ $code -eq 0 ]]"
assert "copy without force warns" "grep -q 'home skill root' '$tmp/copy.err'"
assert "copy without force keeps marker" "[[ \$(cat '$fake_home/.claude/skills/perf/marker') == home-keep ]]"

bash "$SYNC" --mode copy --home "$fake_home" --force >"$tmp/copy-force.out" 2>"$tmp/copy-force.err"
assert "copy force backs up" "grep -q 'backed up ' '$tmp/copy-force.out'"
assert "copy force writes library skill" "[[ -f '$fake_home/.claude/skills/perf/SKILL.md' ]]"
assert "copy force is not a symlink" "[[ ! -L '$fake_home/.claude/skills/perf' ]]"
home_bak="$(find "$fake_home/.claude/skills" -maxdepth 1 -type d -name 'perf.bak.*' | head -n 1)"
assert "copy backup has marker" "[[ -n '$home_bak' && \$(cat '$home_bak/marker') == home-keep ]]"

# Copy into a non-home repo still replaces a real directory without --force.
plain="$tmp/plain-repo"
mkdir -p "$plain/.agents/skills/perf"
printf 'plain\n' > "$plain/.agents/skills/perf/marker"
env HOME="$tmp/unrelated-home" bash "$SYNC" --mode copy --repo "$plain" >"$tmp/plain.out" 2>"$tmp/plain.err"
assert "non-home copy replaces" "[[ -f '$plain/.agents/skills/perf/SKILL.md' && ! -e '$plain/.agents/skills/perf/marker' ]]"
assert "library file matches source" "cmp -s '$LIB/perf/SKILL.md' '$plain/.agents/skills/perf/SKILL.md'"

if [[ "$fail" -ne 0 ]]; then
  printf 'sync-skills tests failed\n' >&2
  exit 1
fi
printf 'sync-skills tests passed\n'
