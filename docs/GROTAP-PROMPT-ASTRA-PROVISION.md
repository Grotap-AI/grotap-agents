# Grotap Prompt / Agent Team / Astra provision

**Date:** 2026-09-23 (PT)
**Status:** `prompt-01-claude` (`178.156.209.112`) was **deleted 2026-09-26**. Hetzner has no server by that name. `prompt-01-astra` is separate metal at `5.161.243.18`. `agent-team-01-astra` is `5.161.80.75`.
**Bootstrap:** land this alongside SERVERS.md / rename plan in grotap-agents

## Names (locked)

| Host | Action | Model / role |
|------|--------|----------------|
| `prompt-01-astra` | Live Ashburn `5.161.243.18` (cpx31, Hetzner id 167204705) | GPT-6 Astra — Prompt Option. Outside the Team Claude pool |
| `agent-team-01-astra` | Live Ashburn `5.161.80.75` (cpx31, Hetzner id 167204706) | GPT-6 Astra — Agent Team. Outside the Team Claude pool |
| `prompt-01-claude` | Deleted 2026-09-26. Was `178.156.209.112` (from `claudecode-01` / `claude-code-01`). DNS `claudecode.grotap.com` was unchanged. Hetzner has no server by that name. Not the Astra host | Former Claude jump seat |

## Rules

1. Lowercase hyphens; Hetzner Cloud name = Linux hostname.
2. Ashburn only for new metal.
3. Fast mode off by default; spend caps on Astra.
4. Not in Team Claude `agent-0N-claude` pool.
5. Do not create `agent-11-codex`; do not retire `openreplay-ai-support`.

## Speed model

Claude fleet has many boxes for **concurrent** work (throughput), not lower latency per job. Dedicated Astra Prompt + Agent Team boxes remove contention with that fleet.
