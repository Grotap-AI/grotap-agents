# claude-prompt-cache.sh — keep Claude Code prompt caching enabled.
#
# Claude Code caches tool definitions, the system prompt, and CLAUDE.md on
# its own. DISABLE_PROMPT_CACHING=1 turns that off. CLAUDE_CODE_DISABLE_PROMPT_CACHING
# is unset as well so a prefixed alias of the same switch cannot linger in
# the environment. Source this immediately before invoking `claude`.
# `unset` of a variable that was never set is a no-op under `set -u`.
unset DISABLE_PROMPT_CACHING
unset CLAUDE_CODE_DISABLE_PROMPT_CACHING
