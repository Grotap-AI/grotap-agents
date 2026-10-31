# CLAUDE.md — grotap-agents (auto-loaded every session)

Shared entry for every AI: `AGENTS.md` (canonical load order). Constitution: `agents/GLOBAL.md`; its absolute rules win on any conflict. Grok: `BOT.md`. Gemini: `GEMINI.md`.

## Session start (every session, no exceptions)
Run `./.claude-session-init.sh`. The root tree is ff-only, so its pull is safe. `BOOTSTRAP.md` is for fleet and jumpbox sessions only.

## Repos
`grotap-agents` = `C:\1Claude\` (docs in `docs/`). `grotap-platform` = `C:\1Claude\platform\`. `grotap-platform-docs` is remote-only and stale.

## Manor View go-live freeze, through 2026-11-13
Work only ScanTap web, ScanTap Setup, ScanTap Mobile and sister apps, Print Cloud Setup/Labels, and Vendor Avail & Inventory Planning. All else is paused. Detail: `agents/GLOBAL.md`, `docs/PRIORITY_SURFACES.md`.

## Execution
CLAUDE-CLI-FIRST. Auto-dispatch PERMANENTLY frozen 2026-10-30 (owner; enforced in platform code). Major development runs in Claude CLI sessions. Agents work only cases flagged `agent_eligible` that a human dispatches. Still file/answer pipeline cases. Keep the review gate and owner-approved irreversible ops.
