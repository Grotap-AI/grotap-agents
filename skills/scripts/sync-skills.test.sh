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

export HOME="$tmp/invoker-home"
export XDG_STATE_HOME="$tmp/state"
unset CODEX_HOME || true
mkdir -p "$HOME" "$XDG_STATE_HOME"

backup_root() {
  printf '%s/grotap-skills/backup\n' "$XDG_STATE_HOME"
}

run_dirs() {
  local root
  root="$(backup_root)"
  if [[ ! -d "$root" ]]; then
    return 0
  fi
  find "$root" -mindepth 1 -maxdepth 1 -type d | sort
}

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

missing="$checkout/agents/new-home"
set +e
out="$(bash "$SYNC" --mode symlink --home "$missing" --dry-run 2>&1)"
code=$?
set -e
assert "refuse --home subdirectory of checkout" "[[ $code -eq 2 && '$out' == *'via --home'* && '$out' == *'checkout '* ]]"
assert "dry-run subdirectory does not create a directory" "[[ ! -e '$missing' ]]"
set +e
out="$(bash "$SYNC" --mode copy --repo "$checkout/skills" 2>&1)"
code=$?
set -e
assert "refuse --repo subdirectory of checkout" "[[ $code -eq 2 && '$out' == *'via --repo'* ]]"
assert "subdirectory refusal creates no skill root" "[[ ! -d '$checkout/skills/.claude' && ! -d '$checkout/skills/.agents' ]]"

# Real directory must not become perf/perf.
nest="$tmp/nest-repo"
mkdir -p "$nest/.claude/skills/perf"
printf 'keep\n' > "$nest/.claude/skills/perf/marker"
printf '%s\n' '---' 'name: perf' 'description: "stale"' '---' 'old' > "$nest/.claude/skills/perf/SKILL.md"
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
assert "skip creates no backup run" "[[ -z \"\$(run_dirs)\" ]]"

bash "$SYNC" --mode symlink --repo "$nest" --force >"$tmp/force.out" 2>"$tmp/force.err"
assert "force backs up" "grep -q 'backed up ' '$tmp/force.out'"
assert "force result is a symlink" "[[ -L '$nest/.claude/skills/perf' ]]"
assert "force did not nest" "[[ ! -e '$nest/.claude/skills/perf/perf' ]]"
bak="$(sed -n 's/^backed up .* -> //p' "$tmp/force.out" | head -n 1)"
assert "backup has marker" "[[ -n '$bak' && \$(cat '$bak/marker') == keep ]]"
assert "backup is under the state dir" "[[ '$bak' == '$XDG_STATE_HOME/grotap-skills/backup/'* ]]"
assert "backup is not inside a scanned skill root" "[[ '$bak' != *'/.claude/skills/'* && '$bak' != *'/.agents/skills/'* && '$bak' != *'/.codex/skills/'* ]]"
assert "scanned roots have no real backup directory" "[[ -z \"\$(find '$nest/.claude/skills' '$nest/.agents/skills' -mindepth 1 -maxdepth 1 \\( -name '*.bak.*' -o -type d \\) -print)\" ]]"
assert "library skills are the only entries" "[[ \$(find '$nest/.claude/skills' -mindepth 1 -maxdepth 1 -type l | wc -l) -eq 9 ]]"
assert "backed up skill text is only in the state dir" "[[ \$(grep -Rls 'description: \"stale\"' '$nest' | wc -l) -eq 0 && \$(grep -Rls 'description: \"stale\"' '$(backup_root)' | wc -l) -eq 1 ]]"

# Second symlink run relinks without nesting or another backup.
runs_after_first="$(run_dirs | wc -l | tr -d ' ')"
bash "$SYNC" --mode symlink --repo "$nest" >"$tmp/relink.out" 2>"$tmp/relink.err"
assert "relink stays a symlink" "[[ -L '$nest/.claude/skills/perf' ]]"
assert "relink does not nest" "[[ ! -L '$nest/.claude/skills/perf/perf' && ! -d '$nest/.claude/skills/perf/perf' ]]"
assert "relink adds no backup" "[[ \$(run_dirs | wc -l | tr -d ' ') -eq $runs_after_first ]]"

