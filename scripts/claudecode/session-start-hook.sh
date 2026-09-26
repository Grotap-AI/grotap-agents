#!/usr/bin/env bash
# session-start-hook.sh — Claude Code SessionStart hook: best-effort bootstrap
# + environment-readiness report.
#
# Wired via .claude/settings.json (hooks.SessionStart) in BOTH repos:
#   grotap-platform: scripts/claudecode/session-start-hook.sh   (canonical)
#   grotap-agents:   scripts/claudecode/session-start-hook.sh   (mirror — keep in sync)
#
# Runs at the start of EVERY session in the repo, across four environments:
#   1. Windows local (Git Bash)          — report only; NEVER git-pull here: the
#      local tree is SHARED between concurrent Claude sessions (see platform
#      CLAUDE.md "Shared-Tree Git Etiquette").
#   2. claudecode jumpbox seats (user1-5) — per-user isolated clones: safe to
#      sync + run .claude-session-init.sh.
#   3. Fleet agent servers               — report only (dispatcher owns sync).
#   4. claude.ai cloud sandbox           — report only; points at
#      docs/CLAUDE_CODE_CLOUD_ENV.md when doppler is missing.
#
# CONTRACT: must NEVER fail or block the session — every step guarded, exit 0.
# stdout is appended to the session's context. Claude Code prompt-caches that
# leading context, so the byte-stable rule is printed first and every per-run
# sha, count, and timestamp is buffered until after prompt-cache-prefix-end.
set -u

# Quoted heredoc: nothing in here is expanded. Keep it free of dates, shas,
# case ids, and command substitutions — it is the cached prefix.
print_prompt_cache_prefix() {
  cat <<'EOF'
[bootstrap] !! RULE: never quote a file:line from this tree in a report, a correction or an argument without re-reading it via `git show origin/master:<path>` (prefix MSYS_NO_PATHCONV=1 when the path starts with a dot).
[bootstrap] prompt-cache-prefix-end
EOF
}

VOLATILE_LINES=()
say() { VOLATILE_LINES+=("$*"); }

flush_session_context() {
  print_prompt_cache_prefix
  if [ "${#VOLATILE_LINES[@]}" -gt 0 ]; then
    printf '%s\n' "${VOLATILE_LINES[@]}"
  fi
}

