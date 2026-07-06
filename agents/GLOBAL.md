# agents/GLOBAL.md — Load order: GLOBAL.md → SERVERS.md → MODULE.md → ROLE.md → handoff.md
# Max 200 lines enforced by session-init. Dated incident ledgers: agents/LESSONS-ARCHIVE.md (not auto-loaded).

## Platform
grotap — multi-tenant AI-powered SaaS. Every feature = discrete app. Tenants subscribe to apps.
Code: `platform/` | Docs: `docs/` | Tasks: `agents/tasks/` | Fleet scripts: platform repo `agents/*.sh`

## Stack
| Layer | Tech | Location |
|---|---|---|
| Frontend | React + Vercel | `platform/frontend/` |
| Backend | FastAPI + Railway | `platform/backend/` |
| Auth | WorkOS JWT | `app/providers/workos_provider.py` |
| Database | Neon Postgres — pooled shards + FORCE RLS (dedicated project = premium) | control: `green-rice-76766370` |
| Jobs | INNGEST | `platform/agent-worker/` |
| Agents | LangGraph + LangSmith (TS only) | `platform/agent-worker/` |
| Storage | Cloudflare R2 | `app/providers/r2_provider.py` |
| Billing | Stripe metering | `app/providers/stripe_provider.py` |
| Mobile | Expo | `platform/mobile/` |
| Cobrowse | Cobrowse.IO | `frontend/src/lib/cobrowse.ts` |
| Secret Scan | GitGuardian MCP | compliance-checker node |

## ⛔ Absolute Rules — All Agents, No Exceptions
| # | Rule |
|---|---|
| 1 | **DOPPLER ONLY** — No `.env` in CI, no GitHub secrets (except `DOPPLER_SERVICE_TOKEN`). Local: `doppler run -- <cmd>`. Update secrets in Doppler (`grotap` prd/dev). NEVER tell a human to update GitHub secrets. **NEVER put secret VALUES in chat/prompts/task files/logs/commits.** Humans supply secrets via the Doppler dashboard or a terminal OUTSIDE any AI session. |
| 2 | **NO PYTHON FOR AGENTS** — TypeScript/JS only. Python = FastAPI backend only. |
| 3 | **NO DIRECT 3RD-PARTY CALLS** — All SDK calls via `app/providers/` wrappers. |
| 4 | **NO CROSS-TENANT DATA** — Every DB query scoped to the tenant. No cross-tenant reads. |
| 5 | **TENANT ISOLATION VIA RLS** — Default placement is POOLED: tenants share a Neon shard, isolated by FORCE RLS keyed on `current_setting('app.current_tenant_id')::uuid` (set per-connection by `tenant_db.py`). Dedicated Neon project = premium/override path. Never bypass RLS or weaken a policy. |
| 6 | **NO SKIPPING COMPLIANCE** — GitGuardian MCP + compliance node before every deploy. |
| 7 | **NO MERGE WITHOUT 4-REVIEWER SIGN-OFF** — Build Validator + Logic + Security + Perf = all PASS. From platform repo root: `./agents/review-pipeline.sh <branch>` then `./agents/collect-reviews.sh --wait <branch>`. ANY FAIL = branch blocked. |
| 8 | **AppShell + COBROWSE MANDATORY** — All apps render `AppShell`. Never remove Cobrowse components. SDK only via `lib/cobrowse.ts`. |

## ⚠ Common FAIL Causes — Check Before Committing