# A second --force run, after a real dir replaces the installed symlink, gets
# its own backup dir. Remove the symlink first; mkdir -p would follow it into
# the library tree.
rm -rf "$nest/.agents/skills/perf"
mkdir -p "$nest/.agents/skills/perf"
printf 'second\n' > "$nest/.agents/skills/perf/marker"
bash "$SYNC" --mode symlink --repo "$nest" --force >"$tmp/force2.out" 2>"$tmp/force2.err"
bak2="$(sed -n 's/^backed up .* -> //p' "$tmp/force2.out" | head -n 1)"
assert "second run backs up" "[[ -n '$bak2' && \$(cat '$bak2/marker') == second ]]"
assert "backup dirs are unique per run" "[[ '$bak' != '$bak2' && \$(dirname \$(dirname '$bak')) != \$(dirname \$(dirname '$bak2')) ]]"
assert "backup dirs are siblings, not nested" "[[ '$bak2' != '$bak'/* && '$bak' != '$bak2'/* ]]"

# Copy mode requires --force for a differing real directory, including when
# --home is not the invoking user's $HOME.
other="$tmp/other-home"
mkdir -p "$other/.claude/skills/perf"
printf 'foreign\n' > "$other/.claude/skills/perf/marker"
set +e
bash "$SYNC" --mode copy --home "$other" >"$tmp/foreign.out" 2>"$tmp/foreign.err"
code=$?
set -e
assert "copy without force on non-HOME --home exits 0" "[[ $code -eq 0 ]]"
assert "copy without force on non-HOME --home warns" "grep -q 'differs from the library' '$tmp/foreign.err'"
assert "copy without force on non-HOME --home keeps marker" "[[ \$(cat '$other/.claude/skills/perf/marker') == foreign ]]"
assert "copy without force on non-HOME --home does not back up" "! grep -q 'backed up ' '$tmp/foreign.out'"

# Copy into a repo root is the same rule: no silent replace.
plain="$tmp/plain-repo"
mkdir -p "$plain/.agents/skills/perf"
printf 'plain\n' > "$plain/.agents/skills/perf/marker"
bash "$SYNC" --mode copy --repo "$plain" >"$tmp/plain.out" 2>"$tmp/plain.err"
assert "copy without force on --repo keeps marker" "[[ \$(cat '$plain/.agents/skills/perf/marker') == plain ]]"
assert "copy without force on --repo warns" "grep -q 'differs from the library' '$tmp/plain.err'"

runs_before_identical="$(run_dirs | wc -l | tr -d ' ')"
bash "$SYNC" --mode copy --home "$other" --force >"$tmp/copy-force.out" 2>"$tmp/copy-force.err"
assert "copy force backs up" "grep -q 'backed up ' '$tmp/copy-force.out'"
assert "copy force writes library skill" "[[ -f '$other/.claude/skills/perf/SKILL.md' ]]"
assert "copy force is not a symlink" "[[ ! -L '$other/.claude/skills/perf' ]]"
home_bak="$(sed -n 's/^backed up .* -> //p' "$tmp/copy-force.out" | head -n 1)"
assert "copy backup has marker" "[[ -n '$home_bak' && \$(cat '$home_bak/marker') == foreign ]]"
assert "copy backup is outside scanned roots" "[[ '$home_bak' == '$XDG_STATE_HOME/grotap-skills/backup/'* && '$home_bak' != *'/.claude/skills/'* && '$home_bak' != *'/.agents/skills/'* && '$home_bak' != *'/.codex/skills/'* ]]"
assert "copy backup is not listed as a skill" "[[ \$(find '$other/.claude/skills' '$other/.agents/skills' '$other/.codex/skills' -name SKILL.md | wc -l) -eq 27 && -z \"\$(find '$other/.claude/skills' '$other/.agents/skills' '$other/.codex/skills' \\( -name '*.bak.*' -o -path '*/grotap-skills/*' \\) -print)\" ]]"

