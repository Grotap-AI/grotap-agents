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
# stdout is appended to the session's context.
set -u
say() { printf '%s\n' "$*"; }

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
  *) IS_WINDOWS=0 ;;
esac

# --- Jumpbox seats: sync isolated per-user clones + run session init --------
# Detection: Linux + ~/.claude-remote (created by provision.sh on the box only).
if [ "$IS_WINDOWS" = 0 ] && [ -d "${HOME:-/nonexistent}/.claude-remote" ] && [ -d "${HOME:-/nonexistent}/workspace/grotap/.git" ]; then
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
  ( cd "$W" && bash ./.claude-session-init.sh >/dev/null 2>&1 ) \
    && say "[bootstrap] session-init: OK ($W)" \
    || say "[bootstrap] WARN: .claude-session-init.sh failed — validate MD structure manually per BOOTSTRAP.md"
fi

# --- Readiness report (all environments) ------------------------------------
say "[bootstrap] repo: $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown) on $(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?') ($(uname -s 2>/dev/null || echo unknown))"

DBPY=""
if   [ -f "$ROOT/scripts/db.py" ];          then DBPY="scripts/db.py"
elif [ -f "$ROOT/platform/scripts/db.py" ]; then DBPY="platform/scripts/db.py"
fi

# Interpreter with asyncpg: python3 on Linux, usually plain `python` on Windows.
PY=""
if   python3 -c 'import asyncpg' >/dev/null 2>&1; then PY=python3
elif python  -c 'import asyncpg' >/dev/null 2>&1; then PY=python
fi

if command -v doppler >/dev/null 2>&1; then
  if [ -n "$DBPY" ]; then
    say "[bootstrap] doppler: $(doppler --version 2>/dev/null | head -1) — Neon SQL: doppler run -p grotap -c prd -- ${PY:-python3} $DBPY \"<sql>\""
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
exit 0
