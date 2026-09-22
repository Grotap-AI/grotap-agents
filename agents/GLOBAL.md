# agents/GLOBAL.md — Load order: GLOBAL.md then (on demand) SERVERS.md then MODULE.md then ROLE.md then handoff.md
# Keep SMALL. Ledgers: agents/LESSONS-ARCHIVE.md (never auto-load). FAIL essays: agents/lessons/always-on-fail-detail.md (on demand).

## Platform
grotap — multi-tenant AI SaaS. Every feature = discrete app; tenants subscribe.
Code: `platform/` | Docs: `docs/` | Tasks: `agents/tasks/` | Fleet scripts: platform `agents/*.sh`

## Stack
React+Vercel `platform/frontend/` · FastAPI+Railway `platform/backend/` · WorkOS JWT · Neon Postgres (pooled + FORCE RLS; dedicated = premium) · Inngest + LangGraph/LangSmith TS `platform/agent-worker/` · R2 · Stripe via `app/providers/*` · Expo · OpenReplay `lib/openreplay.ts` · GitGuardian MCP

## Absolute Rules — All Agents, No Exceptions
| # | Rule |
|---|---|
| 1 | **DOPPLER ONLY** — No `.env` in CI; no GitHub secrets except `DOPPLER_SERVICE_TOKEN`. Local: `doppler run -- <cmd>`. Never put secret VALUES in chat/prompts/tasks/logs/commits. |
| 2 | **NO PYTHON FOR AGENTS** — TypeScript/JS only. Python = FastAPI backend only. |
| 3 | **NO DIRECT 3RD-PARTY CALLS** — All SDKs via `app/providers/` wrappers. |
| 4 | **NO CROSS-TENANT DATA** — Every query tenant-scoped. |
| 5 | **TENANT ISOLATION VIA RLS** — FORCE RLS on `current_setting('app.current_tenant_id')::uuid` via `tenant_db.py`. Never bypass/weaken. |
| 6 | **NO SKIPPING COMPLIANCE** — GitGuardian MCP + compliance node before every deploy. |
| 7 | **NO MERGE WITHOUT 4-REVIEWER SIGN-OFF** — Build+Logic+Security+Perf PASS. `./agents/review-pipeline.sh <branch>` then `./agents/collect-reviews.sh --wait <branch>`. |
| 8 | **AppShell MANDATORY** — OpenReplay only via `lib/openreplay.ts`. Cobrowse removed — never restore. |
| 9 | **JEV IS THE SD JUDGE** — When `JEV_ENABLED`, Jev (platform/orchestrator Decisions via OpenRouter; not chat completions) is the only judge/router for assign, done-ship, and monitor. Never LLM-as-judge. Low confidence → `human_review`. Full: platform `docs/JEV_HARNESS.md`. |
| 10 | **AGENTIC EXECUTION SECURITY** — Agents propose; platform APIs are source of truth. No admin/commerce write keys on agent boxes to finish the job. Re-verify truth at commit; fail closed. Full: platform `docs/AGENTIC-EXECUTION-SECURITY-PLAN.md`. |
| 11 | **PLAN MD GO-LIVE** — Desktop `*.md` are drafts. Implemented plans live in git (platform `docs/` or this repo’s `docs/`). Must-obey text is a short pointer here; do not load plan novels into prompts. Playbook: `docs/PLAN-GO-LIVE.md`. |

## Common FAIL Causes — SHORT (detail: `agents/lessons/always-on-fail-detail.md`)
- SQL: control-plane DDL only in `backend/db/migrations/control_plane/vNNN_*.sql`; app schemas in BOTH `migrations/apps/<slug>/` and `ingestion-worker/migrations/apps/<slug>/`; never amend applied migrations; asyncpg JSONB=`json.dumps`+`::jsonb`; RLS GUC name exact.
- Auth: `request.state.organization_id`; PUBLIC_PATHS for all non-JWT; fail closed in prd; allowlist paths for file reads.
- Wiring: `include_router` required; prove FE/BE contract on real endpoint; task JSON contract keys are LAW.
- Frontend: AppShell; no dead UI actions; enums match API.
- State/jobs: idempotent webhooks; no poison txn swallow.
- Fleet: no `git add -A`; master not main; task not done until merged+deployed.
- Before commit: Read matching `agents/lessons/*.md` by trigger only — never cat all lessons into the prompt.

## Key IDs
Control Neon `green-rice-76766370` · Grotap tenant Neon `proud-union-74070434` · Railway `f9bf333c-f929-413e-a95c-7923e10b5777`

## Fleet / Dispatch / Review / Deploy
Roster+SSH: `agents/SERVERS.md` (do **not** auto-load into coding prompts).
Dispatch continuous; teams/routing: `agents/SERVERS.md` + platform `agents/config.sh`.
Review: `/codex:review` then Rule 7 pipeline. Deploy: Vercel FE on master; Railway BE gated on green CI.
Git: master; stage named paths only; tsc before commit; one app to one branch.

## Lessons (on-demand only)
| File | When |
|---|---|
| `lessons/decomposition-gate.md` | decompose / review / merge gate / fan-out |
| `lessons/sql-migrations.md` | SQL/migrations/RLS |
| `lessons/wiring-contracts.md` | endpoints/events/contracts |
| `lessons/build-ship.md` | tests/signatures/startup/CI |
| `lessons/frontend.md` | frontend/mobile/UI enums |
| `lessons/auth-security.md` | auth/secrets/fail-closed |
| `lessons/state-jobs.md` | status/webhooks/idempotency |
| `lessons/fleet-ops.md` | dispatch/orchestrator/fleet |
| `lessons/always-on-fail-detail.md` | debugging a FAIL mode in depth |

Append new lessons to matching `lessons/*.md`. NEVER grow this file with incident essays.