### SQL & migrations
- Control-plane DDL goes ONLY in `backend/db/migrations/control_plane/vNNN_*.sql` — idempotent, one file per txn, FK children after parents. Never inline DDL in `backend/app` (CI guard blocks it); never the retired `backend/migrations/` path. App schemas: repo-root `migrations/apps/<slug>/vNNN_*.sql` AND copy each file to `ingestion-worker/migrations/apps/<slug>/` (its Docker image only ships its own dir; a registered-but-absent file = `schema_status='failed'` on first subscription).
- Pick the next FREE `vNNN` (grep the dir). Two branches must never both CREATE a table or claim the same number — declare the dependency and let ONE branch own the table's canonical schema.
- Grep the real migration for schema-qualified table + column names before writing SQL — never invent columns. Need a new column? Ship `ADD COLUMN IF NOT EXISTS` + backfill FIRST. Consuming a sibling case's schema? grep ITS migration for the real names.
- A migration recorded in prod's `schema_migrations` is FROZEN — fix forward as the next `vNNN`. Any script that executes SQL as "proof" must `assert_not_prod(dsn)` (`backend/scripts/_lib_guard.py`).
- JSONB binds: `json.dumps(value)` + `$N::jsonb` cast (no codec registered). `->>` for text comparison; `->` returns JSONB.
- `pipeline_cases` tenant column is `org_id`. `tenants.tenant_id` is UUID but `tenant_users.tenant_id` is TEXT — `str()` before passing. WorkOS ids (`org_01…`, `user_01…`) are TEXT — never UUID columns, never `uuid.UUID()`.
- UNIQUE with COALESCE is invalid — `CREATE UNIQUE INDEX`. A new unique/invariant index ships WITH its dedupe migration. Enforce invariants in every write path (CASE guard + partial unique index), not just backfill + docstring.
- Never swallow schema errors (`except: log-and-continue` hides missing columns from every reviewer). asyncpg: an error POISONS the open transaction — `to_regclass('<table>')` checks or nested-transaction savepoints for optional tables.
- Never call `.get()` on asyncpg Records from `pool.fetch/fetchrow` — `dict(r)` first, then `.get()` (banned even though asyncpg 0.29 allows it; recurred in 3BA7FB export service).
- No `SELECT SUM(...) FOR UPDATE` (invalid) — lock the parent row or take an advisory lock. Dynamic UPDATE SET builders: never hardcode a column AND loop it.
- Schema rename on an existing tenant: `ALTER SCHEMA … RENAME` (guard `to_regnamespace`) + re-GRANT app_user — never re-CREATE. Rotate DB role creds via `ALTER ROLE … WITH PASSWORD` — `DROP ROLE` fails once policies/grants depend on it.
- RLS policies keyed EXACTLY on `current_setting('app.current_tenant_id')::uuid` — any other GUC name silently returns zero rows on enforced tenants. No tenant-specific seed rows in shared app migrations (they run on EVERY tenant).
- `GENERATED ALWAYS AS` requires IMMUTABLE expressions (`convert_from`/`jsonb_build_object` are STABLE → 42P17 at apply) — use a plain column + app-layer sync. A migration that remaps live values (status/billing_model renames) must update EVERY query filtering on the old value in the SAME change — grep consumers first (a prepay→prepay_credits rename would have zeroed the daily drawdown).

