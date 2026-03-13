# agents/GLOBAL.md — Load order: GLOBAL.md → MODULE.md → ROLE.md → handoff.md
# Max 200 lines enforced by pre-commit hook.

## Platform
grotap — multi-tenant AI-powered SaaS. Every feature = discrete app. Tenants subscribe to apps.
Code: `platform/` | Docs: `docs/` | Tasks: `agents/tasks/`

## Stack
| Layer | Tech | Location |
|---|---|---|
| Frontend | React + Vercel | `platform/frontend/` |
| Backend | FastAPI + Railway | `platform/backend/` |
| Auth | WorkOS JWT | `app/providers/workos.py` |
| Database | Neon Postgres (db-per-tenant) | control: `green-rice-76766370` |
| Knowledge | PageIndex (reasoning-based) | `app/providers/pageindex.py` |
| Jobs | INNGEST | `platform/agent-worker/` |
| Agents | LangGraph + LangSmith (TS only) | `platform/agent-worker/` |
| Storage | Cloudflare R2 → PageIndex | `app/providers/r2.py` |
| Billing | Stripe metering | `app/providers/stripe.py` |
| Mobile | Expo MCP | `platform/mobile/` |
| Cobrowse | Cobrowse.IO | `lib/cobrowse.ts` |
| Secret Scan | GitGuardian MCP | compliance-checker node |

## ⚠ Common FAIL Causes — Check Before Committing
- Unused TS imports → `noUnusedLocals: true` → build error. Remove them.
- `request.state.tenant_id` → AttributeError → 500. Use `request.state.organization_id`.
- `RAILWAY_TOKEN` (wrong) — use `RAILWAY_API_TOKEN` for account tokens.
- UPDATE missing `session_id` scope from its SELECT → data leak.
- Status fields without explicit allowlist validation → security hole.
- `pipeline_cases` tenant column is `org_id` NOT `organization_id`.
- JSONB: `->>` for text comparison; `->` returns JSONB (type mismatch in WHERE).
- UNIQUE constraint with COALESCE → invalid Postgres. Use `CREATE UNIQUE INDEX`.
- `| head -4` in scripts → use `| head -n 4`.

## ⛔ Absolute Rules — All Agents, No Exceptions
| # | Rule |
|---|---|
| 1 | **DOPPLER ONLY** — No `.env` in CI, no GitHub secrets (except `DOPPLER_SERVICE_TOKEN`). Local: `doppler run -- <cmd>`. CI: `doppler run --` injects all secrets. Update secrets in Doppler (`grotap` prd/dev). NEVER tell human to update GitHub secrets. |
| 2 | **NO PYTHON FOR AGENTS** — TypeScript/JS only. Python = FastAPI backend only. |
| 3 | **NO DIRECT 3RD-PARTY CALLS** — All SDK calls via `app/providers/` wrappers. |
| 4 | **NO SHARED TENANT DATA** — Every DB query scoped to `tenant_id`. No cross-tenant reads. |
| 5 | **NO SHARED DB SCHEMAS** — Neon database-per-tenant. Never row-level separation. |
| 6 | **NO SKIPPING COMPLIANCE** — GitGuardian MCP + compliance node before every deploy. |
| 7 | **NO VECTOR EMBEDDINGS** — PageIndex reasoning-based retrieval only. No pgvector. |
| 8 | **NO MERGE WITHOUT 4-REVIEWER SIGN-OFF** — Build Validator + Logic + Security + Perf = all PASS. Run `./agents/review-pipeline.sh <branch>` then `./agents/collect-reviews.sh --wait <branch>`. |
| 9 | **AppShell + COBROWSE MANDATORY** — All apps render `AppShell`. Never remove Cobrowse components. Never call Cobrowse SDK directly — use `lib/cobrowse.ts`. |

## Key IDs
- Control plane Neon: `green-rice-76766370`
- Grotap tenant Neon: `proud-union-74070434` / ID: `c7d02593-955c-4ff4-8117-3b2bb267f518`
- Railway project: `f9bf333c-f929-413e-a95c-7923e10b5777`

## Agent Servers
| Server | IP | Roles |
|---|---|---|
| agent-01 | 5.161.189.143 | Execute (primary) |
| agent-02 | 5.161.74.39 | Intake, Triage, Security Reviewer; overflow exec |
| agent-03 | 5.161.81.193 | Planner, Fix/Logic/Policy/Perf Reviewer; overflow exec |
| agent-04 | 178.156.222.220 | Execute (primary), Change Reviewer, Build Validator |
| agent-05 | 5.161.73.195 | Pipeline Detail, Audit, Mobile; overflow exec |
| agent-06 | 5.78.178.81 | **Deploy only — 0 exec slots. Never dispatch tasks here.** |
| agent-07 | 89.167.66.105 | Execute (primary) |
| agent-08 | 77.42.42.213 | **Dispatch Coordinator** + Execute (2 slots) |
| agent-09 | 46.62.184.50 | Execute (primary) |
| agent-10 | 46.62.184.52 | Execute (primary) |

SSH: always `ssh agent-NN` aliases. Never raw IP. Key: `~/.ssh/grotap_agents`. agent-01/08: `User agent`. All others: `User root`.
agent-08: systemd services `grotap-dispatch` + `grotap-watchdog` — both must always run. Max 3 tasks/server via worktrees.

## Dispatch — 24/7, Never Idle
```bash
bash agents/dispatch.sh <task.md> <server-ip> <session>   # manual
bash agents/dispatch-execute.sh <task.md> <session>       # auto-route (most free slots)
bash agents/server-status.sh                              # check slots/load
```
Priority: `pending/` first, then `active/` backlog, lowest ID first. Verify tmux sessions after dispatch.

## Code Review
```bash
./agents/review-pipeline.sh <branch> && ./agents/collect-reviews.sh --wait <branch>
```
ANY reviewer FAIL = branch blocked. No exceptions.

## Deployment
- **Backend (Railway)**: auto-deploys on push to `master` (~2 min)
- **Frontend (Vercel)**: auto-deploys via CI on push to `master` (paths: `frontend/**`)
- Agents on Hetzner: push branch → request merge+deploy from coordinator

## Git Discipline
| # | Rule |
|---|---|
| 1 | Branch is `master` — not `main`. Always `git pull origin master`. |
| 2 | Pull before push — `git pull origin master --rebase` before pushing. |
| 3 | Never `git add -A` or `git add .` — stage specific files only. |
| 4 | Task NOT done until merged to master and deployed. Pushed ≠ done. Reviewed ≠ done. |
| 5 | Task files are gitignored — `agents/tasks/pending/active/done/archive/` not tracked. |
| 6 | Type-check before commit — `cd frontend && npx tsc --noEmit`. Fix errors first. |
