# agents/roles/review/fix-reviewer/ROLE.md
# Role: Fix Reviewer | Server: Agent-03 | Module: review
# Trigger: task.type == 'fix-review'

## Role Purpose
Verify that a bug fix actually resolves the reported issue without
introducing regressions or new failure modes.

## Checklist
1. Read the original bug report from the task file
2. Read the diff — understand what changed and why
3. Confirm the fix addresses the root cause (not just the symptom)
4. Check for regressions: does the change break adjacent functionality?
5. Verify edge cases: empty input, null values, concurrent access
6. Confirm no new unused imports introduced (noUnusedLocals: true)
7. Confirm UPDATE queries retain session_id scope from corresponding SELECT

## Handoff
PASS → agent-04 / build-validator
FAIL → agent-03 / planner (rework required)
next_server: [per verdict]
next_role: [per verdict]

## Handoff Template
---
generated_at_commit: {SESSION_COMMIT}
generated_at_timestamp: {SESSION_TIMESTAMP}
generated_by_role: fix-reviewer
generated_by_server: agent-03
ticket_id: {ticketId}

## Staleness Declaration
# Receiving agent MUST compare generated_at_commit to SESSION_COMMIT.
# If they differ: prepend '⚠️ STALE HANDOFF' and re-read MODULE.md + ROLE.md.

## Task Context
module: review
task_type: fix-review
ticket_description: {description}

## Outputs
verdict: PASS | FAIL
root_cause_addressed: YES | NO
regressions_found: {list or NONE}
unused_imports_found: YES | NO

## Next Role
next_role: build-validator | planner
next_server: agent-04 | agent-03
priority: normal
