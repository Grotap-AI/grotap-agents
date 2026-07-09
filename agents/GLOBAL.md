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
- A migration recorded in prod's `schema_migrations` is FROZEN — fix forward as the next `vNNN`. FROZEN means every byte: even a one-word seed-VALUE tweak (e.g. renaming a seeded display name in place) trips the startup checksum guard and blocks ALL prod deploys until reverted (lesson 2026-07-06, f661e2f0 broke every grotap-backend deploy). Any script that executes SQL as "proof" must `assert_not_prod(dsn)` (`backend/scripts/_lib_guard.py`).
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
- Integrating a 3rd-party SDK: probe the REAL artifact's export shape (2-min headless check: `typeof`, constructability, method presence) before coding against it — never trust docs-memory or in-repo "working precedent" without exercising it (CobrowseViewerPopout `new`-ed the device CDN singleton — not constructable, no `attachContext` — and shipped broken because a catch-all swallowed the TypeError into a generic error state; the spec then cited it as precedent). SDK-init catch blocks must surface `err.message`, and at least one test/smoke must fail if the SDK's export shape isn't what the code assumes.
- A contract SPIKE isn't done at "the shapes match" — it must include ONE end-to-end runtime proof of every RPC the feature depends on, against the real remote surface. The cobrowse-agent-sdk spike verified constructor/attachContext shapes, but `ctx.setTool()` — type-correct, promise-returning — NEVER acks against the hosted session page (0/24 over 60s on a fully-working session; the SDK's RPC layer is one-shot, no timeout, promise never settles), and the gap only surfaced at go-live as `browser_attach_failed`. For each remote call: prove it settles (resolve OR reject) live, and treat any cosmetic call as best-effort with a deadline, never a hard gate on the critical path (fixed in 61c63fc0).
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
- Frontend `npm run build` needs ~3 GB heap since AG Grid Enterprise (2026-07-06): vite OOMs at node's default ~2 GB during "computing gzip size" on 4 GB fleet boxes — tsc passes, all modules transform, THEN fatal OOM, so verify fails on good code. Keep `--max-old-space-size=3072` in frontend package.json `build` + `build.reportCompressedSize:false` in vite.config.ts; never revert to bare `vite build`. Verify error text is NOT persisted to any DB table — reproduce in the preserved `/home/agent/worktrees/CASE-*` on the failing box.
- `railway up` has NO `--build-arg` flag — inject Dockerfile ARGs (e.g. GIT_SHA) as Railway service variables; verify any new CLI flag against the CLI's actual `--help` before shipping a workflow change.
- `ON CONFLICT (col)` can NOT use a PARTIAL unique index unless the predicate is repeated verbatim: `ON CONFLICT (col) WHERE <index predicate> DO UPDATE`. Without it every execute raises at runtime — and mock tests that assert the SQL string contains "ON CONFLICT" won't catch it. Check `pg_indexes` for a WHERE clause before writing the upsert.
- CI test steps install `-r requirements.txt -r requirements-dev.txt` — dev-deps-only makes every `app.*` import fail at collection and turns CI red on all backend changes.
- NEVER amend an already-applied migration file in place — the runner records applied FILENAMES and skips them, so amended DDL silently never runs anywhere. Always cut a new vNNN file, mirror it in BOTH dirs (`migrations/apps/<slug>/` + `ingestion-worker/migrations/apps/<slug>/`), and make manifest updates ADDITIVE (a hardcoded entry list drops whichever sibling migration merges alongside yours).
- Tests import the production code they verify (no reimplemented formulas, no tautologies); mock fixture types match the REAL helper return types; daemon/polling-loop tests mock `sleep`, cap iterations, and run bounded (`timeout 300 …`) — an unbounded loop test once wedged a whole server. Per-file test isolation must be process-level (pytest-forked), not `sys.modules` juggling — but wire `--forked` as a CI-only pytest flag (workflow step), NEVER in `pytest.ini` `addopts`: `os.fork` is POSIX-only, so a global `--forked` breaks every local (Windows) `pytest` run. "Unconfigured provider" tests must monkeypatch the provider's env vars EMPTY and mock the transport — ambient Doppler creds otherwise configure the provider and the test sends a real SMS/email.
- Verification/gate tasks (no code expected) report success without commits — say so in the task file.
- Never relax a mandatory safeguard (drain-before-push, gate, gating doc) off ONE anecdotal survival — first `git grep` master to confirm the fixes the safeguard waits on actually landed (3B0DEB declared drain optional while the ORR1 s1–s3 re-attach fixes were still unmerged; the "survivors" were doc/CI cases).
- Reviewers judge the REAL branch, not the provided diff artifact: R2 case diffs have shipped truncated (lockfile-only when the branch had 3 files — 46490B was wrongfully rejected 3/3 on one; fix case CASE-20260706-05ADCB). If the diff looks partial (single lockfile, no source files, count ≠ branch stat), `git fetch` and `git diff master...origin/<branch>` before any verdict.
- Reviewers verify deliverable SUBSTANCE against the task's stated scope, not file existence: a case whose spec is "claim loop + browser layer + brain loop" is NOT done because `src/index.ts` compiles — CASE-20260704-C9C561 was approved 'done' with a one-line index.ts and the gap surfaced only when the feature was exercised. Check each numbered deliverable has a real implementation + its tests before PASS.
- No unbounded concurrent SSH to one host — pool, serialize, backoff (sshd MaxStartups drops stampedes).
- Visibility/authz changes cover EVERY read+write path (list, my-apps, subscribe, vote, brands…) in ONE case; scope to the owning TENANT, not the creator user. One owner per hot file. Appending to a shared init hunk: use your OWN `pool.execute` block; don't re-ADD siblings' columns.
- One owner per hot FUNCTION too: two same-batch cases that both rewrite the same function (05572B + 8584FE both rewrote `record_answer_from_hold`) guarantee a structural merge conflict — the second branch is dead on arrival. Same for NEW shared helpers: check whether a sibling's branch already adds the helper you need (`git ls-remote` + `git show`) before implementing your own copy (8C689F + 9D649C both independently invented `getOrCreateSessionId` in cobrowse.ts with different semantics; the e2e spec only matched one). Coalesce such cases into ONE task before dispatch, or build them in sequence on one shared branch.
- Sibling cases split from ONE decomposition own DISJOINT files: the layer-scoped case owns its layer's edits and the other sibling must NOT re-implement them "for completeness" (357E52 orchestrator-scoped case duplicated the backend `source_doc` field/persistence hunks its sibling 58A503 owned — with a WEAKER verbatim-persist variant, colliding on the same anchors and forcing a rebase fix case). If your task references a sibling case's scope, wire to its interface; don't rebuild it.
- A fail-closed consumer gate requires closing EVERY producer path of that state in the same change (provision-or-cleanup, not warn-and-continue).
- Optimistic-UI reconcile (dropping a local temp message once its server copy lands) must match ONLY rows persisted by THIS turn — never content-match against pre-existing history: a message textually identical to an older one + a failure before the server insert = the user's pending message silently deleted. Row-REUSE flows (re-send of a failed turn) may count an existing row as this turn's copy only with positive evidence of reuse (e.g. no OLD assistant reply after it in the refetch), never just "last user row matches" (F5F1C1 gate REJECT 2026-07-08).
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
- **API-limit fast-fail signature (lesson 2026-07-07):** every run dying at ~90s with $0 / 0 tokens
  and no error in the box log (`/home/agent/logs/orchestrator-run.log` shows "Running Claude:" then
  silence) = the Anthropic Console org hit its **monthly usage limit** (Console → Settings → Limits;
  distinct from credit exhaustion). Diagnose: `orchestrator_learnings` table holds the per-run diagnose
  verdicts; reproduce with `sudo -u agent claude -p "Say OK" --output-format json` on any agent box —
  a 400 "reached your specified API usage limits" confirms. Response: PAUSE `pipeline_automation`
  (enabled=false) so the dispatcher stops churning cases into failed, file an owner HI hold, relabel
  failed cases → `plan_approved` only AFTER the limit is raised. Model pins accelerate the burn —
  revert any burndown pin when its window closes.