main() {
  VOLATILE_LINES=()

  ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
    *) IS_WINDOWS=0 ;;
  esac

  # --- Jumpbox seats: sync isolated per-user clones + run session init --------
  # Detection: Linux + ~/.claude-remote (created by provision.sh on the box only).
  JUMPBOX=0
  if [ "$IS_WINDOWS" = 0 ] && [ -d "${HOME:-/nonexistent}/.claude-remote" ] && [ -d "${HOME:-/nonexistent}/workspace/grotap/.git" ]; then
    JUMPBOX=1
    W="${HOME}/workspace/grotap"
    git -C "$W" pull --ff-only -q 2>/dev/null \
      || say "[bootstrap] WARN: grotap-agents pull failed (offline or diverged) — working from $(git -C "$W" rev-parse --short HEAD 2>/dev/null || echo '?')"
    if [ -d "$W/platform/.git" ]; then
      git -C "$W/platform" pull --ff-only -q 2>/dev/null \
        || say "[bootstrap] WARN: grotap-platform pull failed — working from $(git -C "$W/platform" rev-parse --short HEAD 2>/dev/null || echo '?')"
    else
      say "[bootstrap] WARN: no grotap-platform clone at $W/platform — run scripts/claudecode/seed-secrets.sh (from an operator machine) to install git credentials + clone"
    fi
    # Run (not source) so its `exit 1` (e.g. GLOBAL.md >200 lines) can't kill us.
    # stdout is discarded: session-init prints a per-run timestamp, which must
    # not land in this hook's context.
    ( cd "$W" && bash ./.claude-session-init.sh >/dev/null 2>&1 ) \
      && say "[bootstrap] session-init: OK ($W)" \
      || say "[bootstrap] WARN: .claude-session-init.sh failed — validate MD structure manually per BOOTSTRAP.md"
  fi

  # --- Repo git hooks (all environments) --------------------------------------
  # competitor-name guard (owner rule 2026-09-10): pre-commit + commit-msg refuse
  # additions that name the competitor RFID vendor. Idempotent, never fatal.
  if [ -d "$ROOT/scripts/git-hooks" ] && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$ROOT" config core.hooksPath scripts/git-hooks 2>/dev/null || true
  fi

  # --- Readiness report (all environments) ------------------------------------
  say "[bootstrap] repo: $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown) on $(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?') ($(uname -s 2>/dev/null || echo unknown))"

  # --- Staleness of THIS checkout vs origin/master (all environments) ---------
  # The local Windows tree is shared between concurrent sessions and drifts far
  # behind master; a file:line quoted from it is then fiction. Measure it once at
  # session start and say it out loud.
  #
  # The PreToolUse guard (scripts/claudecode/stale-evidence-guard.py) owns its own
  # cache ENTIRELY: there is no longer any shared-cache contract with this script,
  # and nothing here parses or writes the guard's JSON.
  #
  # NOTE: this fetch does NOT pull. The Windows tree is shared (platform
  # CLAUDE.md "Shared-Tree Git Etiquette") and must never be moved from here.
  # It is SKIPPED outright when no `timeout` mechanism exists -- an unbounded fetch
  # can hang forever on a network stall or a credential prompt, and a SessionStart
  # hook must never block. Interactive prompting is disabled either way so git
  # fails fast instead of waiting on a terminal nobody is watching.
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    ST_FETCH="skipped"
    if command -v timeout >/dev/null 2>&1; then
      GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=echo SSH_ASKPASS=echo SSH_ASKPASS_REQUIRE=never \
        GCM_INTERACTIVE=never timeout 20 git -C "$ROOT" fetch -q origin master 2>/dev/null \
        && ST_FETCH="ok" || ST_FETCH="failed"
    fi
    ST_TOP="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || echo '')"
    ST_BEHIND="$(git -C "$ROOT" rev-list --count HEAD..origin/master 2>/dev/null || echo '')"
    ST_AHEAD="$(git -C "$ROOT" rev-list --count origin/master..HEAD 2>/dev/null || echo 0)"
    ST_BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    ST_DIRTY="$(git -C "$ROOT" status --porcelain 2>/dev/null | grep -c . || true)"
    [ -n "${ST_DIRTY:-}" ] || ST_DIRTY=0
    if [ "$ST_FETCH" != "ok" ]; then
      say "[bootstrap] freshness: fetch $ST_FETCH -- the counts below are against the origin/master ref AS IT ALREADY IS on disk (only as fresh as the last successful fetch)."
    fi
    if [ -n "$ST_BEHIND" ] && [ -n "$ST_TOP" ]; then
      if [ "$ST_BEHIND" -eq 0 ] 2>/dev/null; then
        say "[bootstrap] freshness: CURRENT with origin/master (0 behind, $ST_AHEAD ahead, $ST_DIRTY dirty) on $ST_BRANCH"
      else
        say "[bootstrap] !! STALE CHECKOUT: $ST_BEHIND commits BEHIND origin/master ($ST_AHEAD ahead, $ST_DIRTY dirty paths) on branch '$ST_BRANCH' -- $ST_TOP"
      fi
    else
      say "[bootstrap] freshness: unknown (no origin/master ref here -- counts unavailable)"
    fi
  fi

  DBPY=""
  if   [ -f "$ROOT/scripts/db.py" ];          then DBPY="scripts/db.py"
  elif [ -f "$ROOT/platform/scripts/db.py" ]; then DBPY="platform/scripts/db.py"
  fi

  # Interpreter with asyncpg: python3 on Linux, usually plain `python` on Windows.
  PY=""
  if   python3 -c 'import asyncpg' >/dev/null 2>&1; then PY=python3
  elif python  -c 'import asyncpg' >/dev/null 2>&1; then PY=python
  fi

  # Jumpbox seats + cloud sandboxes hold a CONFIG-SCOPED service token
  # (grotap/claudecode — exposes ONLY DATABASE_URL, resolved from prd). Passing
  # -p/-c flags for a different config errors against a scoped token, so those
  # environments must invoke doppler flagless; operator machines use prd flags.
  if [ "$JUMPBOX" = 1 ] || [ -n "${DOPPLER_TOKEN:-}" ]; then
    DOP="doppler run --"
  else
    DOP="doppler run -p grotap -c prd --"
  fi

  if command -v doppler >/dev/null 2>&1; then
    if [ -n "$DBPY" ]; then
      say "[bootstrap] doppler: $(doppler --version 2>/dev/null | head -1) — Neon SQL: $DOP ${PY:-python3} $DBPY \"<sql>\""
    else
      say "[bootstrap] doppler: $(doppler --version 2>/dev/null | head -1)"
    fi
  elif [ -n "${DOPPLER_TOKEN:-}" ]; then
    say "[bootstrap] doppler: CLI missing but DOPPLER_TOKEN is set — run: bash scripts/claudecode/cloud-env-setup.sh"
  else
    say "[bootstrap] doppler: NOT AVAILABLE — no secrets/Neon access in this session. Cloud sandbox: owner must configure the claude.ai environment per docs/CLAUDE_CODE_CLOUD_ENV.md; prefer a Remote Control (jumpbox) session for full parity."
  fi

  if [ -n "$DBPY" ]; then
    if [ -n "$PY" ]; then
      say "[bootstrap] asyncpg: ok ($PY)"
    else
      say "[bootstrap] asyncpg: MISSING ($DBPY needs it — apt: python3-asyncpg, pip: pip install asyncpg)"
    fi
  fi

  flush_session_context
  exit 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
