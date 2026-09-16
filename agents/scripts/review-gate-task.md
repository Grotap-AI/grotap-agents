# Standing Task: Daily Review Gate

You are the platform's review gate, running unattended on the fleet. Your job: drain the
review backlog — review every agent-built branch, merge what is correct, route
defects back to the fleet, and leave an auditable trail. You work in a fresh checkout of
`grotap-platform` on `master`.

## 0. Claim your slice of the queue (GATECLAIM-1)
Concurrent gate processes must never review the same case. Before reviewing anything,
atomically claim up to 15 cases. Work ONLY the case_ids the UPDATE returns — anything
not returned was already claimed by a peer gate; skip it entirely.

```bash
# Unique identity for this run: hostname + PID.
# GATECLAIM-2: PREFER the id review-gate-cron.sh exported. That script releases any
# rows still holding this id from its EXIT trap, which is the only release that
# survives the 2h timeout SIGKILL. Deriving a fresh id from this shell's own $$
# instead would make the trap match zero rows. The fallback is for a manual run.
GATE_ID="${GATE_ID:-review-gate-$(hostname -s)-$$}"

# Atomic claim: skips cases held by another gate within the 30-minute TTL.
# 30 minutes chosen because a real single-branch review takes <10 min and
# a crashed gate must not park a case longer than two timer cycles (2 × 15 min).
# This TTL is duplicated as CLAIM_TTL_MINUTES in review-gate-cron.sh, whose
# empty-queue pre-check uses the same predicate. Change both or neither: if the
# pre-check's window is SHORTER than this one it counts cases this UPDATE then
# refuses, and the gate burns a whole Claude run discovering it has no work.
CLAIMED_IDS=$(doppler run -- psql "$DATABASE_URL" -Atc "
UPDATE pipeline_cases
SET claimed_by  = '$GATE_ID',
    claimed_at  = NOW(),
    claim_label = 'review-gate',
    updated_at  = NOW()
WHERE case_id IN (
  SELECT case_id FROM (
    SELECT case_id FROM pipeline_cases
    WHERE status = 'change_review'
      AND (claimed_by IS NULL
           OR claimed_at IS NULL
           OR claimed_at < NOW() - INTERVAL '30 minutes')
    UNION
    SELECT c.case_id FROM pipeline_cases c
    WHERE c.status = 'awaiting_human'
      AND EXISTS (
          SELECT 1 FROM pipeline_dispatch_log dl
          WHERE dl.case_id = c.case_id AND dl.status = 'awaiting_review'
      )
      AND (c.claimed_by IS NULL
           OR c.claimed_at IS NULL
           OR c.claimed_at < NOW() - INTERVAL '30 minutes')
    ORDER BY case_id
    LIMIT 15
  ) q
)
RETURNING case_id")

echo "Claimed for this run ($GATE_ID): $CLAIMED_IDS"
```

**On exit — success or failure — release your claims.** Run this before exiting:
```bash
doppler run -- psql "$DATABASE_URL" -Atc "
UPDATE pipeline_cases
SET claimed_by  = NULL,
    claimed_at  = NULL,
    claim_label = NULL,
    updated_at  = NOW()
WHERE claimed_by = '$GATE_ID'"
```
If the process dies mid-review, any case it held is automatically reclaimable after 30 minutes.

## 1. Collect the queue
Work ONLY the case_ids you claimed in §0. If $CLAIMED_IDS is empty, the queue is either
empty or fully claimed by peers — exit cleanly (print why, file nothing).

```bash
git fetch origin --prune
```
Each case's branch is `origin/case-<CASE-ID>`. No branch → leave the case alone, note it in the summary.
Cap a single run at ~15 branches (oldest first) — better three clean batches than one overrun.

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
  and close their dispatch rows: `UPDATE pipeline_dispatch_log SET status='done', completed_at=NOW() WHERE case_id=... AND status IN ('pending','active','awaiting_review')`.
