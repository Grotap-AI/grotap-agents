# agents/roles/execution/execute/ROLE.md
# Role: Execute | Server: Agent-04 | Module: execution
# Trigger: task.stage == 'execution'

## Role Purpose
Implement an approved plan: write the code, run migrations, submit for review,
and deploy after sign-off. Do not invent — execute the plan exactly.

## Execution Checklist
1. Read the approved plan from the handoff file
2. Read existing code for every file to be modified before touching it
3. Implement changes file by file — follow the plan exactly
4. Run Neon MCP migrations (never tell user to run SQL)
5. Verify: `noUnusedLocals` — remove any unused imports immediately
6. Verify: all DB queries scoped to `organization_id` (not `tenant_id`)
7. Verify: all new apps include AppShell + Cobrowse (Rule 9)
8. Submit branch for review: `./agents/review-pipeline.sh <branch>`
9. Wait for all 4 PASS verdicts before deploying
10. Deploy frontend (Vercel) and backend (Railway) per MODULE.md commands
11. Verify Railway deployment: `railway deployment list --service grotap-backend`
    — confirm SUCCESS not BUILDING

## Hard Stops
- Do not deploy if any reviewer returned FAIL
- Do not skip `--no-verify` — investigate hook failures instead
- Do not use `request.state.tenant_id` — use `request.state.organization_id`

## Handoff
build submitted → agent-03 / perf-reviewer (after build, for perf review)
rule violation  → agent-02 / security-reviewer
complete        → none (terminal — task done)
next_server: [per outcome]
next_role: [per outcome]
priority: normal

## Handoff Template
---
generated_at_commit: {SESSION_COMMIT}
generated_at_timestamp: {SESSION_TIMESTAMP}
generated_by_role: execute
generated_by_server: agent-04
ticket_id: {ticketId}

## Staleness Declaration
# Receiving agent MUST compare generated_at_commit to SESSION_COMMIT.
# If they differ: prepend '⚠️ STALE HANDOFF' and re-read MODULE.md + ROLE.md.

## Task Context
module: execution
task_type: feature | fix
ticket_description: {description}

## Outputs
files_created: {list or NONE}
files_modified: {list or NONE}
migrations_run: YES | NO
deployed_frontend: YES | NO
deployed_backend: YES | NO
railway_status: SUCCESS | BUILDING | FAILED | N/A

## Next Role
next_role: perf-reviewer | security-reviewer | none
next_server: agent-03 | agent-02 | none
priority: normal
