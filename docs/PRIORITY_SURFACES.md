# Priority surfaces and owner directives (ON-DEMAND)

Moved out of platform/CLAUDE.md to shrink session preamble.

## PRIORITY ORDER — IN FORCE (owner directive 2026-09-15, gate OPENED 2026-09-17)

**The gate is open. This ordering governs what is worked on next, starting 2026-09-17.** The owner's
start condition was "once the Forgejo INFRASTRUCTURE upgrade is complete", and on 2026-09-17 the
owner ruled that condition met — the forge, its runners, the HMAC route, dispatch admission control,
per-host SSH keys and Cloudflare Access are all live (below). Moving the DEPLOY PATH to the forge was
always a separate owner-gated step; it continues as a background infrastructure track and does NOT
gate product work. The 2026-08-13 ordering below no longer decides what to work on next.
Status as of 2026-09-17:

- **DONE:** `forge-01` (Hetzner cpx21 Ashburn, `178.156.246.81`) runs Forgejo 13.0.5 behind Caddy +
  Cloudflare at `https://forge.grotap.com` (verified 200, API requires sign-in). Firewall `forge-fw`:
  22 and 2222 fleet/workstation only, 80/443 Cloudflare ranges only. `DISABLE_REGISTRATION`,
  `REQUIRE_SIGNIN_VIEW`, `INSTALL_LOCK` on. All four repos pull-mirror from GitHub every 10 min.
  `forgejo-runner` v13.1.0 runs in HOST mode on **agent-02..06** as an unprivileged `forge-runner`
  user in a systemd jail — so each worker box now runs a SECOND daemon alongside its agent tmux
  session. Credentials in Doppler `grotap` prd+dev: `FORGE_URL`, `FORGE_API_TOKEN`, `FORGE_ADMIN_*`,
  `FORGEJO_WEBHOOK_SECRET`, `FORGE_SSH_HOST`, `FORGE_SSH_PORT`, `FORGE_SERVER_IP`.
- **ALSO DONE since 2026-09-15 — 4 of the 5 items this list used to call open:** the
  HMAC-authenticated `/api/v1/forgejo/*` route (`f86d599ed`, `backend/app/routers/forgejo.py:43`;
  `GET /api/v1/forgejo/health` returns 200 `configured:true`); `dispatch.sh` admission control
  (`f86d599ed`, `agents/dispatch.sh:1941-1998` — count and tmux launch under one `flock` on the
  target, `DISPATCH_SLOTS_PER_BOX` ceiling); per-host SSH keys replacing the shared fleet key
  (`cfa9f97ae`, merged `ed3e51999` — shared key stripped from `root` on 13 hosts and from `agent@`
  on agent-02..06); Cloudflare Access in front of the forge (live 2026-09-16).
- **NOT DONE — GitHub is still the source of truth.** Mirrors are pull-only; Railway and Vercel still
  build from GitHub. Cutting the deploy path over is a separate owner-gated step and is the ONE
  remaining item. Its canary started 2026-09-17T14:44:40Z on `grotap-platform-docs` (converted from a
  pull mirror to a normal repo plus a push mirror back to GitHub); earliest close of the 14-day
  "boring window" is 2026-10-01T14:44:40Z — see `docs/06-infrastructure/forgejo-cutover-gate.md`
  (grotap-agents repo).

**Open gate does not mean migration complete.** Those are two different things and only the first
one has happened. Two consequences worth keeping straight:
- Product work follows the five-surface order below starting now; it does not wait for the canary.
- The canary is tracked, not waited on — and it will not satisfy itself. The 20-green-Actions
  criterion measures runs with `id > 4` inside the window, but the canary repo has
  `has_actions=false` and no workflows, so ambient traffic yields zero; someone must produce those
  runs deliberately or re-point the criterion at a repo that runs CI. The in-window
  restore-verified-backup criterion is still blocked on the `REPLACE_ME_` Wasabi credential, which
  has never produced one successful timer-fired backup.

Pending or requested development work is taken in this order, and **one surface is finished
completely before the next is started** — no interleaving, no "while I'm in there":

1. **ScanTap platform app** (the web app)
2. **ScanTap Mobile app** (Scan M on the tablet)
3. **Print Cloud**
4. **Loop Engine**
5. **Free Stream**

Rules of this ordering:
- It REPLACES the 2026-08-13 ordering below for deciding what to work on next. The section below is
  kept for its factual detail (what is built, what is blocked, case ids) — not for its sequence.