# Repeat --force of an identical tree writes nothing and adds no backup.
bash "$SYNC" --mode copy --home "$other" --force >"$tmp/identical.out" 2>"$tmp/identical.err"
assert "identical copy is skipped" "grep -q 'already identical to source' '$tmp/identical.out'"
assert "identical copy does not back up" "! grep -q 'backed up ' '$tmp/identical.out'"
assert "identical copy adds no backup run" "[[ \$(run_dirs | wc -l | tr -d ' ') -eq \$((runs_before_identical + 1)) ]]"
assert "identical copy leaves library file" "cmp -s '$LIB/perf/SKILL.md' '$other/.claude/skills/perf/SKILL.md'"

# --force on the repo root replaces, and the library file matches.
bash "$SYNC" --mode copy --repo "$plain" --force >"$tmp/plain-force.out" 2>"$tmp/plain-force.err"
assert "repo copy force replaces" "[[ -f '$plain/.agents/skills/perf/SKILL.md' && ! -e '$plain/.agents/skills/perf/marker' ]]"
assert "library file matches source" "cmp -s '$LIB/perf/SKILL.md' '$plain/.agents/skills/perf/SKILL.md'"
plain_bak="$(sed -n 's/^backed up .* -> //p' "$tmp/plain-force.out" | head -n 1)"
assert "repo backup stays outside the repo skill roots" "[[ -n '$plain_bak' && '$plain_bak' != '$plain/'* ]]"

# Keep only the last 5 backup runs.
retain_state="$tmp/state-retain"
retain_home="$tmp/retain-home"
mkdir -p "$retain_state" "$retain_home/.claude/skills/perf"
printf 'gen0\n' > "$retain_home/.claude/skills/perf/marker"
first_retain=""
i=0
while [[ "$i" -lt 6 ]]; do
  env HOME="$retain_home" XDG_STATE_HOME="$retain_state" \
    bash "$SYNC" --mode copy --home "$retain_home" --force >"$tmp/retain-$i.out" 2>"$tmp/retain-$i.err"
  this="$(sed -n 's/^backed up .* -> //p' "$tmp/retain-$i.out" | head -n 1)"
  assert "retain run $i backed up" "[[ -n '$this' && \$(cat '$this/marker') == gen$i ]]"
  if [[ "$i" -eq 0 ]]; then
    first_retain="$this"
  fi
  last_retain="$this"
  i=$((i + 1))
  rm -rf "$retain_home/.claude/skills/perf"
  mkdir -p "$retain_home/.claude/skills/perf"
  printf 'gen%s\n' "$i" > "$retain_home/.claude/skills/perf/marker"
done
retain_count="$(find "$retain_state/grotap-skills/backup" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
assert "only the last 5 backup runs are kept" "[[ '$retain_count' -eq 5 ]]"
assert "oldest backup run was removed" "[[ ! -d '$(dirname "$(dirname "$first_retain")")' ]]"
assert "newest backup run remains" "[[ -d '$(dirname "$(dirname "$last_retain")")' && \$(cat '$last_retain/marker') == gen5 ]]"
assert "retention across separate invocations keeps 5 runs" "[[ '$retain_count' -eq 5 ]]"

