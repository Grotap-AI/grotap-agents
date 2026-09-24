# Grotap Prompt / Agent Team / Astra provision

**Date:** 2026-09-23 (PT)
**Status:** Aaron GO — provision + rename
**Bootstrap:** land this alongside SERVERS.md / rename plan in grotap-agents

## Names (locked)

| Host | Action | Model / role |
|------|--------|----------------|
| `prompt-01-astra` | New Ashburn Hetzner | GPT-6 Astra — Prompt Option |
| `agent-team-01-astra` | New Ashburn Hetzner | GPT-6 Astra — Agent Team |
| `prompt-01-claude` | Rename from `claude-code-01` | Claude jump seat (Prompt Option Claude path) |

## Rules

1. Lowercase hyphens; Hetzner Cloud name = Linux hostname.
2. Ashburn only for new metal.
3. Fast mode off by default; spend caps on Astra.
4. Not in Team Claude `agent-0N-claude` pool.
5. Do not create `agent-11-codex`; do not retire `openreplay-ai-support`.

## Speed model

Claude fleet has many boxes for **concurrent** work (throughput), not lower latency per job. Dedicated Astra Prompt + Agent Team boxes remove contention with that fleet.