- Everything not on this list — Team Hub, Vendor View, platform basics, the self-improving fleet,
  pipeline/CI/monitoring work — sits BELOW all five and is still subject to the PRODUCT FREEZE below.
  The freeze's existing exception still holds: work that BLOCKS one of the five is part of that
  surface's slice, not separate work.
- "Finished" means the surface has no pending or requested dev work left, not that a single case
  merged. Confirm against the open-case list for that surface before moving on.

**Dependency handling (owner decision 2026-09-15).** The blocked-by graph does not respect the
surface boundary, so two clauses qualify the strict ordering. Measured from `pipeline_case_deps`,
2026-09-15: one serial chain runs `MAP-1 -> MAP-2 -> MAP-2b -> MAP-2d/MAP-4 -> CAD-3 (web) ->
CAD-2 (tablet) -> ANT-2 -> ANT-3 -> ANT-4 -> LPOS-2 -> LPOS-3 -> LPOS-4 -> LPOS-8 (web)`. It starts
and ends on surface 1, so surface 1 cannot be finished without surface 2 running in the middle.
1. **Blocker pull-forward.** When a case on the CURRENT surface is blocked by a case on a LATER
   surface, work that blocker as part of the current slice — build only what unblocks, no extra
   scope. This is not a surface switch and does not reopen the later surface.
2. **Tail demotion.** When a current-surface case sits behind a CHAIN of later-surface work rather
   than a single blocker, it moves to the tail of that later surface instead of holding the current
   surface open. As of 2026-09-15 that is exactly three ScanTap-web cases, which move to the end of
   ScanTap Mobile: **LPOS-4** (`CASE-20260914-915E58`), **LPOS-8** (`CASE-20260914-5898B3`) and
   **ANT-5** (`CASE-20260914-FF83E9`). Surface 1 counts as finished without them.
- Free Stream remains downstream of Loop Engine (no connected mailbox means no mail means an empty
  stream), which is consistent with taking Loop Engine first.

## PRIORITY SURFACES (owner directive 2026-08-13, amended 2026-08-15)
Work is prioritized on these surfaces, in this order of standing. Anything not on this list is
subject to the PRODUCT FREEZE below.
1. **ScanTap**
2. **Scan M Platform**
3. **Scan M mobile (on the tablet)**
4. **Print Cloud**
5. **Free Stream** — added 2026-08-15. Beta; the app is built (`frontend/src/pages/free-stream/`,
   ~4.7k lines, no stubs) and no case has been filed against it since 2026-07-21. It is downstream of
   Loop Engine: no connected mailbox means no mail means an empty stream, so item 6 unblocks it.
6. **Loop Engine** — added 2026-08-15. Beta; built (`backend/app/routers/loop_engine.py`,
   `frontend/src/pages/loop-engine/`) and cold since 2026-07-26. **GroTap is connected; Manor View
   is the one still blocked on an owner action.** Measured in the GroTap tenant DB 2026-09-17,
   `loop_engine.connected_accounts` has 2 rows: `info@grotap.com` (`e02365a1-…`, provider `google`,
   connected 2026-09-15 03:39Z, `gmail_sync_enabled=true`, `gmail_history_id` advancing, tokens set
   — live and syncing) and `info@sauvieislandstable.com` (`18ee82ea-…`, connected 2026-09-17 05:07Z,
   tokens set but `gmail_sync_enabled=false` — connected, sync not yet turned on). The GroTap hold
   `e3f60833-9539-428c-9455-1bdac6a90deb` (`gmail-mailbox-setup-c7d02593`) is **`resolved`**
   (2026-09-15 03:40Z, resolution "Connected info@grotap.com to the GroTap tenant in Loop Engine") —
   and this time the connect really happened, unlike the older `232be02d-…` hold resolved 2026-09-07
   15:39Z ("create internal report showing this") with no mailbox attached, which is why the bot
   refiled a minute later. The genuinely unresolved one is Manor View's
   `7cc892b1-9183-4c79-877f-f5365255f70f` (`gmail-mailbox-setup-9a1f6820`, filed 2026-09-10, still
   `pending`): its only `connected_accounts` row is `damon@manorview.com` with NULL tokens and
   `gmail_sync_enabled=false` — a placeholder, not a connection. Connecting it needs the account to
   be an OAuth-consent test user if the GCP app is still in Testing mode. Verify claims here against
   the table, not the hold — resolving a hold is not the same as doing the connect. Tenant data
   lives in the tenant DB under the `loop_engine` schema (`loops`, `connected_accounts`), not the
   control plane.