## Agent Teams (dispatch routing — TEAM2-DISPATCH contract, owner-approved 2026-07-07)
- **team1** — the existing Claude agents (agent-02…06 pool, `orchestrator-run.sh` path). The default team.
- **team2** — open-model agents (aider via OpenRouter, default qwen-2.5-coder-32b with escalation ladder, `agents/team-run.sh`; pool agent-20/21). Inactive until its pool is provisioned in platform repo `agents/config.sh`.
- **Routing order:** explicit `case_data.team` on the case > `DEFAULT_TEAM` env (default `team1`). Team registry (server pool, runtime script, model env block, review policy) lives in platform repo `agents/config.sh`.
- **Switch the default:** set `DEFAULT_TEAM=team2` in the dispatcher env — the single knob for open-model-first cutover. Rollout order: provision agent-20/21 → add to config.sh pool → route a few P3 cases via `case_data.team=team2` → evaluate → widen. Daily cap: `TEAM2_DAILY_CAP` (default 10); `CODING_PILOT=1` survives one release as a back-compat alias for team2 routing.
- **Fallback team2 → team1:** a team2 run that exhausts its ladder emits `status=failed_open_model` → dispatcher automatically re-queues the SAME task to team1 (the Claude path), tagged `meta.team_fallback=true` in dispatch_log.
- **Disable routing:** `DEFAULT_TEAM=team1` (or unset) + no `case_data.team` on cases → the team1 path is byte-identical to pre-teams dispatch.

