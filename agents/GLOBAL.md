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
- **Stay in task scope — do NOT run `npm install`, edit `package.json`/lockfiles, or bump a dependency version unless the task IS explicitly a dependency upgrade.** An unrequested dep bump is an unreviewed platform-wide risk and derails the task (you burn the run touching deps instead of the actual files).
- **Schema rename/move on an EXISTING tenant → use `ALTER SCHEMA old RENAME TO new` (guarded by `to_regnamespace`), then re-GRANT app_user (USAGE+DML+ALTER DEFAULT PRIVILEGES). NEVER re-`CREATE` the schema — that leaves live data stranded in the old one.** Order rename migration BEFORE the create/alter migrations so existing tenants rename-then-noop and fresh tenants create directly.
- **Rename/refactor task → before push, `git grep -nE "<old-identifier>"` MUST return zero (minus intended compat shims/redirects), AND `tsc --noEmit` + `py_compile` pass.** Also update the app-catalog slug/name seed (`seed_apps.sql`, `seed_brands_apps.sql`, `control_plane.py`) — a rename that leaves the old slug is not done.
- **App schema migrations live at repo-root `migrations/apps/<slug>/vNNN_*.sql`** — NOT `backend/migrations/apps/`. The appSchemaProvision worker reads the repo-root tree; a migration placed under `backend/` is invisible to provisioning even if listed in `phase5_app_schema_migrations.sql`.
- **RLS tenant-isolation policies MUST use `current_setting('app.current_tenant_id')::uuid`** — NOT `app.tenant_id` or any other name. That is the GUC `tenant_db.py` sets per-connection; a policy keyed on a different GUC silently returns ZERO rows on RLS-enforced (non-owner) tenants while appearing to work on owner-URL tenants. Match the existing tables' policy verbatim.
- **Frontend + backend built in separate runs → PROVE the wire contract, don't assume it.** Before done: hit the real endpoint and diff field names/shapes/enum casing against the TS types (ScanTap shipped `session_id/device_name/record_id`+nested `data` vs a UI expecting `id/device`+flat rows → every click 500'd on `/scans/undefined`; UI sent `'Reviewed'` vs lowercase DB CHECK → bulk status 100% broken). Map DB rows→UI shape in ONE api layer, never per-page.
- **Any endpoint that can return unbounded rows MUST paginate (limit/offset + stable ORDER BY tie-breaker) BEFORE it ships.** An unpaginated list endpoint "works" in dev and then returns 58MB/500k rows in prod and crashes the browser tab. Grids: infinite scroll + per-column server-side filters; escape ILIKE metachars (`% _ \`) in every user-supplied pattern.
- **App slugs: NEVER guess — verify against the `apps` table (`SELECT slug, name FROM apps`) before writing any slug→app mapping, and copy slug facts stated in the task VERBATIM.** The Pipeline app is slug `pipeline` (📋); `agent-pipeline` (⚡) is a DIFFERENT app; `document-upload` displays as "AI Knowledge Base". A release-notes build mapped pipeline→agent-pipeline despite the task stating the trap explicitly — wrong icon + wrong app attribution shipped to review.
- **Any state machine that marks work FAILED must also release/revert what that work claimed — in the SAME transaction.** Marking a `pipeline_dispatch_log` row failed while leaving its case at `planning` orphaned 32 cases for 2 weeks (auto-assign only selects `plan_approved`, so nothing ever retried them). When you write a failure path, ask: what did the happy path claim (status, slot, lock, row) and who un-claims it on this branch? If the answer is "nobody", the failure is a leak.

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

## Dispatch — ONCE DAILY at High Noon (12:00 UTC) — changed 2026-06-28
**The old "24/7, never idle" policy is RETIRED.** Per the platform owner (2026-06-28), pipeline
work + agent assignment run **once a day at 12:00 UTC**, NOT continuously. Do NOT restart
`continuous-dispatch.sh` or any always-on dispatch loop/systemd service.
- Scheduled: agent-06 root cron `auto_dispatch_dependents.py` at `0 12 * * *`; backend
  `pipeline_automation` row anchored to 12:00 UTC daily (interval_hours=24).
- Manual one-off dispatch is still fine when a human asks:
```bash
bash agents/dispatch.sh <task.md> <server-ip> <session>   # manual
bash agents/dispatch-execute.sh <task.md> <session>       # auto-route (most free slots)
bash agents/server-status.sh                              # check slots/load
```
Priority within a run: `pending/` first, then `active/` backlog, lowest ID first. Verify tmux sessions after dispatch.

## Coding Pilot (CODING_PILOT env flag)
Open-weight lane (qwen-2.5-coder-32b via OpenRouter) runs **instead of Claude** for `simple` tasks
when `CODING_PILOT=1` is set on the dispatch server (unset by default — never enable without owner approval).
- **Never piloted:** P0/P1 priority, medium/complex tasks, or runs over the 2/day cap per server.
- **Gate:** after pilot commits, `tsc --noEmit` (frontend/agent-worker/orchestrator) + `py_compile` must
  pass; any gate fail → reset worktree + automatic Claude fallback.
- **Telemetry:** pilot runs → `service=fleet-pilot`; fallback Claude runs → `meta.pilot_fallback=true`.
  Pass rate: `fleet-pilot ok runs ÷ (fleet-pilot runs + pilot_fallback runs)`.
- **To disable:** `unset CODING_PILOT` or set to `0`. No code change needed.
- Pilot window: ≤20 cases or 2 weeks; success bar ≥70% gate-pass AND ≥90% cost reduction vs Sonnet.

## Code Review
```bash
/codex:review                    # pre-commit — run before every commit
./agents/review-pipeline.sh <branch> && ./agents/collect-reviews.sh --wait <branch>
```
ANY reviewer FAIL = branch blocked. No exceptions. Codex pre-commit review is mandatory but separate from Rule 8 pipeline.

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
| 7 | **ONE app changed at once = ONE branch, built in sequence.** Do NOT fan a single-app change into many parallel branches — they touch the same files, collide, and create merge churn for zero isolation benefit. Only use separate branches for genuinely independent work (different apps/subsystems). Coupled steps stack on the same branch so each starts from the latest state. |
| 8 | **Stage every NEW file you create — explicitly, by name — and verify with `git status` before you finish.** A pushed branch that imports/references a module you created but never committed crashes the whole backend on startup (`ModuleNotFoundError`). The runner now runs `git add -A` as a safety net (respecting `.gitignore`), but do NOT rely on it — new files are your responsibility. This is the #1 cause of broken half-merged branches. |
