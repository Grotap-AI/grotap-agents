#!/bin/bash
# .pre-commit-hooks/check-global-size.sh
# Blocks commits that push agents/GLOBAL.md over 200 lines.

GLOBAL_FILE="agents/GLOBAL.md"
MAX_LINES=200

if git diff --cached --name-only | grep -q "$GLOBAL_FILE"; then
  LINES=$(git show :"$GLOBAL_FILE" 2>/dev/null | wc -l || wc -l < "$GLOBAL_FILE")
  if [ "$LINES" -gt "$MAX_LINES" ]; then
    echo ""
    echo "  ✗ COMMIT BLOCKED: $GLOBAL_FILE has $LINES lines (max $MAX_LINES)."
    echo "  If content is global, refactor it."
    echo "  If domain-specific, move it to the relevant MODULE.md."
    echo "  To override (emergencies only): git commit --no-verify"
    echo ""
    exit 1
  fi
fi
exit 0
