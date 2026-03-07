#!/bin/bash
# .pre-commit-hooks/validate-md-structure.sh
# Verifies that every ROLE.md and MODULE.md listed in registry.md exists on disk.

REGISTRY="agents/registry.md"
ERRORS=0

if [ ! -f "$REGISTRY" ]; then
  echo "  ERROR: $REGISTRY not found."
  exit 1
fi

# Extract .md file paths from registry and check each exists
while IFS= read -r line; do
  if [[ "$line" =~ agents/roles.*\.md|agents/servers.*\.md|agents/GLOBAL\.md|agents/OWNERS\.md ]]; then
    filepath=$(echo "$line" | grep -oE 'agents/[a-z/._-]+\.md' | head -n 1)
    if [ -n "$filepath" ] && [ ! -f "$filepath" ]; then
      echo "  ERROR: registry.md references missing file: $filepath"
      ERRORS=$((ERRORS + 1))
    fi
  fi
done < "$REGISTRY"

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "  ✗ COMMIT BLOCKED: registry.md integrity check failed ($ERRORS missing files)."
  echo "  Update registry.md to match the actual file structure."
  echo ""
  exit 1
fi

echo "  registry.md integrity: OK"
exit 0