7. **Platform basics** (auth, tenancy, billing, deploy, the app shell — the things every app rides on)
7a. **Team Hub** — added by owner 2026-09-13 ("we can't manage the to do list"). v1 (chat rooms +
   scratchpad drawer) merged `3288490dc` 2026-09-10. v2 = the owner document "#Team Hub Enhancements":
   playbook docs, shared client project board, client review pings, banners, kanban lifecycle,
   permission tiers — filed as HUB-1..8 (`scripts/team_hub_v2_cases.py`, roots `CASE-20260913-F0A17F`
   … `CASE-20260913-C624ED`), sequential on `feat/team-hub-v2`. Decisions of record are in that
   script's docstring (clone trigger = quote won OR tenant provisioned; credentials Fernet-encrypted,
   staff-only reveal; build in document order).
8. **Self-Improving Fleet + Improvement Scout** — the two `/machine` panels that currently read dark.
   Both waves are BUILT and merged (SIA-A..D `CASE-20260719-EF4D3A/43B6CF/3D5CA1/F0A699`;
   SEP-A..E `CASE-20260719-3BDC78/BA0430/31FE3A/91037B/0ACE7E`). Both scouts are **enabled and
   running** as of 2026-09-07: `MODEL_SCOUT` and `IMPROVE_SCOUT` are present in Doppler grotap/prd;
   `pipeline_automation.model_scout_enabled` and `improve_scout_enabled` are both TRUE for the grotap
   org. Measured 2026-09-07: `model_scout_runs` = 32 rows (30 ok / 2 error, latest ok 2026-09-07),
   `improvement_scout_runs` = 43 rows (32 ok / 3 failed / 8 skipped, latest ok 2026-09-04).
   **Open problem: neither scout has ever produced a candidate or a finding** — SUM(findings_count)
   across all improvement_scout runs = 0; zero model_scout runs have emitted a non-empty findings
   field. The cause is unknown (likely a signal/threshold gate in the scout logic, not enablement).
   Spec of record: `scripts/self_improving_fleet_cases.py` (SIA — scouts MODELS) and
   `scripts/self_evolving_platform_cases.py` (SEP — scouts TECHNIQUES/DESIGN/PRICING, $15/mo
   research cap). Both are suggest-only by hard rule.
This item is an explicit owner-granted exception to the freeze — it is meta work, and it is
prioritized anyway; it does not widen the exception to any other meta work.
   **PAUSED by owner 2026-09-09** ("pause all cases asking about LLM improvements"): both scout
   flags set FALSE for the grotap org (`model_scout_enabled`, `improve_scout_enabled`); the 12
   improvement-scout research cases filed 2026-09-10 (roots `CASE-20260910-CB8FE6` RTX PRO 6000,
   `D0EB72` Agentifying Agentic AI, `6AE32F` LLM-Coordination, `1C251D` SkillReducer, `C9F1AA`
   Context Engineering + 7 children) sit at `status='paused'` with the prior status in
   `metadata->>'paused_from'`; their 5 clarification/breakdown holds were dismissed by SQL (never
   via the API — dismissing a clarification hold through the API REJECTS the case). `paused` is
   not a status any automation query or the review-gate cron selects, so it is inert; the UI has a
   fallback colour. Resume: `UPDATE pipeline_cases SET status = metadata->>'paused_from' WHERE
   status='paused'` and flip the two flags back to TRUE. Owner priority order as of 2026-09-09:
   platform fixes, Print Cloud, ScanTap platform, ScanTap mobile, Scan M platform, ScanTap remote
   management of tablets and readers. Do not file or approve LLM-improvement work until unpaused.

## PRODUCT FREEZE on fleet self-improvement (owner directive 2026-08-13)
**No new pipeline / CI / monitoring / review-gate / orchestrator / backup-tooling case may be filed
unless it BLOCKS a case on a PRIORITY SURFACE above (ScanTap, Scan M Platform, Scan M mobile,
Print Cloud, platform basics, or the scout enablement).**
Everything else is meta: work the machine does on itself, which produces no customer-visible change
and buries the work that does. If it does not block product, it does not get a case — it gets closed.
- **Why (measured 2026-08-13):** the HI board held 120 pending holds — **119 filed by bots, 0 by the
  owner** — against 87 distinct titles, split 78 meta / 18 product. Open cases ran ~70 meta / ~40
  product. Buried in that noise: DR backup dead 18 days, a P1 where the public quote page undercharges
  through Stripe, and the Intuit production keys blocking ScanTap↔QuickBooks. Purge: 71 cases closed,
  100 holds dismissed.
