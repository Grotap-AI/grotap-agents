#!/usr/bin/env bash
# Read-only skills loading check for a builder box.
# Writes only under --home (default /tmp/skills-test-home). Does not need root
# or an API key. Skips Codex or Claude Code when that binary is missing.
# Idempotent.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/library"
SYNC="$ROOT/scripts/sync-skills.sh"
HOME_DEST="/tmp/skills-test-home"
CODEX_BIN="${CODEX_BIN:-}"
CLAUDE_BIN="${CLAUDE_BIN:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --home) HOME_DEST="${2:-}"; shift 2 ;;
    --codex-bin) CODEX_BIN="${2:-}"; shift 2 ;;
    --claude-bin) CLAUDE_BIN="${2:-}"; shift 2 ;;
    -h|--help)
      echo "usage: load-test.sh [--home DIR] [--codex-bin PATH] [--claude-bin PATH]"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$HOME_DEST" ]]; then
  echo "--home must be a directory path" >&2
  exit 2
fi

tokens_from_bytes() {
  echo $(( ($1 + 3) / 4 ))
}

front_description() {
  local file="$1" line
  line="$(sed -n 's/^description: "\(.*\)"[[:space:]]*$/\1/p' "$file" | head -n 1)"
  if [[ -z "$line" ]]; then
    line="$(sed -n "s/^description: '\\(.*\\)'[[:space:]]*$/\\1/p" "$file" | head -n 1)"
  fi
  printf '%s' "$line"
}

echo "=== grotap skills load-test ==="
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "user: $(id -un) uid=$(id -u)"
echo "repo_skills_root: $ROOT"
echo "canonical: $LIB"
echo "scratch_home: $HOME_DEST"
echo "tokenizer: codex rust-v0.157.0 approx_token_count = (byte_len + 3) / 4"
echo "listing_line: - {name}: {description} (file: {path}) plus newline"
echo "budget_rule: 2% of context window in tokens; if window unknown, 8000 characters (render.rs DEFAULT_SKILL_METADATA_CHAR_BUDGET)"
echo "context_window: unknown (no model call, no API key)"
echo "fallback_char_budget: 8000"
echo "reference_2pct_tokens_128000: 2560"
echo "reference_2pct_tokens_200000: 4000"

SCRATCH="$HOME_DEST/repo"
mkdir -p "$HOME_DEST"
if [[ ! -d "$SCRATCH/.git" ]]; then
  mkdir -p "$SCRATCH"
  git -C "$SCRATCH" init -q
fi
bash "$SYNC" --mode symlink --repo "$SCRATCH" --home "$HOME_DEST" >"$HOME_DEST/sync.out"
echo "--- sync (scratch only) ---"
cat "$HOME_DEST/sync.out"

echo "--- per skill ---"
echo "name desc_chars listing_bytes listing_tokens body_bytes body_tokens skill_md"
listing_bytes_total=0
listing_tokens_total=0
body_tokens_total=0
count=0
char_total=0
while IFS= read -r skill_md; do
  name="$(basename "$(dirname "$skill_md")")"
  desc="$(front_description "$skill_md")"
  desc_chars="${#desc}"
  installed="$SCRATCH/.agents/skills/$name/SKILL.md"
  line="- ${name}: ${desc} (file: ${installed})"
  listing_bytes="$(printf '%s\n' "$line" | wc -c | tr -d ' ')"
  listing_tokens="$(tokens_from_bytes "$listing_bytes")"
  body_bytes="$(wc -c < "$skill_md" | tr -d ' ')"
  body_tokens="$(tokens_from_bytes "$body_bytes")"
  printf '%s %s %s %s %s %s %s\n' \
    "$name" "$desc_chars" "$listing_bytes" "$listing_tokens" \
    "$body_bytes" "$body_tokens" "$skill_md"
  listing_bytes_total=$((listing_bytes_total + listing_bytes))
  listing_tokens_total=$((listing_tokens_total + listing_tokens))
  body_tokens_total=$((body_tokens_total + body_tokens))
  char_total=$((char_total + desc_chars))
  count=$((count + 1))
done < <(find "$LIB" -mindepth 2 -maxdepth 2 -name SKILL.md | sort)

echo "--- totals ---"
echo "skill_count: $count"
echo "description_chars: $char_total"
echo "listing_bytes: $listing_bytes_total"
echo "listing_tokens: $listing_tokens_total"
echo "body_tokens: $body_tokens_total"
echo "char_budget_8000_used: $listing_bytes_total"
if [[ "$listing_bytes_total" -le 8000 ]]; then
  echo "char_budget_8000_headroom: $((8000 - listing_bytes_total))"
