# agents/GLOBAL.md
# Universal context — loaded first by every agent session on every server.
# Load order: GLOBAL.md → MODULE.md → ROLE.md → handoff.md
# Max 200 lines enforced by pre-commit hook.

## Platform
grotap — multi-tenant AI-powered SaaS platform.
Every feature is a discrete app. Tenants subscribe to apps.
Code: `platform/` | Docs: `docs/` | Tasks: `agents/tasks/`

## Stack
| Layer | Tech | Location |
|---|---|---|
| Frontend | React + Vercel | `platform/frontend/` |
| Backend | FastAPI + Railway | `platform/backend/` |
| Auth | WorkOS — multi-tenant JWT | `app/providers/workos.py` |
| Database | Neon Postgres — database-per-tenant | `green-rice-76766370` (control) |
| Knowledge | PageIndex — reasoning-based retrieval | via `app/providers/pageindex.py` |
| Jobs | INNGEST — durable workflows | `platform/agent-worker/` |
| Agents | LangGraph + LangSmith — TypeScript only | `platform/agent-worker/` |
| Storage | Cloudflare R2 → PageIndex ingestion | via `app/providers/r2.py` |
| Billing | Stripe — per-tenant metering | via `app/providers/stripe.py` |
| Mobile | Expo | via Expo MCP |
| Screen Share | Cobrowse.IO | `lib/cobrowse.ts` wrapper |
| Secret Scan | GitGuardian MCP | compliance-checker node |

## ⛔ ABSOLUTE RULES — ALL AGENTS, NO EXCEPTIONS

| # | Rule |
|---|---|
| 1 | **DOPPLER HOLDS ALL SECRETS** — No `.env`, no hardcoded values. Local: `doppler run -- <cmd>`. Never set tokens inline. |
| 2 | **NO PYTHON FOR AGENTS** — TypeScript/JS only. Python = FastAPI backend only. |
| 3 | **NO DIRECT 3RD-PARTY CALLS** — All SDK calls via vendor wrappers in `app/providers/`. |
| 4 | **NO SHARED TENANT DATA** — Every DB query scoped to `tenant_id`. No cross-tenant reads. |
| 5 | **NO SHARED DATABASE SCHEMAS** — Neon database-per-tenant. Never row-level separation. |
| 6 | **NO SKIPPING COMPLIANCE** — GitGuardian MCP + compliance node before every deploy. |
| 7 | **NO VECTOR EMBEDDINGS FOR RETRIEVAL** — PageIndex reasoning-based retrieval only. |
| 8 | **NO MERGE WITHOUT 4-REVIEWER SIGN-OFF** — All of: Build Validator + Logic + Security + Perf = PASS. |
| 9 | **EVERY APP MUST USE AppShell** — Cobrowse always active. Never call Cobrowse SDK directly. |

## Key IDs
- Control plane Neon: `green-rice-76766370`
- Grotap tenant Neon: `proud-union-74070434`
- Grotap tenant ID: `c7d02593-955c-4ff4-8117-3b2bb267f518`
- Railway project: `f9bf333c-f929-413e-a95c-7923e10b5777`

## Agent Servers
| Server | IP | Primary Roles | Overflow |
|---|---|---|---|
| Agent-01 | `5.161.189.143` | Execute | — |
| Agent-02 | `5.161.74.39` | Intake, Triage, Security Reviewer | Execute |
| Agent-03 | `5.161.81.193` | Planner, Fix/Logic/Policy/Perf Reviewer | Execute |
| Agent-04 | `178.156.222.220` | Execute, Change Reviewer, Rule Enforcer, Build Validator | — |
| Agent-05 | `5.161.73.195` | Pipeline Detail, Audit Filters, Mobile Approvals | Execute |

Overflow = Execute tasks dispatched only when server has free slots. Primary roles always take priority.
Each server supports up to 3 concurrent tasks via git worktrees (isolated working directories).

## Dispatch
```bash
# Manual (specify server IP) — each task gets its own worktree
bash agents/dispatch.sh <task.md> <server-ip> <session-name>
# Auto-route execution (picks server with most free slots — primary first, then overflow)
bash agents/dispatch-execute.sh <task.md> <session-name>
# Check server slots, CPU, memory, load
bash agents/server-status.sh
```

## Code Review Pipeline
```bash
./agents/review-pipeline.sh <branch>
./agents/collect-reviews.sh --wait <branch>
```
ANY reviewer returning FAIL = branch blocked. No exceptions.

## Deployment
- **Backend (Railway)**: auto-deploys on push to `master` (~2 min)
- **Frontend (Vercel)**: requires manual CLI deploy after push:
```bash
VTOKEN=$(doppler secrets get VERCEL_TOKEN --project grotap --config prd --plain)
cd platform/frontend && npx vercel --token "$VTOKEN" --prod --yes
```
Agents on Hetzner servers: push your branch, then request Vercel deploy from coordinator.

## Backend Auth — Critical
FastAPI middleware sets `request.state.organization_id` — NOT `tenant_id`.
`request.state.tenant_id` → AttributeError → 500 on all requests.

## Git Discipline — ALL AGENTS, NO EXCEPTIONS
| # | Rule |
|---|---|
| 1 | **Branch is `master`** — not `main`. Always `git pull origin master`. |
| 2 | **Pull before push** — always `git pull origin master --rebase` (or branch) before pushing. |
| 3 | **Never `git add -A` or `git add .`** — stage specific files only. Wildcard staging picks up unrelated files. |
| 4 | **Always push after commit** — uncommitted or unpushed work is invisible to everyone. A task is not done until pushed. |
| 5 | **Task files are gitignored** — `agents/tasks/pending/`, `active/`, `done/`, `archive/` are NOT tracked. Do not try to `git add` them. |
| 6 | **Type-check before commit** — run `cd frontend && npx tsc --noEmit` for frontend changes. Fix errors before committing. |

## Common FAIL Causes
- Unused TS imports (`noUnusedLocals: true` → build error)
- UPDATE missing `session_id` scope from corresponding SELECT
- Status fields without explicit allowlist validation
- `pipeline_cases` tenant column is `org_id` NOT `organization_id`
- JSONB: `->>` for text comparison, `->` returns JSONB (type mismatch)
- `| head -4` with CLI output → use `| head -n 4`