## Coding Pilot (CODING_PILOT env flag — default OFF, never enable without owner approval)
Open-weight lane (qwen-2.5-coder-32b via OpenRouter) replaces Claude for `simple` tasks only; never P0/P1, medium/complex, or >2/day/server. Gate: post-commit `tsc --noEmit` + `py_compile`; any fail → reset worktree + Claude fallback. Window ≤20 cases or 2 weeks; success = ≥70% gate-pass AND ≥90% cost cut vs Sonnet. Detail: platform repo `agents/GLOBAL.md`.

## Code Review
`/codex:review` before every commit (mandatory; separate from Rule 7 pipeline), then the Rule 7 review pipeline. ANY reviewer FAIL = branch blocked. No exceptions.

## Deployment
Frontend (Vercel) via CI on push to `master` (paths `frontend/**`). Backend Railway GitHub auto-deploy is BROKEN (case RLWAY1) — deploy via `doppler run -- railway up --service grotap-backend --detach` from `backend/`. Orchestrator: GitHub Actions `deploy-railway.yml` runs `railway up` on master pushes touching `orchestrator/**` (tip-commit detection only until CASE-20260705-C29667 lands — multi-commit pushes may silently skip; verify, fall back to manual `railway up`). Agents on Hetzner: push branch → request merge+deploy from coordinator.
- **Orchestrator redeploy kills in-flight runs (lesson 2026-07-07):** the orchestrator Railway service
  auto-deploys on master pushes touching `orchestrator/**`, and a redeploy severs every live SSH run on
  the fleet (runs die silently, dispatch rows go stale). Before ANY master push, check
  `git diff --name-only origin/master..HEAD -- orchestrator/` — if non-empty, wait for in-flight runs to
  drain (or pause automation) first.

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
- Rebuilding/re-pushing a branch is a fresh landing attempt: fetch and rebase onto CURRENT master right before your final push, and DROP any hunk master now owns (357E52's 07-06 15:28 rebuild still carried the superseded backend source_doc hunks 10 min after sibling 58A503 merged them — instant re-conflict).
- ORP dual-run: OBSOLETE 2026-07-08 — EA3E8D's Cobrowse rip-out reached master (2d6fe34d), so the dual-send no longer exists to preserve. The constraint transfers: `AI_SUPPORT_ENABLED` must STAY false until an OpenReplay runner driver actually lands on master (ORP3 case 9C3809 reads `done` but shipped ZERO code — `cobrowse-agent-runner/src/index.ts:52-53` still hard-throws; verify the code, never the case status). Still true: `frontend/src/lib/openreplay.ts` is RESERVED for ORP1's tracker wrapper — never create it for plumbing/seams.
- Duplicate case cuts of the SAME endpoint (663AF1 + D290F7 both built GET /support/turn-credentials): before building, `git log origin/master` + grep the router for the route — if a twin case already landed, ship a superseded marker doc instead of a second implementation (two `@router.get` defs for one path merge silently and shadow each other).
- Bash test harness under `set -euo pipefail`: a helper function must NOT end with a bare `[[ cond ]] && cmd` — when `cond` is false the `&&`-list returns 1, becomes the function's exit status, and (called as a bare statement) trips `set -e`, aborting the whole script before any assertion runs. Symptom: `rc=1` with ZERO output. Use `if [[ cond ]]; then cmd; fi` or append `return 0`. (CASE-20260706-61647F's `test_frozen_migrations.sh` `run_guard()` ended with `[[ $VERBOSE -eq 1 ]] && printf ...`; default `bash test.sh` ran 0 of 10 tests. The guard it tested was correct — only the harness aborted. When you ship tests, RUN them in the default (no-flag) mode before claiming green.)

