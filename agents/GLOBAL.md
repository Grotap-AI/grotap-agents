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
- **App schema migrations: repo-root `migrations/apps/<slug>/vNNN_*.sql` is canonical, but each file MUST ALSO be copied to `ingestion-worker/migrations/apps/<slug>/`** — appSchemaProvision resolves `__dirname/../../migrations/apps` and the ingestion-worker Dockerfile copies ONLY its own dir; a migration registered in `phase5_app_schema_migrations.sql`/`seed_app_schemas.sql` but absent there = `schema_status='failed'` (ENOENT) on first real subscription. Never `backend/migrations/apps/` either.
- **RLS tenant-isolation policies MUST use `current_setting('app.current_tenant_id')::uuid`** — NOT `app.tenant_id` or any other name. That is the GUC `tenant_db.py` sets per-connection; a policy keyed on a different GUC silently returns ZERO rows on RLS-enforced (non-owner) tenants while appearing to work on owner-URL tenants. Match the existing tables' policy verbatim.
- **Frontend + backend built in separate runs → PROVE the wire contract, don't assume it.** Before done: hit the real endpoint and diff field names/shapes/enum casing against the TS types (ScanTap shipped `session_id/device_name/record_id`+nested `data` vs a UI expecting `id/device`+flat rows → every click 500'd on `/scans/undefined`; UI sent `'Reviewed'` vs lowercase DB CHECK → bulk status 100% broken). Map DB rows→UI shape in ONE api layer, never per-page.
- **Any endpoint that can return unbounded rows MUST paginate (limit/offset + stable ORDER BY tie-breaker) BEFORE it ships.** An unpaginated list endpoint "works" in dev and then returns 58MB/500k rows in prod and crashes the browser tab. Grids: infinite scroll + per-column server-side filters; escape ILIKE metachars (`% _ \`) in every user-supplied pattern.
- **App slugs: NEVER guess — verify against the `apps` table (`SELECT slug, name FROM apps`) before writing any slug→app mapping, and copy slug facts stated in the task VERBATIM.** The Pipeline app is slug `pipeline` (📋); `agent-pipeline` (⚡) is a DIFFERENT app; `document-upload` displays as "AI Knowledge Base". A release-notes build mapped pipeline→agent-pipeline despite the task stating the trap explicitly — wrong icon + wrong app attribution shipped to review.
- **Any state machine that marks work FAILED must also release/revert what that work claimed — in the SAME transaction.** Marking a `pipeline_dispatch_log` row failed while leaving its case at `planning` orphaned 32 cases for 2 weeks (auto-assign only selects `plan_approved`, so nothing ever retried them). When you write a failure path, ask: what did the happy path claim (status, slot, lock, row) and who un-claims it on this branch? If the answer is "nobody", the failure is a leak.
- **Every UI action must call an endpoint that EXISTS (on master or in YOUR branch) — `git grep` the backend router for each path before done.** Two Loop Engine branches shipped New/Edit/Delete/Run buttons against seven endpoints that existed nowhere → every action 404s; both branches were rejected at review. If the task is UI-only and the endpoint is missing, extending the router is in scope — a dead button is not a deliverable.
- **A DELETE feature covers EVERY delete path, and deletes carry the same org/tenant scope as their SELECTs.** A retention-cascade branch fixed bulk-delete but missed the HI Dismiss single-delete (orphaned rows + leaked R2 objects) and rewrote a deps delete with no org scope (cross-org edge deletion). Grep for every `DELETE FROM <table>`/router delete path touching the entity before calling cascade work done.
- **Security gates FAIL CLOSED in production when their config is missing.** A virus-scan gate marked uploads 'clean' when `VIRUSTOTAL_API_KEY` was unset; webhook sig-verify returned True when the secret was unset. Dev fallback is fine, but gate it on env: missing key in prd = block + log critical, never silently allow.
- **Real WorkOS access tokens carry NO `email` claim — our HS256 test JWTs DO.** Any gate keyed on `request.state.user_email` passes Playwright but silently fails for real sessions (AL5 scoping emptied the HI holds list for the owner while /stats counted 49). Middleware now backfills email (cached user_id→email lookup), so `user_email` is reliable — but when you ADD an auth/scoping gate, also probe it with a JWT that OMITS `email` before calling it done.
- **`tenants.tenant_id` is UUID; `tenant_users.tenant_id` is TEXT — always `str(tenant["tenant_id"])` before passing to queries/helpers.** A webhook reconciliation branch passed the UUID unconverted → asyncpg DataError on EVERY event, swallowed by a blanket except → the whole feature was a silent no-op. And mock tests used string fixtures so they couldn't catch it: fixture types must match the REAL return types of the helpers you mock.
- **Webhook handlers: verify signature, be idempotent, and return non-2xx on transient failure.** Senders (WorkOS, Stripe) retry only non-2xx; `except Exception: log; return 200` permanently drops the event with no repair sweep. Also assume events arrive out of order and duplicated — a late `updated` after `deleted` must not resurrect a removed row (dedup on event id or guard on status).
- **A connect flow must request the permissions its CONSUMER needs — trace the whole feature, not your case.** OAuth connect shipped `gmail.readonly` while the executor case (same feature, different branch) trashes/labels — every connected mailbox permanently unable to run the bundle. When a flow is split across cases, verify the handshake artifact (scope, token, schema, enum) against what the downstream case DOES with it.
- **Global `body` CSS is DARK (`background:#0f0f0f; color:#fff`) — every light-surface element must set its OWN text color, and e2e must assert VISIBILITY, not DOM presence.** ScanTap Inventory Items shipped a `td` style with no `color:` → white text on a white grid; data loaded (200s, 23k rows) but the screen read as "never loads" for weeks, and Playwright passed because rows existed in the DOM. When you build a table/card on a light background, set `color` explicitly (grids use `#374151`), and add a computed-style luminance check to the e2e (see scantap-data-grids.spec.ts "Inventory Items").
- **"Most recent N" derived from a list endpoint: verify the endpoint's ORDER BY delivers recency — both the sort AND the LIMIT window.** HI recent-answers chips walked `GET /human-intervention/?status=resolved&limit=50` taking the first 5 distinct resolutions, but that endpoint orders priority-then-`created_at ASC` — the walk collected the OLDEST answers, and with >50 resolved rows the recent ones aren't even in the returned page, so client-side sorting can't fix it. Read the producing query before deriving recency; if ordering doesn't match, add an allowlisted order param (e.g. `order=resolved_desc`, with a stable tie-breaker) — never sort a wrongly-windowed page.
- **Before filtering/querying a 3rd-party system by a key, prove WE emit that key — CURRENT format, CURRENT master.** A LangSmith proxy filtered runs on `metadata.case_id` (orchestrator only sets `thread_id`) → `[]` forever; the fix-forward then matched bare `case_id` while master had moved to `thread_id = case_id:dispatch_id` → `[]` again, invented an undocumented filter DSL form, and passed `project_name` where the API takes `session: [<uuid>]`. Read the producing code on master the day you build, and copy request/response shapes from the provider's current docs (cite the URL in a comment) — never from memory.
- **Postgres/asyncpg: an error inside an open transaction POISONS it — catching the exception in Python does not recover it.** A cascade helper caught `UndefinedTableError` per child table inside one `conn.transaction()`; the next statement raises `InFailedSQLTransactionError` and the whole delete 500s exactly when a lazily-created table is missing. For optional tables: check `to_regclass('<table>')` first (repo pattern, see c695e06e) or wrap each statement in a nested `async with conn.transaction():` (savepoint).
- **A stated invariant must be ENFORCED in the write path, not just documented + backfilled.** "Exactly one owner per tenant" shipped as a backfill + docstring while the login role-sync `COALESCE` could demote the owner on next login (reverting the backfill) or mint a second one. Every writer that can violate the invariant must guard it (CASE guard + partial unique index backstop, e.g. `UNIQUE ON (tenant_id) WHERE role='owner'`), and tests must include the violating writer path — a test that codifies the bug is worse than none.
- **"Private"/visibility features: enumerate EVERY read path that returns the entity before calling it done — `git grep -n "FROM <table>" backend/app/routers/`.** Private apps shipped filtered in one router while the legacy `GET /apps` catalog and `GET /brands/{id}/apps` leaked them platform-wide. And scope visibility to the OWNING TENANT (creator_tenant_id), not the creator user — user-scoping hides a company's private app from the company and follows the creator across tenants.

## ⛔ Absolute Rules — All Agents, No Exceptions
| # | Rule |
|---|---|
| 1 | **DOPPLER ONLY** — No `.env` in CI, no GitHub secrets (except `DOPPLER_SERVICE_TOKEN`). Local: `doppler run -- <cmd>`. CI: `doppler run --` injects all secrets. Update secrets in Doppler (`grotap` prd/dev). NEVER tell human to update GitHub secrets. **NEVER put secret VALUES in chat/prompts/task files/logs/commits — transcripts persist.** When a human must supply a secret, direct them to the Doppler dashboard or a terminal OUTSIDE any AI session; never ask them to paste it to an agent. |
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
Git auth on exec servers (02–06): `credential.helper = /home/agent/bin/git-credential-doppler` (fetches `GITHUB_TOKEN` from Doppler per call — survives token rotation; installed 2026-07-03 after the 6/25 rotation silently broke `$GH_PUSH_TOKEN`-based auth fleet-wide for 8 days). NEVER set a static token in `~/.env`; if git auth fails, check `doppler me` works as the `agent` user first.

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

## Review-Sweep Lessons (57-branch gate, 2026-07-04)
| # | Lesson |
|---|---|
| 1 | **Cross-case contracts are exact:** before writing a consumer of a sibling case's schema, `grep` its migration for the REAL column names/types. A webhook UPDATEd invented columns (`stripe_account_id`) while the sibling created `stripe_connect_account_id` — silent no-op forever. Same for shared TS shapes across split cases. |
| 2 | **Never swallow schema errors.** `try/except: log-and-continue` around DB writes hides missing-column bugs from every reviewer. Let unexpected DB errors surface at ERROR level. |
| 3 | **Billing idempotency keys are deterministic, never `uuid4()` per call** — a fresh key defeats Stripe retry-safety and double-bills. Derive from stable ids (`account-{brand_id}`, `invoice-{brand_id}-{period}`). |
| 4 | **Branch from CURRENT master and always push YOUR case branch.** Stale bases turned a 1-file utility into a 54-file diff; 7 coalesced cases pushed no per-case branch, making review/revert impossible. |
| 5 | **One owner per hot file / one case per enforcement surface.** Two agents built duplicate OAuth in the same router with different secret names; three branches each partially rewrote app-visibility filters, leaving subscribe/vote leaks. Visibility/authz changes must cover EVERY read+write path (list, my-apps, subscribe, request, vote, pricing, brands) in ONE case. |
| 6 | **Third-party callback endpoints (OAuth, webhooks) go in PUBLIC_PATHS** — the caller has no JWT; shipping the callback without it 401s the whole flow. |
| 7 | **A new unique/invariant index ships WITH a dedupe migration.** `CREATE UNIQUE INDEX` at startup assumes clean data; promote-only backfills don't clean duplicates and the index throws on boot. |
| 8 | **Appending to a shared init hunk (control_plane.py initialize etc.)? Use your OWN `pool.execute` block** and don't re-ADD columns a sibling already added — same-anchor appends are the #1 merge-conflict source. |
| 9 | **Verify referenced modules/pages exist before wiring routes** (a route importing a nonexistent page breaks the whole frontend build), and check master first before re-adding "foundation" work that already landed. |

## Boot-Time Failure Lessons (2026-07-04 outage)
| # | Lesson |
|---|---|
| 1 | **`py_compile` does NOT catch FastAPI import-time crashes.** Before pushing ANY backend change, boot-test the app: `python -c "import app.main"` (dummy env vars for required settings). A router that compiles can still assert during route registration and take down every deploy — e.g. `from __future__ import annotations` + `status_code=204` + `-> None` return annotation asserts "204 must not have a response body" on FastAPI 0.115. With a bodyless status code, pass `response_model=None` explicitly. |
| 2 | **Orchestrator boot must NEVER re-enter threads paused at an interrupt gate** (`next=['human_gate']`). Those are awaiting a human decision, not crashed — re-running them re-executes finished work and destroys the pause state (8 approved-review cases were marked failed this way). |
| 3 | **Do not open unbounded concurrent SSH connections to one host.** sshd MaxStartups drops the stampede and every 60s ctrl command times out. Reuse a pooled connection per host, serialize control commands, retry with backoff. |
| 4 | **Verification/gate-shaped tasks (no code expected) must report success without commits** — "no commits produced" is only a failure for build tasks. Say so explicitly in the task file until the framework supports it. |

## Review-Sweep Lessons (2026-07-04 gate #2)
| # | Lesson |
|---|---|
| 1 | **`SELECT SUM(...) ... FOR UPDATE` is invalid** — Postgres errors "FOR UPDATE is not allowed with aggregate functions", so the endpoint fails 100%. To make read-accrued-then-pay atomic, lock the PARENT row (`SELECT ... FROM brands WHERE id=$1 FOR UPDATE`) or take an advisory lock — never FOR UPDATE an aggregate. (A row lock on existing payouts also does NOT block a concurrent INSERT of a new one.) |
| 2 | **Dynamic UPDATE SET builders: don't hardcode a column AND loop it.** Seeding the SET list with `status='paid'`/`paid_at=NOW()` then iterating a fields dict that still contains `status` emits `SET status='paid', ..., status=$N` → "multiple assignments to same column". Exclude hardcoded columns from the loop. |
| 3 | **Importing a helper/component is NOT wiring it — grep for a real call site before "done".** `teardownPreviewByCase` was imported into finalize.ts and never called (containers leaked); an Export button set state but no `<ExportModal>` was ever rendered (dead button). Neither fails typecheck (orchestrator has no `noUnusedLocals`; a set-but-unread modal still compiles), yet the feature ships broken. |
| 4 | **"Paused at the human gate" detection keys on the interrupt node, not run activity.** Use `snapshot.next?.includes('human_gate')`, NEVER `next.length>0` — the latter is true for EVERY non-terminal run, so an Approve/Resume button fires a second concurrent `invoke(Command({resume}))` on a live thread (re-entry race; see Boot-Time #2). |
| 5 | **PUBLIC_PATHS covers ALL non-JWT auth, not just OAuth/webhooks.** Any endpoint authed by a shared-secret header (internal RPC like `/telemetry/pilot-rl-check` with `X-Telemetry-Secret`) must be in PUBLIC_PATHS — TenantAuthMiddleware 401s it before the route runs, and a caller that parses the 401 body silently mis-defaults (the pilot rate-limiter became an unconditional kill-switch). |

## Review-Sweep Lessons (2026-07-04 gate #3)
| # | Lesson |
|---|---|
| 1 | **Actually RUN `tsc --noEmit`; "it compiles" is not a claim, it's a command.** An Excel-export page shipped 4×TS2352 by casting typed row arrays straight to `Record<string,unknown>[]` — `ReportRow[] as Record<string,unknown>[]` fails because the interface has no string index signature. Either add `[key: string]: unknown` to the row type or cast via `as unknown as Record<string,unknown>[]`, and run the frontend typecheck before submitting. A whole batch push was blocked and the branch reverted for this. |
| 2 | **Grep the real migration for schema-qualified table + column names before writing ANY SQL — don't invent columns.** A loop-scheduler queried `loops` (real: `loop_engine.loops`), `id` (real: `loop_id`), `cron` (real: `cron_expr`), and a `next_run_at`/`timezone` that don't exist on the table at all — so it was a permanent no-op. If your feature needs a column that isn't there, ship the idempotent `ADD COLUMN IF NOT EXISTS` + backfill migration FIRST, then reference it. (Compounds with "never swallow schema errors" — a blanket `catch {}` hid every one of these as "migration not applied".) |
| 3 | **Rebasing onto a router master has since HARDENED must preserve its auth guards — never reintroduce an endpoint version missing a `Depends(require_company_role(...))` master already added.** A tenant-users branch built on a stale base would have dropped the admin-only guard on member removal (privilege-escalation regression) and rel_types persistence. Also don't add a parallel provider wrapper for something that exists — `workos_provider.delete_organization_membership()` already did the list-then-delete a new `remove_membership()` duplicated. |

## Review-Sweep Lessons (2026-07-05 gate #4)
| # | Lesson |
|---|---|
| 1 | **Control-plane schema changes go ONLY in `backend/db/migrations/control_plane/vNNN_*.sql` (SCA001).** NEVER add inline DDL to `control_plane.py`/routers — CI guard `backend/scripts/check_no_inline_ddl.py` fails on any `CREATE/ALTER TABLE`, `CREATE INDEX/TYPE/VIEW/SEQUENCE`, `DROP TABLE` in non-allowlisted `backend/app` files. NEVER use the retired `backend/migrations/*.sql` path or `backend/migrate.sh` (not wired to `migration_runner` → tables silently never created in prod). 5 branches built pre-SCA001 (agent_team_templates/purchases, brand_type, ai_support_sessions, tenant_billing) were all rejected for this. Pick the next free `vNNN`, keep it idempotent (`IF NOT EXISTS`/`DO … EXCEPTION duplicate_object`); files apply one-per-txn in filename order, so order FK children after parents. |
| 2 | **Rebase onto latest master and NEVER commit conflict markers.** A server-connections branch committed literal `<<<<<<< Updated upstream`/`=======`/`>>>>>>> Stashed changes` in `main.py` from a botched `git stash pop` — `py_compile` fails at that line, taking down every deploy, and `git merge-tree` reports "clean" (committed content, not a live conflict → false green). Before submitting: `grep -rn '^<<<<<<<\|^>>>>>>>' ` your diff AND run `python3 -m py_compile` / `tsc --noEmit`. Also dedupe: don't `include_router(x)` that master already registers. |
| 3 | **Every JSONB bind param needs `json.dumps(...)` + a `$N::jsonb` cast** (no jsonb type-codec is registered). A dual-write ledger passed a raw `dict` as `$6` into a JSONB column — dormant only because callers passed `None`; it breaks the first time a dict is sent. Canonical pattern: `... $6::jsonb ...`, value `json.dumps(meta or {})`. |
| 4 | **Never DROP/CREATE a DB role to rotate its credentials — `ALTER ROLE x WITH PASSWORD` instead.** Once a role is the target of RLS policies or holds grants/default-privileges, `DROP ROLE` always fails ("some objects depend on it"). `backfill_rls_roles.py --force` was unrunnable on every provisioned tenant for this (CASE-20260705-8C58D1). Grants/policies are idempotently re-applied; only the password needs rotating. |
| 5 | **Proof/verification scripts that EXECUTE SQL must assert a non-prod target before running.** During SCA003 a "branch-only" proof applied v002 to live prod (harmless only by luck + idempotence; the checksum then froze the file). Use `backend/scripts/_lib_guard.py::assert_not_prod(dsn)` in any script that applies migration files; a file recorded in prod's `schema_migrations` ledger is FROZEN — never edit it, ship the fix as the next `vNNN`. |
| 6 | **A fail-closed check on the consumer side requires closing EVERY producer path in the same change.** SCA002 made middleware 503 on tenants without `neon_app_database_url` while three provisioning paths could still create such tenants (org auto-provision created them with NO role at all → every new company dead-on-arrival). When you add a "reject invalid state" gate, grep for all writers of that state and make them provision-or-cleanup (delete the orphaned Neon project on failure), not warn-and-continue. |

## Review-Sweep Lessons (2026-07-05 gate #5)
| # | Lesson |
|---|---|
| 1 | **WorkOS `organization_id` is a TEXT string (`org_01...`), NEVER a UUID.** Don't declare it `UUID` in DDL and never `uuid.UUID(org_id)` it — that 500s on every real request (test JWTs may pass a UUID-shaped org, masking it). Same for user ids (`user_01...`). |
| 2 | **Never piggyback new event types on an existing BroadcastChannel.** Existing listeners use bare `onmessage = () => refetch()` with no type filter, so your event triggers their handler in every window. New event domain → new dedicated channel (e.g. `grotap_cobrowse`, not `grotap_subscriptions`). |
| 3 | **No tenant-specific seed rows in shared migrations.** A migration under `migrations/apps/<slug>/` runs on EVERY tenant that provisions the app — a hardcoded grotap `tenant_id` INSERT pollutes other tenants' DBs. Seed data goes in an ad-hoc script or a tenant-conditional block. |
| 4 | **Tests must import the production code they verify — never reimplement the formula in the test file** (drift is then undetectable), and never assert tautologies like `assertEqual(f(x), round(x, n))` where both sides are the same expression. If the logic isn't importable, extract it into a helper first; that refactor IS the task. |