- **An auto-filed meta case is closed, not triaged** — `status='closed'` (never `'rejected'`, which
  supersedes dependents instead of releasing them).
- **A monitor that can only ever tell a human to perform one fixed mechanical action must perform it
  instead.** A hold has to carry a DECISION. If the remedy is always the same command, automate the
  remedy and hold only on the case that deviates.
- **A run summary is a log, not a hold.** Receipts go to stdout/report tables; the board is for
  blocked work only.
- Genuine exceptions (ship them): a fault that is losing customer data, money, or the ability to
  deploy at all. Judge by customer impact, not by how interesting the defect is.

## Default Execution — PIPELINE-FIRST (owner directive 2026-07-01)
For any substantive change (feature, bug fix, multi-file work), the DEFAULT is the pipeline / agent
fleet — NOT building it myself. Every agent run + review + `GLOBAL.md` lesson compounds the machine.
1. **Plan** — decompose into cases, clarify, build the plan.
2. **Prompt the owner** — state I'd rather drop it in the pipeline (I review + gate + teach); proceed that way unless told otherwise.
3. **Dispatch** — `bash agents/dispatch.sh <task.md> <ip> <session>` (see memory `project_fleet_dispatch_working_path`).
   One app changing at once = ONE shared branch built in sequence, single merge.
4. **Review every branch before it goes live.** Defect found → route the fix back to an agent AND encode
   the lesson — never silently hand-patch agent work.

### Where a lesson gets written (rule changed 2026-07-25)
Lessons go in `C:\1Claude\agents\lessons\<surface>.md`, **never** in `GLOBAL.md`.
`GLOBAL.md` is the constitution (8 rules + always-on FAIL causes) and is byte-capped at 40 KB by
`.claude-session-init.sh` — it is cat'd verbatim into every agent prompt, so every line added there
is billed on every dispatch, forever. It reached 199 KB / ~50k tokens this way; 85% of it was an
append-only incident log shipped to agents who could not act on it.
- Pick the file whose trigger matches the defect: `sql-migrations` · `wiring-contracts` ·
  `build-ship` · `frontend` · `auth-security` · `state-jobs` · `fleet-ops` ·
  `decomposition-gate` (the last is auto-pushed into reviewer/gate prompts; the rest are read on demand).
- **Before appending, grep the file for the same root cause and generalize the existing line instead.**
  Four separate lessons about "siblings fanned out onto one file" is what bloat looks like.
- One line, claim first, with the case id. Only a lesson that applies to EVERY agent regardless of
  surface may go in `GLOBAL.md` — and then by generalizing an existing FAIL-cause line, not adding one.

I keep by hand: the review gate, and owner-approved irreversible ops (live migrations, data loads).
Build-it-myself is reserved for trivial one-liners, conversational answers, and genuine emergencies.

### Coalescing (owner directive 2026-07-01)
Let non-urgent cases ACCUMULATE, then dispatch COALESCED — each agent run has a large fixed cost
(bootstrap, worktree, context, 4-reviewer + Codex pass); batching pays it once per group.
- **Group by touch-surface**: cases hitting the SAME screen/router/schema → ONE coalesced task, ONE shared branch.
- **Cadence**: batch on the dispatch cycle or when a cluster forms — not on arrival.
- **Cap batch size to the agent's turn budget** (~one screen-area, finishes in ~80 turns) — an over-large task fails partway and wastes the run.
- **Urgency bypass**: P0/P1 ship immediately, never wait for a batch.
- When unsure whether to batch, prompt the owner with the cluster + spend/latency trade.
- **Safety gates (server-side coalesced dispatch, ships dark)**: automation-side grouping in
  `backend/app/services/pipeline_automation.py` activates only when BOTH gates are on —
  `PIPE_COALESCE=1` env var (deploy-level; accepts 1/true/yes/on, anything else = OFF) **AND**
  `pipeline_automation.pipe_coalesce_enabled` (per-org runtime flag, migration `v034`, DEFAULT false).
  Either gate off → dispatch is byte-identical to pre-coalescing (one whole-slice claim, no
  metadata writes). Cap is `COALESCE_MAX_GROUP = 4`; P0/P1 always dispatch solo; only
  CONSECUTIVE same-`touch_surface` cases group.
  - Enable per org (runtime, no redeploy; the env var must already be set on the service):
    `doppler run -p grotap -c prd -- python scripts/db.py "UPDATE pipeline_automation SET pipe_coalesce_enabled=true WHERE org_id='<org>'"`
  - Kill switch: flip that column back to `false` (instant, per-org), or unset/zero
    `PIPE_COALESCE` on the Railway backend service (global, needs restart).
  - Example: 3 consecutive plan-approved `scantap` cases + 1 `print-cloud` case → 2 dispatch
    groups (`[A,B,C]` coalesced, members stamped `metadata->>'coalesced_into'='A'`; `[D]` solo);
    a P1 arriving between them breaks the run and ships alone.

