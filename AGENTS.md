# AGENTS.md — Shared entry for every AI

This file is the tool-neutral entry point for every AI that works in this repo: Claude Code, Grok (Bot / Grok Bot), Gemini, Codex and Cursor. All of them follow the same rules. Tool-specific entry files (listed at the end) add mechanics only.

## Load order

At the start of every substantive session, before editing code or filing work:

1. `agents/GLOBAL.md` — the single constitution. It holds the numbered absolute rules and the Manor View go-live freeze (in force through 2026-11-13). If anything here or in a tool file disagrees with it, `agents/GLOBAL.md` wins.
2. `PROJECT_STATUS.md` — what is being built and what is live.
3. `docs/PRIORITY_SURFACES.md` — the surface map and freezes.
4. `docs/00-INDEX.md`, then the docs for the surface you are touching.
5. For fleet, dispatch or role work only: `agents/SERVERS.md` and the matching `agents/lessons/*.md` files (by trigger, never all of them).

## Official designs

These are adopted by the owner and bind every AI:

- `docs/05-agents/agent-assignment-design.md` — agent assignment separated from execution, no model lock-in.
- `docs/05-agents/owner-ai-teammates.md` — how the owner's AI teammates divide the work.

## Shared defaults

These owner defaults apply to every AI (they are also stated in `CLAUDE.md`). `agents/GLOBAL.md` wins on any conflict; a new rule goes into `agents/GLOBAL.md`, not here.

- Pipeline first. Substantive changes go through the pipeline and agent fleet (plan, owner prompt, dispatch, review). Building directly is for trivial fixes, doc work the owner assigned, and emergencies.
- Secrets live in Doppler only (`grotap` project). Use `doppler run -- <cmd>`. Never put a secret value in chat, prompts, task files, logs or commits.
- Git discipline. The branch is `master`. Never run `git add -A` or `git add .`; stage named paths. Use worktrees for multi-session work and leave peers' files alone in shared checkouts.
- Never name the competitor RFID vendor. Write "Competitor RFID Software" or `competitor`.

## Tool-specific entry files

| Tool | Entry file | Notes |
|---|---|---|
| Claude Code | `CLAUDE.md` | Also runs `.claude-session-init.sh` and reads `BOOTSTRAP.md`. |
| Grok (Bot / Grok Bot) | `BOT.md` | Grok has no native repo file loading; the owner's Grok project instruction tells it to read `BOT.md` and this file. |
| Gemini CLI | `GEMINI.md` | `.gemini/settings.json` makes Gemini load this file and `GEMINI.md`. |
| Codex, Cursor | this file | Both read `AGENTS.md` natively. |

Tool files hold mechanics only, never rules. Rules change only in `agents/GLOBAL.md`.
