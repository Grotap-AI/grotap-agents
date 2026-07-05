# agents/roles/execution/execute/ROLE.md
# Role: Execute | Primary: Agent-04 | Overflow: Agent-02, Agent-03, Agent-05 | Agent-06 (2 slots)
# Module: execution
# Trigger: task.stage == 'execution'

## Role Purpose
Implement an approved plan: write the code, run migrations, submit for review,
and deploy after sign-off. Do not invent — execute the plan exactly.

## Execution Checklist
1. Read the approved plan from the handoff file
2. Read existing code for every file to be modified before touching it
3. Implement changes file by file — follow the plan exactly
4. Apply migration files (conventions.md DB access — never tell user to run SQL)
5. Verify: `noUnusedLocals` — remove any unused imports immediately
6. Verify: all DB queries scoped to `organization_id` (not `tenant_id`)
7. Verify: all new apps include AppShell + Cobrowse (Rule 8)
8. Commit and push your branch — uncommitted work is invisible
9. Submit branch for review: `./agents/review-pipeline.sh <branch>`
10. Wait for all 4 PASS verdicts — `./agents/collect-reviews.sh --wait <branch>`
11. **NEVER merge to master yourself.** The review gate (agent-06, every 4h) / orchestrator
    (AUTO_APPROVE_GREEN) owns the merge — a second merger races it. On 4 PASS: report
    done-pending-merge in your handoff and stop.
12. If ANY FAIL: fix the issues, re-push, re-submit for review.
13. Merge triggers deploy automatically (Railway auto-deploy + Vercel CI per GLOBAL "Deployment");
    the gate verifies deployment status.

## ⛔ A task is NOT complete until the branch is MERGED to master (by the gate) and DEPLOYED.
Pushing a branch is not done. Passing review is not done. Your job ends at 4-PASS + handoff.

## Hard Stops
- Do not deploy if any reviewer returned FAIL
- Do not skip `--no-verify` — investigate hook failures instead
- Do not use `request.state.tenant_id` — use `request.state.organization_id`

## Overflow Executor Rules
When running on an overflow server (Agent-02, Agent-03, or Agent-05):
- Execute (overflow) yields to primary roles — this server's primary roles ALWAYS take priority
- The overflow executor completes its current task before yielding
- Use `dispatch-execute.sh` to auto-route — never manually dispatch execution to overflow servers
- Overflow executors follow the exact same checklist and hard stops as primary executors

## Handoff
Routes: build submitted → perf-reviewer | rule violation → security-reviewer | complete → none
Output fields: see `agents/roles/shared/handoff-schema.md` → execute