## Screenshot Verification — Subagents Only (context rule 2026-07-10)
**Never `Read` screenshot/image files in the main session** — each image lands as base64 and burns
tens of K of context until compaction. Spawn the `screenshot-verifier` agent
(`.claude/agents/screenshot-verifier.md`) instead: it runs Playwright / Reads the images in its own
throwaway context and returns a text-only PASS/FAIL verdict per check. Give it the URL or spec, the
screenshot path(s), and an explicit checklist. Humans who want to see an image open the reported
file path themselves. Exception: multi-turn visual design iteration in the main session — even then,
one cropped screenshot, not full-page sets.

## Rehearse With User — Pre-Dispatch Requirement Clarification (CASE-20260907-5D1E43)
An **opt-in** interactive loop between case creation and dispatch. A domain-expert agent asks up to
5 clarifying questions; the resulting conversation is summarized into `pipeline_cases.metadata.rehearsal_summary`
and injected into the task file `context_pack` before SSH dispatch. No changes to `dispatch.sh`,
the LangGraph orchestrator, or the ERP agent graph.
- **When:** `case_data.rehearse: true` AND `complexity: medium|complex` AND priority surface case only.
- **Never for:** P0/P1, bug fixes, simple cases, cases with a detailed existing `context_pack`.
- **20% throughput gain claim is unvalidated** — baseline metrics (`T = cases/day`, retry rate,
  first-attempt success rate) do not yet exist. Run §5.5 queries from `docs/multi-agent-coordination-design.md`
  before deploying; evaluate after 14 days. See full spec: `docs/rehearse-with-user-design.md`.
- **Kill switch:** remove `rehearse: true` from a case's `case_data`, or set `rehearsal_status: cancelled` in metadata.

## Agent Fleet Security (CASE-20260907-B78C9D)
Threat model, deployment checklist, incident playbooks, and monitoring setup are in `SECURITY_OPERATIONS.md`.
Key open P1 risks (unmitigated until implementation cases ship):
- **`agent-progress` fallback auth** — webhook accepts calls without `NODE_SECRET` if a valid `case_id` is supplied (P1-A fix).
- **Unauthenticated bootstrap clone** — `dispatch.sh` clones the agents repo with no SHA pin or integrity check (P1-B fix).
- **Heredoc shell injection** — task body is embedded inline in dispatch heredocs without sanitization (P1-C fix).

When a security-related HI hold fires, follow the matching playbook in `SECURITY_OPERATIONS.md §3`:
- Prompt injection → §3.1
- Worktree escape / lateral movement → §3.2
- Orchestrator auth failures / 403 storm → §3.3

## Skill Caching & Reuse (CASE-20260907-5A7C0E)
The LangGraph orchestrator has a process-lifetime **skill result cache** that avoids re-running identical LLM skill invocations across turns and concurrent tasks.

**Orchestrator** (`orchestrator/src/lib/skill-cache.ts`):
- `SkillCache` interface + `InMemorySkillCache` (lazy TTL expiry, no timers) + `NoopSkillCache` (tests)
- `hashCacheKey(parts)` — SHA-256 hex prefix for stable, short cache keys
- `defaultSkillCache` — module-level singleton, shared across all concurrent runs
- TTL: `SKILL_CACHE_TTL_MS` env var (default 3600000 ms = 1 h). Set to `0` to disable (entries expire immediately).

**Triage node** (`orchestrator/src/nodes/triage.ts`):
- `makeTriageNode(invoke, lessonFetcher, timesApplied, cache?)` — 4th param is `SkillCache`; tests omit it (get `NoopSkillCache`) so all existing invoke mocks are always called unchanged.
- Cache key: SHA-256 of `[title, requirements, context, complexity, priority]`. Learnings excluded — they evolve over time and a fresh plan may legitimately differ.
- On cache hit: reuses LLM content, tokens reported as 0; all other node logic (lesson fetch, `bumpTimesApplied`, limits) runs unchanged.
- On cache miss: calls invoke, stores result best-effort (`catch(() => {})`).

