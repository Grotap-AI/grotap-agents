#!/usr/bin/env bash
# claude-prompt-cache.sh — keep Claude Code prompt caching enabled.
#
# Claude Code caches its system prompt unless a DISABLE_PROMPT_CACHING*
# variable is set. The family is per-model as well as global:
#   DISABLE_PROMPT_CACHING
#   DISABLE_PROMPT_CACHING_SONNET / _OPUS / _HAIKU / _FABLE
#   and any later DISABLE_PROMPT_CACHING* name
# CLAUDE_CODE_DISABLE_PROMPT_CACHING* is the same switch with a prefix.
#
# Source this in the shell that execs claude. When doppler run wraps the
# launch, doppler injects prd AFTER a parent unset, so execute this file
# as the command doppler runs (`bash claude-prompt-cache.sh claude ...`).
# It then clears the switches and execs the remaining arguments.
#
# `unset` of a name that is not set is a no-op under `set -u`.
# compgen exits 1 when nothing matches; that must not trip `set -e`.

grotap_clear_prompt_cache_disables() {
  local name names
  names="$(
    compgen -A export DISABLE_PROMPT_CACHING || true
    compgen -A export CLAUDE_CODE_DISABLE_PROMPT_CACHING || true
  )"
  [ -n "$names" ] || return 0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    unset "$name"
  done <<< "$names"
}

grotap_clear_prompt_cache_disables

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ $# -eq 0 ]]; then
    exit 0
  fi
  exec "$@"
fi
