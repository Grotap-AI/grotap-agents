# CLAUDE.md — grotap Agent Project
# This file is loaded automatically by Claude Code at every session start.

## Mandatory Session Bootstrap

At the start of EVERY session, before any other work:

1. Run `./.claude-session-init.sh` to sync from GitHub and validate MD structure
2. Read `BOOTSTRAP.md` for the full 6-step initialization protocol

Do not skip this on "quick" sessions — there are none.

## Repos

| Repo | Purpose | Local Path |
|---|---|---|
| `grotap-agents` | Agent bootstrap architecture | `C:\1Claude\` |
| `grotap-platform-docs` | Platform documentation (remote only, last push 2026-07-05; NOT cloned — working docs live in `C:\1Claude\docs\` inside this repo) | — |
| `grotap-platform` | Application code | `C:\1Claude\platform\` |

## Rules

Full rules are in `agents/GLOBAL.md`. The 8 absolute rules are enforced on every task.

## Manor View go-live — IN FORCE through 2026-11-13 (owner 2026-10-11)

First customer: Manor View Farms. Soft go-live 2026-10-26. Hard go-live 2026-11-13. Until that hard go-live is over, work only ScanTap platform app, ScanTap Setup, ScanTap Mobile, ScanTap Mobile sister apps, Print Cloud Setup, Print Cloud Labels, and Vendor Avail & Inventory Planning. All other areas are paused. The same rule is in `agents/GLOBAL.md`. The map is `docs/PRIORITY_SURFACES.md`.

## Default Execution — PIPELINE-FIRST

For any substantive change, the DEFAULT is to route it through the pipeline / agent fleet (plan → prompt
the owner → dispatch → review + teach the machine), NOT to build it myself — dogfooding the fleet makes it
smarter faster. Full rule + workflow in `platform/CLAUDE.md` ("Default Execution — PIPELINE-FIRST").
I keep only the review gate and owner-approved irreversible ops (live migrations, data loads).