# One invocation that backs up every library skill must keep all of them.
mapfile -t SKILL_NAMES < <(find "$LIB" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
assert "library has more than 5 skills" "[[ ${#SKILL_NAMES[@]} -gt 5 ]]"

seed_real_skills() {
  local root="$1" prefix="$2" name
  for name in "${SKILL_NAMES[@]}"; do
    mkdir -p "$root/$name"
    printf '%s\n' "${prefix}-${name}" > "$root/$name/marker"
  done
}

run_count_under() {
  local state="$1"
  local root="$state/grotap-skills/backup"
  if [[ ! -d "$root" ]]; then
    printf '0\n'
    return 0
  fi
  find "$root" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '
}

many_copy_state="$tmp/state-many-copy"
many_copy_home="$tmp/many-copy-home"
mkdir -p "$many_copy_state"
seed_real_skills "$many_copy_home/.claude/skills" copy
env HOME="$tmp/many-copy-invoker" XDG_STATE_HOME="$many_copy_state" \
  bash "$SYNC" --mode copy --home "$many_copy_home" --force >"$tmp/many-copy.out" 2>"$tmp/many-copy.err"
copy_run="$(find "$many_copy_state/grotap-skills/backup" -mindepth 1 -maxdepth 1 -type d)"
assert "copy --force of every skill uses one run dir" "[[ \$(run_count_under '$many_copy_state') -eq 1 ]]"
assert "copy --force reports every skill backup" "[[ \$(grep -c '^backed up ' '$tmp/many-copy.out') -eq ${#SKILL_NAMES[@]} ]]"
for name in "${SKILL_NAMES[@]}"; do
  assert "copy backup keeps $name" "[[ \$(cat '$copy_run/home-claude/$name/marker') == copy-$name ]]"
done

many_link_state="$tmp/state-many-link"
many_link_home="$tmp/many-link-home"
mkdir -p "$many_link_state"
seed_real_skills "$many_link_home/.claude/skills" link
env HOME="$tmp/many-link-invoker" XDG_STATE_HOME="$many_link_state" \
  bash "$SYNC" --mode symlink --home "$many_link_home" --force >"$tmp/many-link.out" 2>"$tmp/many-link.err"
link_run="$(find "$many_link_state/grotap-skills/backup" -mindepth 1 -maxdepth 1 -type d)"
assert "symlink --force of every skill uses one run dir" "[[ \$(run_count_under '$many_link_state') -eq 1 ]]"
assert "symlink --force reports every skill backup" "[[ \$(grep -c '^backed up ' '$tmp/many-link.out') -eq ${#SKILL_NAMES[@]} ]]"
for name in "${SKILL_NAMES[@]}"; do
  assert "symlink backup keeps $name" "[[ \$(cat '$link_run/home-claude/$name/marker') == link-$name && -L '$many_link_home/.claude/skills/$name' ]]"
done

# No backup location: fail before moving anything.
unset_home="$tmp/unset-home"
mkdir -p "$unset_home/.claude/skills/perf"
printf 'stay\n' > "$unset_home/.claude/skills/perf/marker"
root_before="$tmp/root-before"
root_after="$tmp/root-after"
{ find / -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null || true; } | sort > "$root_before"
set +e
env -u HOME -u XDG_STATE_HOME bash "$SYNC" --mode copy --home "$unset_home" --force >"$tmp/unset.out" 2>"$tmp/unset.err"
code=$?
set -e
{ find / -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null || true; } | sort > "$root_after"
assert "unset HOME and XDG_STATE_HOME exits 2" "[[ $code -eq 2 ]]"
assert "unset HOME and XDG_STATE_HOME explains why" "grep -q 'HOME and XDG_STATE_HOME are unset' '$tmp/unset.err'"
assert "unset env leaves the skill dir unchanged" "[[ \$(cat '$unset_home/.claude/skills/perf/marker') == stay && ! -e '$unset_home/.claude/skills/perf/SKILL.md' ]]"
assert "unset env creates no other skill root" "[[ ! -d '$unset_home/.agents' && ! -d '$unset_home/.codex' ]]"
assert "unset env creates no root run directory" "cmp -s '$root_before' '$root_after'"
assert "unset env does not back up" "! grep -q 'backed up ' '$tmp/unset.out' '$tmp/unset.err'"

if [[ "$fail" -ne 0 ]]; then
  printf 'sync-skills tests failed\n' >&2
  exit 1
fi
printf 'sync-skills tests passed\n'