**pipeline.py** (`backend/app/routers/pipeline.py`):
- `SkillDispatchCache` class + `_skill_dispatch_cache` singleton — deduplicates `done` callbacks per case_id within the TTL window, preventing double fan-out/rollup/refill work.
- TTL: `SKILL_CACHE_TTL_SECS` env var (default 3600 s = 1 h).
- `content_key(title, requirements, context)` — SHA-256 prefix for content-based dedup (used in future per-content caching).

**Skill registry & agent learning** (CASE-20260907-000EBE):
- `GET /pipeline/skills/for-task?title=<...>` (node-secret auth) — returns skills whose `prompt_patterns` match the task title; falls back to top-N by `usage_count`. Called by `dispatch.sh` at agent startup (s2 skill loading). Fails open on missing `agent_skills` table.
- `POST /pipeline/skills/usage` (node-secret auth, body `{"skill_name": "...", "case_id": "..."}`) — increments `agent_skills.usage_count` and stamps `pipeline_cases.metadata.skills_used`. Called by the runner after a successful task to feed the learning loop.
- `GET /pipeline/metrics/skills` (node-secret auth) — exposes `SkillDispatchCache` stats + registry aggregates (`total_skills`, `total_usage`, `top_skills`).
- Schema: `backend/db/migrations/control_plane/v134_agent_skill_registry.sql`. Service layer: `backend/app/services/skill_registry.py`.
- ⚠ **NONE OF THIS LOOP HAS EVER RUN IN PRODUCTION** (verified 2026-09-14). Both halves are broken.
  READ: `/pipeline/skills/for-task` and `/pipeline/metrics/skills` are absent from
  `NODE_SECRET_EXEMPT_ROUTES` (`middleware/tenant_auth.py:99`), so `TenantAuthMiddleware` 401s at
  `:749-758` before the handler's own correct node-secret check runs. `dispatch.sh:1096` swallows it
  (`|| true` + bare `except: pass`), so every agent for ~2 months got an EMPTY skills section with no
  log line. Sibling calls work only because `/pipeline/webhook` and `/pipeline/internal/` are exempt
  by prefix (`tenant_auth.py:654`). Fourth instance of this same root cause — see `CASE-20260710-AF9C01`,
  `CASE-20260720-A87351`, `CASE-20260726-5A81AD`.
  WRITE: there is no `POST /pipeline/skills/usage` call in `dispatch.sh`, `dispatch-execute.sh` or
  `scripts/dispatch-poller.sh` — the write half was never wired, so `agent_skills.usage_count` is 0
  everywhere and `skill_registry.py:52`'s `ORDER BY usage_count DESC` fallback ranks arbitrarily.
  **Fixing the middleware alone yields retrieval that returns rows in meaningless order.**
  ⚠ RANKING SIGNAL: usage frequency is the wrong signal for a LESSON even once the write half works —
  a lesson's value is whether it matches the diff in front of the reviewer, not how often it has been
  served. Proof (2026-09-14): 46 of 300 `orchestrator_learnings` rows were API-credit advice after the
  credit outage, one with `times_applied`=15, and a frontend API-client task was served six ranked
  lessons, all six about credits. A frequency ranker amplifies exactly that. Any lessons-retrieval
  path must rank on content match, NOT reuse the skills path's `usage_count` popularity fallback.
  Both are FLEETVIS-1 scope 4 (`CASE-20260914-C68F55`).

**Context compression** (s3, `dispatch.sh` RUNNER block):
- `CONTEXT_COMPRESS_MAX_CHARS` env var (default 100 000) — if `TASK_CONTENT` exceeds this threshold the runner truncates it with a `[... context truncated ...]` suffix before building `FULL_PROMPT`. Prevents hitting the model context ceiling on retried tasks with large accumulated `prior_errors`.
- Context compressor service: `backend/app/services/context_manager.py` (`ContextManager`, `compress_context_pack`, `compress_prior_errors`, `update_case_compression_metrics`).

**Cache-awareness patterns for agents**:
- Do NOT add `setTimeout`/background TTL sweeps — use lazy expiry (check on read). Test-safe.
- `NoopSkillCache` is the test-safe default for all node factories. Pass the real `defaultSkillCache` only in production exports.
- Never let cache errors propagate — always wrap `cache.set()` in `.catch(() => {})`.
- Return shape must be identical for cache hits and misses — never coerce the cached value.
- Cache keys must include ALL inputs that affect the output (but exclude volatile inputs like learnings).

## Fleet Safety Flags — orchestrator security audit 2026-09-15
Five guards added after an audit of the agent-dispatch path. Each ships with a kill switch and each
default is stated here, not only in the commit. Orchestrator flags are Railway service env vars on
`orchestrator`; backend flags are on the backend service. Railway env vars are STATIC copies —
changing Doppler alone does nothing until the service copy is refreshed.

