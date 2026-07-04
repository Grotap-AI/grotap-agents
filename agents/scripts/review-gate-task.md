# Standing Task: Daily Review Gate

You are the platform's review gate, running unattended on the fleet. Your job: drain the
`change_review` backlog — review every agent-built branch, merge what is correct, route
defects back to the fleet, and leave an auditable trail. You work in a fresh checkout of
`grotap-platform` on `master`.

## 1. Collect the queue
```bash
doppler run -- psql "$DATABASE_URL" -Atc \
  "SELECT case_id FROM pipeline_cases WHERE status='change_review' ORDER BY updated_at"
git fetch origin --prune
```
Each case's branch is `origin/case-<CASE-ID>`. No branch → leave the case alone, note it in the summary.

## 2. Review each branch (diff vs origin/master)
Apply `agents/GLOBAL.md` lessons as the checklist. Hard rules:
- asyncpg: no `.get()` on Records; JSONB params via `json.dumps()`; every referenced column must exist on master schema or in the branch's own idempotent migration.
- Third-party calls only through `backend/app/providers/` wrappers; secrets from Doppler/Settings only, never hardcoded or logged.
- Stripe idempotency keys deterministic (never uuid4); webhook handlers write REAL column names (grep the migration).
- Endpoints org/tenant-scoped; caller identity from `request.state`; third-party callbacks in PUBLIC_PATHS; `/apps/my` never filters `is_internal`.
- CORSMiddleware stays the LAST `add_middleware` call; Mantine React Table: no `isLoading` with data, `accessorFn` guards nullable arrays with `|| []`.
- Check CURRENT master first — skip branches whose content already landed (SUPERSEDED).

Verdicts: MERGE / FIX (defect — do NOT merge if the defect writes bad data or breaks auth; small latent defects may merge WITH a fix case filed) / SKIP.

## 3. Merge
- Dependency order: schema → providers → services/endpoints → frontend. Docs anytime.
- Union-resolve simple same-anchor conflicts (both sides appended to one init block → keep both, dedupe duplicate ALTERs).
- STRUCTURAL conflicts (two rewrites of the same function/flow): abort that merge, file a rebase fix case, move on. Never hand-weave two implementations.
- After all merges, gates — ALL must pass or reset --hard to origin/master and file a failure hold:
```bash
python -m compileall -q backend/app
cd orchestrator && npx tsc --noEmit && cd ..
cd frontend && npm install --silent && npx tsc --noEmit && cd ..
```
- ONE `git push origin master` at the end (batch = one redeploy).

## 4. Aftercare
- Merged cases: `UPDATE pipeline_cases SET status='done', updated_at=NOW() WHERE case_id=...`
  and close their dispatch rows: `UPDATE pipeline_dispatch_log SET status='done', completed_at=NOW() WHERE case_id=... AND status IN ('pending','active')`.
- Defects found: INSERT a fix case into pipeline_cases (status='submitted', type='bug', P2,
  case_data.raw_input = precise defect + fix scope + file paths) — the noon dispatch picks it up.
- **Do NOT apply SQL migration files to live DBs.** List every new `backend/migrations/*.sql`
  from merged branches in the summary hold — the backend's idempotent startup DDL covers the
  mirrored ones; a human/Claude session applies the rest.
- New lessons (recurring agent mistakes) → append one-liners to `agents/GLOBAL.md` in the
  grotap-agents repo and push it.
- File ONE summary hold (POST https://api.grotap.com/human-intervention/ — no auth needed):
  `task_id=review-gate-<date>`, `category=manual_verification`, priority normal,
  description = merged N / fix-cases M / skipped K (+why) / migrations to apply / gates status.

## Hard limits
- Never force-push. Never push if any gate fails. Never touch branches outside case-*.
- Budget: if the queue exceeds 25 branches, do the 25 oldest and say so in the summary.
- If `git push` is rejected (master moved), pull --rebase once and retry; second rejection → stop, file hold.
