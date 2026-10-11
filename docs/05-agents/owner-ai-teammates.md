# Owner AI Teammates — Claude Code, Grok (Bot) and Gemini

> Operating model for the owner's AI teammates on the grotap platform.
> Status: adopted 2026-09-15 as a dual-AI model; widened to multi-AI 2026-10-11. Does not change fleet bootstrap or the Anthropic requirements for the Claude Code fleet.

## Goal

Aaron works with more than one AI to build and manage the platform. Claude Code remains the primary fleet builder. Bot (Grok Bot) is the owner's co-pilot, and Gemini can be used for the same owner-side work, so design and day-to-day management are not tied to one vendor. Every AI follows the same rules.

## Shared entry

Every AI starts at `AGENTS.md` in the repo root (`grotap-agents`). It gives the load order (constitution, status, priority surfaces, docs index), the official designs and the shared defaults. The constitution is `agents/GLOBAL.md`; its absolute rules and the Manor View go-live freeze bind every AI equally. The application repo (`grotap-platform`) has its own `AGENTS.md` that points back here.

## Roles (do not collapse these)

| Role | Name | Runtime | Entry file | Owns |
|---|---|---|---|---|
| Owner co-pilot | Bot / Grok Bot | Grok Bot chat and approved Desktop1 tools | `BOT.md`, then `AGENTS.md` | Planning with the owner, triage, drafts, design and docs, local investigation |
| Owner co-pilot (alternate) | Gemini | Gemini CLI on Desktop1 | `GEMINI.md` (imports `AGENTS.md`) | Same scope as Bot when the owner chooses Gemini |
| Fleet builder (default) | Claude Code | Fleet boxes and local Claude Code | `CLAUDE.md` plus `BOOTSTRAP.md` | Pipeline execution, review gate, dispatch, merge path |
| Open-model lane (optional) | other teams | OpenRouter on designated boxes | `agents/GLOBAL.md` and `agents/SERVERS.md` | Alternate executors; verify model availability from the executor's region |

Neither Bot nor Gemini is automatically a fleet slot. Putting either into the build pipeline is a separate, explicit routing decision. How assignment is meant to work across models is set out in `docs/05-agents/agent-assignment-design.md`.

## Shared brain (single constitution)

All AIs obey the same constitution and read the same material:

- `agents/GLOBAL.md` — the absolute rules, the Manor View freeze and the common FAIL causes
- `agents/lessons/*.md` — surface lessons, read by trigger
- `PROJECT_STATUS.md` and `docs/PRIORITY_SURFACES.md`
- `docs/00-INDEX.md` and the surface docs

Vendor-specific mechanics stay in vendor entry files and never hold rules:

- Claude Code: `CLAUDE.md`, `BOOTSTRAP.md`, `.claude-session-init.sh`, fleet Anthropic keys
- Grok: `BOT.md`, the owner's Grok project instruction, approved Desktop1 tools
- Gemini: `GEMINI.md`, `.gemini/settings.json`

Rules change only in `agents/GLOBAL.md`. When editing product rules, write "agents must" rather than "Claude must"; keep "Claude Code must" only for fleet mechanics.

## How each AI loads the rules

- Claude Code loads `CLAUDE.md` automatically, which points at `AGENTS.md` and runs the bootstrap.
- Grok has no native repo file loading. The owner's Grok project instruction says: "At session start read BOT.md and AGENTS.md from github.com/Grotap-AI/grotap-agents master."
- Gemini CLI loads `GEMINI.md` natively. `.gemini/settings.json` also adds `AGENTS.md` to its context, and `GEMINI.md` imports `AGENTS.md`.
- Codex and Cursor read `AGENTS.md` natively.

## Brand placement

| Surface | What to say |
|---|---|
| Owner chat on this PC | Bot (Grok Bot) or Gemini, as the owner's co-pilot |
| Pipeline, fleet boxes, case dispatch | Claude Code, or the named team and model |
| Product (Grotap Apps, Grotap AI Agents) | Grotap stays the customer brand; internal AI helpers are named by role |
| Bookmarks | Keep `DocsforClaude/` for Claude operator links; put other AI entry docs beside it or under `docs/05-agents/` |

Team Hub and support copy that implies a single AI should name the roles when describing how the platform is built and managed.

## Doc map

| File | Purpose |
|---|---|
| `AGENTS.md` | Shared entry for every AI |
| `agents/GLOBAL.md` | The constitution |
| `BOT.md` | Grok mechanics |
| `GEMINI.md`, `.gemini/settings.json` | Gemini mechanics |
| `CLAUDE.md`, `BOOTSTRAP.md` | Claude Code mechanics |
| `platform/AGENTS.md` | App repo entry; points back to this repo |
| `platform/BOT.md`, `platform/GEMINI.md` | App repo pointers |
| `docs/05-agents/owner-ai-teammates.md` | This file |
| `docs/05-agents/agent-assignment-design.md` | Official agent assignment design |

## Operating defaults

1. Pipeline first still applies. Substantive product changes go to the fleet; Bot and Gemini plan and prepare with the owner unless the owner assigns them the local build.
2. The Manor View go-live freeze and the priority surfaces apply to every AI the same way.
3. Secrets live in Doppler only. Never paste a secret value into any AI's chat.
4. Git discipline is the same for all: `master`, no `git add -A`, explicit paths, worktrees for multi-session work.

## Optional later: other AIs inside the fleet

If Grok, Gemini or another model should execute pipeline cases:

1. Route it through the assignment layer described in `docs/05-agents/agent-assignment-design.md`.
2. Verify model IDs with a live completion from each pool box's egress region before registering.
3. Keep the owner co-pilot role documented separately from executor lanes so owner-side help and fleet execution are never confused.

Until that is provisioned, Bot and Gemini stay owner-side only.

## Adoption checklist

- [x] `AGENTS.md` at the root of both repos
- [x] `BOT.md` at `C:\1Claude\` and the `platform/BOT.md` pointer
- [x] `GEMINI.md` and `.gemini/settings.json` in both repos
- [x] This page and the agent assignment design linked from `docs/00-INDEX.md`
- [ ] Owner: set the Grok project instruction to "At session start read BOT.md and AGENTS.md from github.com/Grotap-AI/grotap-agents master."
- [ ] Owner: start Gemini CLI from `C:\1Claude` or `C:\1Claude\platform` so it picks up `GEMINI.md` and `.gemini/settings.json`
- [ ] Optional: bookmark the AI entry docs beside `DocsforClaude/`
- [ ] Optional: Team Hub copy names each AI role
- [ ] Optional: executor lane for other models, region-verified