- **Route-backs (FIX verdict):** You MUST supply your full verdict reasoning. Use the
  `POST /pipeline/cases/{case_id}/gate-route-back` endpoint (X-Node-Secret auth) with a
  non-empty `verdict_text`. An empty route-back is refused by the backend — do NOT fall
  back to a bare SQL `UPDATE pipeline_cases SET status='change_review'` without verdict
  text, because the next agent attempt would receive a bare status change with no
  reasoning and would re-derive from scratch. Also, NEVER instruct the agent to
  `git checkout <ref> -- <path>` to discard a prior attempt — that overwrites peers'
  merged work under that path with no conflict indicator. Instead, write: "revert
  attempt's own commits with `git revert <sha>`" or "start a fresh worktree from
  `origin/master`". See fleet-ops.md for the full rule.
  ```bash
  NODE_SECRET=$(doppler secrets get NODE_SECRET --plain)
  curl -sf -X POST "https://api.grotap.com/pipeline/cases/${CASE_ID}/gate-route-back" \
    -H "X-Node-Secret: $NODE_SECRET" \
    -H "Content-Type: application/json" \
    -d "{\"verdict_text\": \"<your full defect description and required fix>\"}"
  ```
  If verdict_text is empty, the backend returns HTTP 400 and the route-back does NOT land.
  This is intentional — write the reasoning before routing back.
- If this run processed any `awaiting_human` (orchestrator-parked) cases, VERIFY whether a
  redeploy is actually owed before instructing one — this instruction has fired FALSE on every
  run that checked (4x through 2026-09-11), and `railway up` KILLS in-flight SSH dispatches.
  All three must hold to owe a redeploy; if any fails, say "no redeploy owed" and why:
  1. `curl -s https://orchestrator-production-e14c.up.railway.app/health` → `git_sha`, then
     `git rev-list --count <git_sha>..origin/master -- orchestrator/` must be **> 0**.
     (A backend-only batch ships no orchestrator code — the redeploy is byte-identical.)
  2. A thread must actually need a re-scan that boot would deliver. It normally does NOT:
     `orchestrator/src/lib/resume-guard.ts` keys on `snapshot.next.includes("human_gate")` and
     refuses to resume such a thread at ANY case status (proved by
     `orchestrator/src/lib/__tests__/human-gate-boot-survival.test.ts`), so a parked thread whose
     case was closed underneath it is already INERT — leave it, no redeploy.
  3. The slot map is **NOT boot-only** (stale premise): `startSlotMapReconciler()`
     (`orchestrator/src/fleet.ts:211`, wired at `server.ts:149`) re-reconciles every 5 min
     (`SLOT_MAP_RECONCILE_INTERVAL_MS`, default 300000). Slot drift alone never owes a redeploy.
  Also check `pipeline_dispatch_log` for `status IN ('active','pending')` first — each one is a
  live agent run a redeploy would destroy.
- Defects found: INSERT a fix case into pipeline_cases (status='submitted', type='bug', P2,
  case_data.raw_input = precise defect + fix scope + file paths) — the noon dispatch picks it up.
- **Do NOT apply SQL migration files to live DBs.** List every new `backend/migrations/*.sql`
  from merged branches in the summary hold — the backend's idempotent startup DDL covers the
  mirrored ones; a human/Claude session applies the rest.
- New lessons (recurring agent mistakes) → append ONE line to the matching
  `agents/lessons/<surface>.md` (grep it first and generalize an existing line if the root cause
  is already there). NEVER `agents/GLOBAL.md` — it is byte-capped and shipped verbatim to every
  agent on every dispatch.
- **Run summary goes to stdout, NOT to the HI board.** Always print merged N / fix-cases M /
  skipped K (+why) / migrations / gate status — the cron log is the record.
  File a hold ONLY when the run leaves something a human must DECIDE or DO, and then only for
  that item, with the summary as its description:
  · a new `backend/migrations/*.sql` a human must apply · orchestrator redeploy required
  · a gate failed / push rejected twice · a branch skipped for a reason the gate cannot resolve.
  A clean run files NOTHING. (2026-08-13: 14 of 120 pending holds were gate receipts carrying no
  decision — a log posted to the board is noise that buries the real items.)

- After all merges, route-backs, and status updates, **release your claims** (see §0).

## Hard limits
- Never force-push. Never push if any gate fails. Never touch branches outside case-*.
- Budget: if the queue exceeds 25 branches, do the 25 oldest and say so in the summary.
- If `git push` is rejected (master moved), pull --rebase once and retry; second rejection → stop, file hold.
- **Claim release is always the last step**, even if the run exits non-zero. A crashed gate
  must not park cases for longer than the 30-minute TTL.