| Flag | Default | What OFF restores |
|---|---|---|
| `ORCH_LANE_A_DEFAULT_DENY` | ON | Lane A allow-by-default for unclassified task keys |
| `ORCH_TOKEN_FLOOR_ENABLED` | ON | Token budget charged on the runner's self-report alone |
| `ORCH_ALIGN_RUNNER_TIMEOUT` | ON | Runner watchdog left at its own default (90 min) |
| `DISPATCH_FENCE_ENABLED` | ON | A superseded run may report over the run that replaced it |
| `SPEND_GROUND_TRUTH` | ON (observe only) | No Anthropic cost-report call, no spend logging |
| `SPEND_GROUND_TRUTH_ENFORCE` | **OFF** | — (turning it ON makes ground truth gate auto-assign) |
| `ANTHROPIC_MONTHLY_CEILING_USD` | unset = off | — (set to a positive number to arm the monthly halt) |

**Flag direction — the rule for all of these.** A guard that is ON by default is turned off ONLY by an
explicit off value (`0`/`false`/`no`/`off`). Any other string, including a typo, leaves it ON. The
default-OFF flags (`SPEND_GROUND_TRUTH_ENFORCE`) keep the opposite rule: only an explicit truthy
value turns one on. Written this way on purpose — the obvious `value in (truthy set)` spelling means
a typo in a variable meant to enable protection silently disables it, which is the failure mode these
guards exist to prevent.

**Lane A default-deny** (`orchestrator/src/lib/model-router.ts`). Lane A is a third party
(OpenRouter). An unclassified task key used to fall through to `privacy: "standard"` and became
Lane-A-eligible the moment `MODEL_ROUTING_JSON` named it; the other half of the gate,
`opts.dataPolicy`, is never set by ANY caller in `orchestrator/src` and never was. Measured live on
the Railway `orchestrator` service 2026-09-15: `finalize`, `knowledge-select`, `compliance-check`
and `learning-extract` were routed to Lane A, sending human rejection notes, review policy flags,
error strings and outlines of up to 30 `orchestrator_knowledge` rows off-platform. Unclassified now
means `critical`, which filters Lane A out of the cascade (Lane C is untouched — the filter only
removes A). Making a key Lane-A-eligible is now explicit: add it to `TASK_PRIVACY_DEFAULTS` as
`"standard"`, or set `"privacy":"standard"` on its `MODEL_ROUTING_JSON` entry.
Separately and unconditionally: every OpenRouter request now carries
`provider.data_collection: "deny"`. It used to be gated on a flag that was only ever true when Lane A
had ALREADY been removed from the cascade — so the retention opt-out was attached to exactly the
requests that were never sent, and never to the ones that were.

**Token floor** (`orchestrator/src/lib/token-accounting.ts`). The 8M budget is enforced against a
number the budgeted process prints about itself on stdout. An absent field became 0, and every
error/timeout path hardcodes 0 — so a run that burned 60 minutes and timed out charged NOTHING and
was retried, each attempt free. Unreported wall-clock past a grace window is now charged a floor
(`ORCH_TOKENS_PER_MINUTE_FLOOR`, default 25000/min) and an absurd report is clamped
(`ORCH_TOKEN_REPORT_CEILING`, default 20000000). `exec_result` still carries the runner's own claim
untouched; only the accumulating budget counter is corrected.

**Timeout alignment.** The orchestrator abandons a run at 60 min (`EXEC_TIMEOUT_MS`) while the
runner's own watchdog is 90 min (`ORCH_TIMEOUT_SECS`, `agents/scripts/orchestrator-run.sh`) — so the
orchestrator gives up on a process that is still alive and can still push. The orchestrator now
derives the runner's watchdog from its own deadline minus `ORCH_RUNNER_TIMEOUT_MARGIN_SECS`
(default 300) and passes it in the per-run env file, so the two cannot invert. An explicit
`ORCH_TIMEOUT_SECS` in a task's `run_env` still wins.

**Dispatch fence** (`backend/app/services/dispatch_fence.py`). Consequence of the same gap: after an
abandon the case returns to `plan_approved` and is re-dispatched, and the first runner — which
survives, because the abandon sends TERM only with no follow-up KILL and swallows SSH failures —
can later POST `done`. `_set_case_status_notify` is an unconditional UPDATE, so the case flips over
the top of the live run, and because `reportProgress` sends no `dispatch_id` the stale report closes
the NEW run's dispatch row. The fence refuses a report whose `dispatch_id` names a superseded run
while a newer one is live. It is NOT an auth control: it runs after auth and fails open on every
uncertain path, including DB errors.

