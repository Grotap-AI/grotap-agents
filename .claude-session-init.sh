#!/bin/bash
# .claude-session-init.sh
# grotap ERP Agent Session Initializer
set -e

MODE=${1:---full}

echo "================================================"
echo "  grotap Agent Session Initializer"
echo "================================================"

# ── 1. GIT SYNC ───────────────────────────────────
echo "[1/5] Syncing with origin..."
git fetch origin master --quiet
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/master)

if [ "$LOCAL" != "$REMOTE" ]; then
  echo "  WARNING: Local branch is behind origin."
  echo "  Running git pull..."
  git pull origin master --quiet
fi

SESSION_COMMIT=$(git rev-parse HEAD)
echo "  Commit: $SESSION_COMMIT"

# ── 2. VALIDATE MD STRUCTURE ──────────────────────
echo "[2/5] Validating MD file structure..."

REQUIRED_FILES=(
  "agents/GLOBAL.md"
  "agents/SERVERS.md"
  "agents/registry.md"
  "agents/OWNERS.md"
  "agents/roles/shared/handoff-schema.md"
  "agents/roles/shared/conventions.md"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "  ERROR: Required file missing: $f"
    exit 1
  fi
done
echo "  Structure valid."

# ── 3. CHECK GLOBAL.md SIZE ───────────────────────
# Budget is BYTES, not lines: GLOBAL.md is cat'd verbatim into every agent prompt,
# so cost is bytes. The old 200-line cap was set when lines were ~200 chars; by
# 2026-07-25 they averaged 1,400 and the file had reached 199 KB (~50k tokens per
# dispatch) while still "passing" nothing. Incident lessons now live in
# agents/lessons/*.md and are read on demand — see GLOBAL.md § Lessons.
GLOBAL_MAX_BYTES=${GLOBAL_MAX_BYTES:-40960}
echo "[3/5] Checking GLOBAL.md size..."
BYTES=$(wc -c < agents/GLOBAL.md)
if [ "$BYTES" -gt "$GLOBAL_MAX_BYTES" ]; then
  echo "  ERROR: agents/GLOBAL.md is $BYTES bytes (max $GLOBAL_MAX_BYTES)."
  echo "  Do NOT raise the cap. Move new lessons into agents/lessons/<surface>.md"
  echo "  and generalize duplicates. See GLOBAL.md § Lessons."
  exit 1
fi

if [ ! -d agents/lessons ]; then
  echo "  ERROR: agents/lessons/ is missing — GLOBAL.md § Lessons points at it."
  exit 1
fi
LESSON_FILES=$(ls agents/lessons/*.md 2>/dev/null | wc -l)
echo "  GLOBAL.md: $BYTES/$GLOBAL_MAX_BYTES bytes, $LESSON_FILES lesson files (OK)"

# ── 4. EXPORT SESSION VARS ────────────────────────
echo "[4/5] Exporting session variables..."
export AGENT_SESSION_COMMIT=$SESSION_COMMIT
export AGENT_SESSION_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "  SESSION_COMMIT=$SESSION_COMMIT"
echo "  SESSION_TIMESTAMP=$AGENT_SESSION_TIMESTAMP"

# ── 5. WRITE SESSION MANIFEST ─────────────────────
echo "[5/5] Writing session manifest..."
cat > .current-session.json << EOF
{
  "session_commit": "$SESSION_COMMIT",
  "session_timestamp": "$AGENT_SESSION_TIMESTAMP",
  "initialized": true
}
EOF

echo "================================================"
echo " READY — Session commit: $SESSION_COMMIT"
echo "================================================"
