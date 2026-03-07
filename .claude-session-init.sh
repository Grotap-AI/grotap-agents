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
git fetch origin main --quiet
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" != "$REMOTE" ]; then
  echo "  WARNING: Local branch is behind origin."
  echo "  Running git pull..."
  git pull origin main --quiet
fi

SESSION_COMMIT=$(git rev-parse HEAD)
echo "  Commit: $SESSION_COMMIT"

# ── 2. VALIDATE MD STRUCTURE ──────────────────────
echo "[2/5] Validating MD file structure..."

REQUIRED_FILES=(
  "agents/GLOBAL.md"
  "agents/registry.md"
  "agents/OWNERS.md"
  "agents/servers/agent-02.md"
  "agents/servers/agent-03.md"
  "agents/servers/agent-04.md"
  "agents/servers/agent-05.md"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "  ERROR: Required file missing: $f"
    exit 1
  fi
done
echo "  Structure valid."

# ── 3. CHECK GLOBAL.md SIZE ───────────────────────
echo "[3/5] Checking GLOBAL.md size..."
LINES=$(wc -l < agents/GLOBAL.md)
if [ "$LINES" -gt 200 ]; then
  echo "  ERROR: agents/GLOBAL.md has $LINES lines (max 200)."
  echo "  Reduce GLOBAL.md before starting a session."
  exit 1
fi
echo "  GLOBAL.md: $LINES lines (OK)"

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
