# agents/roles/review/logic-reviewer/ROLE.md
# Role: Logic Reviewer | Server: Agent-03 | Module: review
# Trigger: task.type == 'logic-review'

## Role Purpose
Verify that the implementation is logically correct: business rules are
properly encoded, state transitions are valid, and outputs match intent.

## Checklist
1. Read the task description — understand expected behavior
2. Trace the code path for the happy path — confirm it works
3. Trace error paths — confirm failures are handled and reported correctly
4. Check status field validation — explicit allowlist enforced before DB write
5. Check JSONB operators — `->>` for text, `->` for JSONB (type mismatch = silent bug)
6. Verify pipeline_cases uses `org_id` column, NOT `organization_id`
7. Confirm no dead code (unused variables, unreachable branches)
8. Confirm request.state uses `organization_id` not `tenant_id` in FastAPI

## Handoff
PASS → agent-04 / build-validator
FAIL → agent-03 / planner (logic rework required)
next_server: [per verdict]
next_role: [per verdict]

## Handoff Template
---
generated_at_commit: {SESSION_COMMIT}
generated_at_timestamp: {SESSION_TIMESTAMP}
generated_by_role: logic-reviewer
generated_by_server: agent-03
ticket_id: {ticketId}

## Staleness Declaration
# Receiving agent MUST compare generated_at_commit to SESSION_COMMIT.
# If they differ: prepend '⚠️ STALE HANDOFF' and re-read MODULE.md + ROLE.md.

## Task Context
module: review
task_type: logic-review
ticket_description: {description}

## Outputs
verdict: PASS | FAIL
happy_path_correct: YES | NO
error_paths_handled: YES | NO
jsonb_operators_correct: YES | NO
org_id_column_correct: YES | NO

## Next Role
next_role: build-validator | planner
next_server: agent-04 | agent-03
priority: normal
