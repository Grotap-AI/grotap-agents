# AGENTS.md — Shared entry for every AI

Tool-neutral entry for every AI in this repo (Claude Code, Grok, Gemini, Codex, Cursor). Same rules for all; tool files (end of file) add mechanics only.

## Load order (canonical — `BOOTSTRAP.md` and `agents/GLOBAL.md` point here)

Always, at the start of every session:

1. Your tool entry file (`CLAUDE.md` is auto-loaded for Claude Code).
2. `agents/GLOBAL.md` — the single constitution: the numbered absolute rules and the Manor View go-live freeze (through 2026-11-13). It wins over this file and every tool file.

On demand — read only when your task touches it:

- `docs/PRIORITY_SURFACES.md` — choosing or scoping work, or any freeze question.
- `docs/00-INDEX.md`, then that surface's docs — before editing a surface.
- `PROJECT_STATUS.md` — what is live and what is being built.
- `agents/SERVERS.md` — fleet, SSH or host work.
- `agents/roles/{module}/MODULE.md` then `{role}/ROLE.md` — fleet role work.
- `agents/lessons/*.md` — by diff trigger (table in `agents/GLOBAL.md`), never all of them.

Fleet and jumpbox sessions also follow `BOOTSTRAP.md`.

## Official designs

These are adopted by the owner and bind every AI:

- `docs/05-agents/agent-assignment-design.md` — agent assignment separated from execution, no model lock-in.
- `docs/05-agents/owner-ai-teammates.md` — how the owner's AI teammates divide the work.

## Shared defaults

These owner defaults apply to every AI. `agents/GLOBAL.md` wins on any conflict; new rules go there, not here.

- Claude CLI first. Auto-dispatch permanently frozen 2026-10-30; agents work only human-dispatched `agent_eligible` cases (`agents/GLOBAL.md` § Fleet).
- Secrets live in Doppler only (`grotap` project). Use `doppler run -- <cmd>`. Never put a secret value in chat, prompts, task files, logs or commits.
- Git discipline. The branch is `master`. Never run `git add -A` or `git add .`; stage named paths. Use worktrees for multi-session work and leave peers' files alone in shared checkouts.
- Never name the competitor RFID vendor. Write "Competitor RFID Software" or `competitor`.

## Tool-specific entry files

| Tool | Entry file | Notes |
|---|---|---|
| Claude Code | `CLAUDE.md` | Also runs `.claude-session-init.sh`. `BOOTSTRAP.md` is fleet/jumpbox only. |
| Grok (Bot / Grok Bot) | `BOT.md` | Grok has no native repo file loading; the owner's Grok project instruction tells it to read `BOT.md` and this file. |
| Gemini CLI | `GEMINI.md` | `.gemini/settings.json` makes Gemini load this file and `GEMINI.md`. |
| Codex, Cursor | this file | Both read `AGENTS.md` natively. |

Tool files hold mechanics only, never rules. Rules change only in `agents/GLOBAL.md`.