### Auth & security
- `request.state.organization_id` (NOT `tenant_id` → AttributeError → 500).
- Status fields need explicit allowlist validation. UPDATEs carry the same scope as their SELECT (`session_id`, org). A DELETE feature covers EVERY delete path with the same org/tenant scope — grep every `DELETE FROM <table>` and router delete before done.
- PUBLIC_PATHS covers ALL non-JWT auth: OAuth callbacks, webhooks, shared-secret internal RPC — TenantAuthMiddleware 401s them otherwise and callers silently mis-default.
- Security gates FAIL CLOSED in prd: missing key/secret = block + log critical, never silently pass (a virus-scan gate once marked uploads 'clean' with no API key set).
- Real WorkOS access tokens carry NO `email` claim (test JWTs do). Middleware backfills it, but probe any new email-gated logic with a claim-less JWT before done.
- `require_company_role` checks the caller's role in their OWN tenant only — money-movement and cross-brand endpoints must verify ownership of the specific resource or gate grotap-admin.
- Webhooks: verify signature, be idempotent (dedup on event id), return non-2xx on transient failure (2xx = sender never retries), and survive out-of-order/duplicate delivery.
- A connect/OAuth flow requests the scopes its CONSUMER case needs — trace the whole feature across split cases (scope, token, schema, enum).
- Rebasing onto a hardened master must preserve auth guards master added; never re-add a provider wrapper that already exists.
- NEVER pass user-submitted strings to readFile/exec/path APIs — resolve against an allowlisted root, reject absolute paths and `..`, cap read size (a raw `readFile(source_doc)` would have exfiltrated orchestrator secrets into agent context). This includes FastAPI query params flowing into `Path(...)` (print-cloud `download_agent(version=…)`) — allowlist-regex the value first.
- A key/token FORMAT validator must match what the minting path actually issues — grep the mint endpoint before writing the regex (a `pca_` gate would have 401'd every real `grotap_print_` key; 8BC416).

### Wiring & contracts
- Importing/creating ≠ wiring: a new router is dead until `include_router` lands in main.py; an imported helper needs a real call site; every UI action needs an endpoint that EXISTS (grep the router — extend it if the task is "UI-only" and it's missing). Verify referenced modules/pages exist before wiring routes; check master before re-building landed work.
- Frontend + backend built in separate runs: PROVE the wire contract — hit the real endpoint, diff field names/shapes/enum casing against the TS types. Map DB rows→UI shape in ONE api layer.
- Filtering a 3rd-party system by a key? Prove WE emit that key, current format, current master; copy request/response shapes from the provider's current docs (cite URL in a comment).
- "Most recent N" from a list endpoint: verify its ORDER BY delivers recency — both sort AND limit window; add an allowlisted order param if not.
- Any endpoint that can return unbounded rows paginates BEFORE it ships (limit/offset + stable ORDER BY tie-breaker); grids get server-side filters; escape ILIKE metachars (`% _ \`).
- App slugs: verify against the `apps` table, copy slug facts from the task VERBATIM. `pipeline` (📋) ≠ `agent-pipeline` (⚡); `document-upload` displays as "AI Knowledge Base".
- Anthropic Messages API: any request whose messages contain `tool_use`/`tool_result` blocks MUST still pass the `tools` param — a "final answer" fallback that strips tools 400s on tool-bearing transcripts; use `tool_choice={"type":"none"}` instead (found in CASE-20260706-8F1C60).

### Frontend
- Unused TS imports → `noUnusedLocals` build error.
- Global `body` CSS is DARK (`#0f0f0f`/white) — every light surface sets its OWN text `color` (grids `#374151`); e2e asserts VISIBILITY (computed-style luminance), not DOM presence.
- New event domain → NEW BroadcastChannel (existing listeners have bare `onmessage` refetch handlers, no type filter).
- `window.open(url, '_blank', 'noopener…')` returns NULL even when the popup opens — an `if (!popup)` fallback then ALSO navigates the current tab (double-open, opener lost). Internal same-origin popups: plain `window.open(url, '_blank')`.

### State machines & jobs
- A failure path releases everything the happy path claimed (status, slot, lock, row) in the SAME transaction — "nobody un-claims it" = a leak that starves the pipeline.
- Background loops register in `background_loops.py::start_leader_locked_loops()` — never raw `asyncio.create_task` in lifespan (leader lock prevents web+worker double-execution).
- Never re-enter LangGraph threads paused at the human gate: detect with `snapshot.next?.includes('human_gate')`, NEVER `next.length>0`; re-invoking a live thread re-executes finished work.
- Billing idempotency keys are deterministic (derive from stable ids like `invoice-{brand_id}-{period}`) — never `uuid4()` per call.
- Auto-retry on failure needs backoff or a circuit breaker (N fast-fails on one path → pause + alert). Infra-caused failures are `failed_infra`, not `failed` — they don't burn case strikes.

### Build & ship
- `py_compile` misses import-time crashes — boot-test `python -c "import app.main"` before any backend push. FastAPI 0.115: bodyless status codes (204) need `response_model=None` (a `-> None` annotation asserts at route registration).
- Actually RUN `tsc --noEmit` + `py_compile` — "it compiles" is a command, not a claim. Grep your diff for committed conflict markers (`^<<<<<<<`).
- A "re-land with integrated fixes" task means the fixes are actually INTEGRATED — diff your branch against the rejected one first; byte-identical code = automatic re-reject (49C9DD re-landed 25423B's readFile hole unchanged).
- Rebase conflict resolution must PRESERVE master-side surface: after rebasing, `git grep` every symbol/endpoint/response-shape you deleted or renamed — any master consumer still on the old contract = broken merge (2533BA reverted seed-hetzner + renamed db functions while 3 master call sites and ServersPage still used them).
- Before finalizing, re-diff against CURRENT master: if master already landed your feature or rewrote the region, adapt or report-and-stop — never commit your stale copy of a hot file (a wholesale main.py replacement merged textually "clean" and would have deleted 5 live routers). Verify APIs/exception classes exist in the PINNED lib version (asyncpg has no `PoolAcquisitionError`); Dockerfiles that `npm run build` need devDeps installed first (`npm ci` then prune), not `--omit=dev`.
- Rename/refactor: `git grep <old-identifier>` returns zero (minus intended shims) AND app-catalog seeds updated (`seed_apps.sql`, `seed_brands_apps.sql`, `control_plane.py`).
- Stay in scope: no `npm install`, `package.json`/lockfile edits, or dep bumps unless the task IS a dependency upgrade.
- `railway up` is not done until `railway status --json` shows latestDeployment SUCCESS (healthcheck window ≥ slow boot; a failed healthcheck silently leaves the OLD image live). Use `RAILWAY_API_TOKEN` (not `RAILWAY_TOKEN`). Railway env vars are STATIC — after any Doppler rotation, refresh every service copy (`platform/scripts/railway_secret_audit.py`; runbook: `platform/docs/SECRET_ROTATION_RUNBOOK.md`).
- `| head -n 4`, never `| head -4`, in scripts.
- `railway up` has NO `--build-arg` flag — inject Dockerfile ARGs (e.g. GIT_SHA) as Railway service variables; verify any new CLI flag against the CLI's actual `--help` before shipping a workflow change.
- `ON CONFLICT (col)` can NOT use a PARTIAL unique index unless the predicate is repeated verbatim: `ON CONFLICT (col) WHERE <index predicate> DO UPDATE`. Without it every execute raises at runtime — and mock tests that assert the SQL string contains "ON CONFLICT" won't catch it. Check `pg_indexes` for a WHERE clause before writing the upsert.
- CI test steps install `-r requirements.txt -r requirements-dev.txt` — dev-deps-only makes every `app.*` import fail at collection and turns CI red on all backend changes.
- NEVER amend an already-applied migration file in place — the runner records applied FILENAMES and skips them, so amended DDL silently never runs anywhere. Always cut a new vNNN file, mirror it in BOTH dirs (`migrations/apps/<slug>/` + `ingestion-worker/migrations/apps/<slug>/`), and make manifest updates ADDITIVE (a hardcoded entry list drops whichever sibling migration merges alongside yours).
- Tests import the production code they verify (no reimplemented formulas, no tautologies); mock fixture types match the REAL helper return types; daemon/polling-loop tests mock `sleep`, cap iterations, and run bounded (`timeout 300 …`) — an unbounded loop test once wedged a whole server. Per-file test isolation must be process-level (pytest-forked), not `sys.modules` juggling — but wire `--forked` as a CI-only pytest flag (workflow step), NEVER in `pytest.ini` `addopts`: `os.fork` is POSIX-only, so a global `--forked` breaks every local (Windows) `pytest` run. "Unconfigured provider" tests must monkeypatch the provider's env vars EMPTY and mock the transport — ambient Doppler creds otherwise configure the provider and the test sends a real SMS/email.
- Verification/gate tasks (no code expected) report success without commits — say so in the task file.
- No unbounded concurrent SSH to one host — pool, serialize, backoff (sshd MaxStartups drops stampedes).
- Visibility/authz changes cover EVERY read+write path (list, my-apps, subscribe, vote, brands…) in ONE case; scope to the owning TENANT, not the creator user. One owner per hot file. Appending to a shared init hunk: use your OWN `pool.execute` block; don't re-ADD siblings' columns.
- One owner per hot FUNCTION too: two same-batch cases that both rewrite the same function (05572B + 8584FE both rewrote `record_answer_from_hold`) guarantee a structural merge conflict — the second branch is dead on arrival. Coalesce such cases into ONE task before dispatch, or build them in sequence on one shared branch.
- A fail-closed consumer gate requires closing EVERY producer path of that state in the same change (provision-or-cleanup, not warn-and-continue).
- **ONE-TOUCH HUMAN STEPS** — owner time is the scarcest resource. Before any HI hold that puts a human in a console: derive the COMPLETE end-state from the consumer's actual code + the verbatim error (every field, permission, scope), deliver ALL steps in ONE message, state what NOT to touch, and batch every other pending item for that console into the visit. Verify against reality, not memory.

## Key IDs
- Control plane Neon: `green-rice-76766370`
- Grotap tenant Neon: `proud-union-74070434` / ID: `c7d02593-955c-4ff4-8117-3b2bb267f518`
- Railway project: `f9bf333c-f929-413e-a95c-7923e10b5777`

## Fleet (full roster, hardware, Hetzner accounts: agents/SERVERS.md)
- Dispatch pool = **agent-02…06** (02–05: Execute ×3 slots + reviewer roles; 06: Deploy Ops + pipeline monitoring + Execute ×2 — its crons must always run: review gate 4h, deploy/health watchdogs, dispatch reconciler, Wasabi backups).
- **Not in the pool, never dispatch:** `grotap-cobrowse-01` (5.161.189.143 — recycled old agent-01 IP; Cobrowse AI support runner) and the Lane C model engine `LLM-LOCAL-02`. agent-01/07/08 DELETED; agent-09/10/11 cancelled in Hetzner Robot (awaiting wipe).
- SSH: always `ssh agent-NN` aliases, never raw IP. Key `~/.ssh/grotap_agents`; cobrowse box `User agent`, others `User root`. Max 3 tasks/server via worktrees.
- Git auth on exec servers: `credential.helper = /home/agent/bin/git-credential-doppler` (fetches `GITHUB_TOKEN` per call). NEVER set a static token in `~/.env`; if git auth fails, check `doppler me` as the `agent` user first.

## Dispatch — CONTINUOUS
Backend loop assigns every 3 min + completion-webhook refill; the LangGraph orchestrator (Railway)
owns run lifecycle and SSHes dispatches to the fleet. Manual one-off (from platform repo root):
```bash
bash agents/dispatch.sh <task.md> <server-ip> <session>   # manual
bash agents/dispatch-execute.sh <task.md> <session>       # auto-route (most free slots)
```

## Coding Pilot (CODING_PILOT env flag — default OFF, never enable without owner approval)
Open-weight lane (qwen-2.5-coder-32b via OpenRouter) replaces Claude for `simple` tasks only; never P0/P1, medium/complex, or >2/day/server. Gate: post-commit `tsc --noEmit` + `py_compile`; any fail → reset worktree + Claude fallback. Window ≤20 cases or 2 weeks; success = ≥70% gate-pass AND ≥90% cost cut vs Sonnet. Detail: platform repo `agents/GLOBAL.md`.

## Code Review
`/codex:review` before every commit (mandatory; separate from Rule 7 pipeline), then the Rule 7 review pipeline. ANY reviewer FAIL = branch blocked. No exceptions.

## Deployment
Frontend (Vercel) via CI on push to `master` (paths `frontend/**`). Backend Railway GitHub auto-deploy is BROKEN (case RLWAY1) — deploy via `doppler run -- railway up --service grotap-backend --detach` from `backend/`. Orchestrator: GitHub Actions `deploy-railway.yml` runs `railway up` on master pushes touching `orchestrator/**` (tip-commit detection only until CASE-20260705-C29667 lands — multi-commit pushes may silently skip; verify, fall back to manual `railway up`). Agents on Hetzner: push branch → request merge+deploy from coordinator.

## Git Discipline
| # | Rule |
|---|---|
| 1 | Branch is `master` — not `main`. `git pull origin master --rebase` before pushing. |
| 2 | Branch from CURRENT master; always push YOUR case branch (stale bases → monster diffs; no branch → unreviewable). |
| 3 | Never `git add -A` or `git add .` — stage specific files by name, and stage every NEW file you create (verify with `git status`; an uncommitted imported module crashes the backend on startup — #1 cause of broken merges). |
| 4 | Task NOT done until merged to master and deployed. Pushed ≠ done. Reviewed ≠ done. |
| 5 | Task files are gitignored — `agents/tasks/pending/active/done/archive/` not tracked. |
| 6 | Type-check before commit — `cd frontend && npx tsc --noEmit`. Fix errors first. |
| 7 | ONE app changed at once = ONE branch, built in sequence. Separate branches only for genuinely independent apps/subsystems. |
