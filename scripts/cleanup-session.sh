#!/bin/bash
# scripts/cleanup-session.sh
# Runs on Claude Code session end.
# Cleans up ephemeral session state.

SESSION_FILE=".current-session.json"

if [[ -f "$SESSION_FILE" ]]; then
  rm -f "$SESSION_FILE"
  echo "Session manifest removed."
fi