else
  echo "char_budget_8000_headroom: OVER by $((listing_bytes_total - 8000))"
fi
echo "token_headroom_vs_128000_2pct: $((2560 - listing_tokens_total))"
echo "token_headroom_vs_200000_2pct: $((4000 - listing_tokens_total))"
echo "note: listing cost is name+description+path only. SKILL.md bodies stay on disk until a skill is invoked."

echo "--- codex ---"
if [[ -z "$CODEX_BIN" ]]; then
  CODEX_BIN="$(command -v codex || true)"
fi
if [[ -z "$CODEX_BIN" || ! -x "$CODEX_BIN" ]]; then
  echo "SKIP codex: not installed"
else
  echo "codex_bin: $CODEX_BIN"
  echo "codex_version_raw:"
  version_out="$("$CODEX_BIN" --version 2>&1 || true)"
  printf '%s\n' "$version_out"
  if printf '%s\n' "$version_out" | grep -Eq '0\.157\.'; then
    echo "codex_version_is_0_157: yes"
    echo "codex_cwd: $SCRATCH"
    echo "codex_expected_repo_root: $SCRATCH/.agents/skills"
    echo "codex_expected_user_roots: $HOME_DEST/.agents/skills $HOME_DEST/.codex/skills"
    echo "codex_debug_prompt_input:"
    set +e
    timeout 25s env HOME="$HOME_DEST" CODEX_HOME="$HOME_DEST/.codex" \
      "$CODEX_BIN" debug prompt-input 'list installed skills' \
      >"$HOME_DEST/codex-prompt-input.txt" 2>"$HOME_DEST/codex-prompt-input.err"
    code=$?
    set -e
    echo "exit: $code"
    echo "--- stdout ---"
    cat "$HOME_DEST/codex-prompt-input.txt" || true
    echo "--- stderr ---"
    cat "$HOME_DEST/codex-prompt-input.err" || true
    echo "--- skill paths mentioned ---"
    grep -E 'SKILL\.md|Available skills|engineering-principles|verify-and-prove' \
      "$HOME_DEST/codex-prompt-input.txt" "$HOME_DEST/codex-prompt-input.err" || true
  else
    echo "SKIP codex live list: binary is not 0.157.x"
  fi
fi

echo "--- claude code ---"
if [[ -z "$CLAUDE_BIN" ]]; then
  CLAUDE_BIN="$(command -v claude || true)"
fi
if [[ -z "$CLAUDE_BIN" || ! -x "$CLAUDE_BIN" ]]; then
  echo "SKIP claude: not installed"
else
  echo "claude_bin: $CLAUDE_BIN"
  echo "claude_version_raw:"
  "$CLAUDE_BIN" --version 2>&1 || true
  echo "project_skills:"
  find "$SCRATCH/.claude/skills" -name SKILL.md | sort
  echo "user_skills_under_throwaway_home:"
  find "$HOME_DEST/.claude/skills" -name SKILL.md | sort
  echo "claude_help_skills_lines:"
  set +e
  timeout 20s env HOME="$HOME_DEST" "$CLAUDE_BIN" --help >"$HOME_DEST/claude-help.txt" 2>"$HOME_DEST/claude-help.err"
  help_code=$?
  set -e
  echo "help_exit: $help_code"
  grep -n -i -E 'skill' "$HOME_DEST/claude-help.txt" "$HOME_DEST/claude-help.err" || echo "(no skill lines in --help)"
  resolved="$(readlink -f "$CLAUDE_BIN" || true)"
  echo "claude_resolved: ${resolved:-unknown}"
  search_root=""
  if [[ -n "$resolved" ]]; then
    search_root="$(cd "$(dirname "$resolved")/.." && pwd)"
  fi
  echo "claude_package_root_guess: ${search_root:-none}"
  if [[ -n "$search_root" && -d "$search_root" ]]; then
    echo "package_mentions_of_.claude/skills:"
    grep -R -l --include='*.js' --include='*.mjs' --include='*.cjs' --include='*.json' \
      -e '.claude/skills' "$search_root" 2>/dev/null | head -n 20 || echo "(no matches or package not readable)"
  fi
  if [[ -z "${ANTHROPIC_API_KEY:-}${CLAUDE_API_KEY:-}" ]]; then
    echo "SKIP claude live session: no API key"
  fi
fi

echo "=== end ==="
