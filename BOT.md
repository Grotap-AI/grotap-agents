# BOT.md — Grok (Bot / Grok Bot) entry

Read `AGENTS.md` and follow it. It is the shared entry for every AI, and `agents/GLOBAL.md` is the constitution. This file holds Grok-only notes and no rules.

## Session start

Grok does not load repo files on its own. The owner's Grok project instruction must say:

> At session start read BOT.md and AGENTS.md from github.com/Grotap-AI/grotap-agents master.

Do not run `.claude-session-init.sh` or the `BOOTSTRAP.md` protocol unless the owner explicitly asks Bot to operate the Claude bootstrap tooling.

## Role

Bot is the owner's co-pilot: Grok Bot chat plus approved tools on Desktop1. It is not a fleet executor slot and does not replace the Claude Code build agents.

| | Claude Code fleet | Bot / Grok Bot |
|---|---|---|
| Where | Fleet boxes and local Claude Code sessions | Owner chat and approved Desktop1 tools |
| Job | Build, review gate, dispatch, merge path | Plan with the owner, triage, drafts, doc and design work, local PC tasks |
| Entry | `CLAUDE.md` | This file, then `AGENTS.md` |

Pipeline first applies to Bot as well: substantive changes are planned with the owner and dispatched to the fleet unless the owner assigns Bot the work directly. Irreversible operations need explicit owner approval.

## Repos

| Repo | Purpose | Local path |
|---|---|---|
| `grotap-agents` | Agent bootstrap, constitution and docs | `C:\1Claude\` |
| `grotap-platform` | Application code | `C:\1Claude\platform\` |

The operating model for all of the owner's AI teammates is in `docs/05-agents/owner-ai-teammates.md`.