- Review gate 2026-07-07 (D3117A/4680FB): a frontend-only branch that calls a NEW endpoint can silently 404 in prod if its backend is not on master. ALWAYS grep master backend for the route the frontend consumes (`git grep "<route path>" origin/master -- backend/`); if absent, find the sibling backend case branch and land it FIRST (dependency order). A backend case marked status=`done` may NEVER have been merged (merge lost, no rejection recorded) — verify with `git branch -r --contains` before assuming its content is live.
- Review gate 2026-07-08 (EA3E8D) — **a BLOCK that lives only in prose is NOT a block.** The reviewer BLOCKED EA3E8D (premature ORP5 Cobrowse rip-out) but recorded the verdict only in the review report + hold text; the agent-06 auto-approve gate cron reads dispatch-row/case status, saw a green branch, and MERGED it (2d6fe34d) in the same batch as an approved one. Rule: the moment you decide BLOCK, make it machine-visible FIRST — flip the dispatch row out of `awaiting_review` (e.g. `rejected`) and/or park the case (`awaiting_human` with the block reason in case_data) BEFORE writing any report. Outcome: merge kept (no revert — OpenReplay direction is owner-locked and `AI_SUPPORT_ENABLED=false`, so no live flow broke), but only luck made it safe. Original premature-cut lesson still stands for future removal-family cases: verify the gate on CURRENT master code (not case statuses) before any code deletion; premature → marker doc / hold. Precedent chain: 085AAA·E47AC8·9E6FFE·B28CD4·2197B9·D6EC58·AC3753·EA3E8D.
- Review gate 2026-07-08 (D7A410) — **scaffolding is not a deliverable, and it breaks the build.** A feature agent shipped a correct backend (Drive provider + config + 3 endpoints) but the frontend half was dead scaffolding: two `interface`s declared and never used + an `onInsertLink` prop passed to `<SessionRail>` whose props type never declared it. Zero required UI was built (no "open folder" link, no upload action, no fetch to the new endpoints). `cd frontend && npx tsc --noEmit` failed 3× (TS6196 unused decl ×2, TS2322 excess JSX prop) — Rule 6 would have caught it in 20s. Rules: (1) a frontend deliverable is DONE only when the UI renders AND calls its endpoints — declaring the types/props is 5% of the task, not the task; (2) unused type/interface = TS6196 and a JSX prop the child doesn't declare = TS2322 — both are HARD errors, so run tsc before claiming done, every time; (3) don't leave half-wired plumbing (a helper + a prop that goes nowhere) — either finish the wire or delete it. Branch NOT merged; frontend routed back as fix case FD7A41 (backend preserved, continue the same branch).
- Review gate 2026-07-08 (DC3D27 + 04473B) — **parallel agents collide on the next migration version.** Two independently-dispatched cases each created a `v037_*.sql` under `backend/db/migrations/control_plane/` (`v037_claude_code_slots.sql` and `v037_claude_attachments_meta.sql`) because each computed "next = current max (v036) + 1" in isolation. Harmless HERE only because the migration_runner ledger PK is `filename` (not version int) so both apply in sorted-name order — but two truly same-named files, or a runner keyed on version, would silently drop one. Rules: (1) when a case adds a migration, `git ls-tree origin/master backend/db/migrations/control_plane/ | tail` AND check for peer case branches adding the same vNNN before picking a number; (2) if a sibling already took vNNN, bump to vNNN+1 — never ship two files with the same version prefix; (3) reviewer: on any batch with ≥2 new migrations, confirm distinct version numbers. Both merged (filename-keyed ledger made it safe), noted in the summary hold.
- Review gate 2026-07-08 (8DC100, RECURRENCE of D7A410, SAME app/day) — **a referenced-but-undefined component is a hard TS2304, and again nobody ran tsc.** Claude App spec-upload branch wired all the lifecycle state (SpecEntry map, polling, uploadSpecDocument/serveSpecs, "📄 Upload Spec" button) then rendered `<SpecUploadCard .../>` (ClaudeAppPage.tsx:1152) — a component NEVER defined or imported (file ends 2602). `npx tsc --noEmit` → `TS2304: Cannot find name 'SpecUploadCard'`, and the whole results UI (processing bar, MD link, image thumbnails, retry, Serve-Specs button) lived in that missing component, so 3 of the deliverables render nothing (the added ca-shimmer keyframe is dead). Two build-breaking frontend branches on the Claude App in ONE day, both caught in 20s by Rule 6. Hard rule, restated: RUN `cd frontend && npx tsc --noEmit` and see it pass BEFORE claiming done — a JSX tag with no definition/import fails as loudly as an unused interface. NOT merged; routed back as fix case 8DCF1X (existing work preserved, continue same branch).
- Review gate 2026-07-09 (57E1DC, RECURRENCE of 05572B/8584FE + 357E52/58A503) — sibling subtasks of ONE decomposition (parent 0A3533) again both touched the same function: 57E1DC re-implemented `share_code` generation inside `support_live.py live_help_ping()` (secrets + `_generate_unique_share_code` helper + `status='waiting'` collision filter) that sibling E8600B had already landed inline (random-based, all-rows filter) via d696807a, plus a duplicate migration (`v038_share_code.sql` vs master's `v038_add_share_code.sql`). Structural conflict → merge aborted (no hand-weave), branch failed, routed back as rebase fix case DCFF65 keeping ONLY the genuinely-new by-code endpoint + list SELECT and dropping every hunk master now owns. Restated: a subtask must own DISJOINT files/functions from its siblings — if your task only needs the by-code lookup, do NOT also re-add the shared share_code generator "for completeness"; grep CURRENT master for the symbol first and wire to what's there.