**Ground-truth spend** (`backend/app/services/anthropic_spend.py`). `llm_usage_log` is NOT spend —
it only records calls through the model router's telemetry hook. Measured: $67.82 logged for a
30-day window the org actually billed $2,957.41 for, about 2%. Everything on the Claude Code CLI
(the fleet, the review-gate cron, interactive sessions) is invisible to it, which is why the
`daily_budget_usd` gate never saw the org-level ceiling that stopped the fleet for 15+ hours on
2026-09-15. The Anthropic organization cost report is now read as ground truth — cents to dollars,
divided by 100 EXACTLY ONCE (the API returns `amount` in cents while labelling rows `"currency":
"USD"`).
**Enforcement is OFF on purpose.** Measured actual account-wide spend runs $14-$763/day against a
configured `daily_budget_usd` of 100, so switching `SPEND_GROUND_TRUTH_ENFORCE` on without first
raising that number halts auto-assign on the next tick. Observe mode logs both figures side by side
and says what enforcement WOULD have done. Set a real daily budget first, then enable. The cost
report is ACCOUNT-WIDE and cannot be split per grotap org — never present it as per-tenant spend.

## Codex Review Workflow
Plan-Implement-Review: Claude plans/implements, Codex audits.
- **Before every commit**: a Codex review — block commit if issues found. The `/codex:*` commands are
  user-invoke-only (`disable-model-invocation`); in autonomous sessions Claude drives the codex
  companion runtime directly (see the `codex-cli-runtime` skill contract) instead of skipping review.
- **Security/complex**: `/codex:adversarial-review --background` · **Stuck >2 attempts**: `/codex:rescue`
- Codex reviews complement the Rule 7 agent pipeline — they do NOT replace 4-reviewer sign-off.

## Agent Dispatch — Turn Budgets & Protocol

### Turn budget by complexity (`--max-turns`)
| `complexity:` | `--max-turns` | Intended scope |
|---|---|---|
| `simple` | 20 | Trivial one-file fix, clear spec |
| `medium` | 40 | Single-screen feature, well-defined |
| `complex` | 80 | Multi-file refactor, architectural change |
| (unset) | 80 | Safe default — same as complex |

Cap each coalesced batch so the full run finishes within ~80 turns. Oversized tasks exhaust
the turn budget partway and waste the slot (CLAUDE.md § Coalescing).

### DISPATCH_PROTOCOL env var (Team Claude (team1) only)
Set in the caller's environment before calling `agents/dispatch.sh`:
- **`legacy`** (default): inline RUNNER — reads markdown, runs Claude, commits, pushes.
  Byte-identical to all pre-protocol dispatches; safe for all existing automation.
- **`orchestrator`**: converts the task markdown to JSON and delegates to
  `agents/scripts/orchestrator-run.sh`, which adds: 90-min wall-clock timeout watchdog,
  structured JSON result emission (parseable by the orchestrator), and a `tsc`/`py_compile`
  verification gate before push. Use for tasks where structured output or the timeout
  watchdog matter (e.g. tasks submitted through the LangGraph orchestrator manually).

  Example: `DISPATCH_PROTOCOL=orchestrator bash agents/dispatch.sh <task.md> <ip> <session>`

### Troubleshooting dispatch failures
- **No commits produced** — check the session log (`tail -f ~/logs/<session>.log`) for
  `CLAUDE_STDERR`; usually a model/API error or a task that needed no code change
  (add `no_commit_ok: true` in frontmatter if the task is intentionally analysis-only).
- **HMAC verification failed** — `NODE_SECRET` unavailable on the runner; verify
  `doppler secrets get NODE_SECRET --plain` works on the server as the `agent` user.
- **API exhausted** — Anthropic credit limit hit; the dispatch row is flagged `api_exhausted`
  (no retry strike consumed); any partial commits are preserved on the branch.
- **team pool empty/unreachable** — provisioning incomplete or server down; dispatch logs
  the skip and falls back to Team Claude automatically.
- **tmux session conflict** — `ssh root@<ip> "su - agent -c 'tmux kill-session -t <session>'"`,
  then re-dispatch.
- **`DIRTY_TREE` or `DETACHED_HEAD`** in `agents/logs/bootstrap-sync-fail.json` — another
  session left uncommitted state in `$REPO`; run `git status` and resolve before next dispatch.
