# agents/roles/pipeline/pipeline-detail/ROLE.md
# Role: Pipeline Detail | Server: Agent-05 | Module: pipeline
# Trigger: task.type == 'pipeline' AND task.detail == true

## Role Purpose
Provide detailed status reporting on a branch's review pipeline progress.
Identify which reviewers have responded, what verdicts were returned,
and what actions are needed to unblock a stalled review.

## Checklist
1. Identify the branch under review from task context
2. Check collect-reviews output for all 4 reviewer verdicts
3. For each FAIL: summarize the finding and the file:line cited
4. For each pending reviewer: report last known status
5. Recommend next action: fix and re-submit, or escalate

## Output Format
```
PIPELINE STATUS — ticket #{ticket_id}
Branch: {branch}

| Reviewer        | Status           | Notes     |
|---|---|---|
| Security        | PASS/FAIL/PENDING | {summary} |
| Logic           | PASS/FAIL/PENDING | {summary} |
| Perf            | PASS/FAIL/PENDING | {summary} |
| Build Validator | PASS/FAIL/PENDING | {summary} |

Overall: APPROVED | BLOCKED | IN-REVIEW
Next action: {recommendation}
```

## Handoff
BLOCKED  → agent-03 / fix-reviewer (to address FAIL findings)
APPROVED → agent-04 / execute (ready for execution)
next_server: [per overall status]
next_role: [per overall status]

## Handoff Template
---
generated_at_commit: {SESSION_COMMIT}
generated_at_timestamp: {SESSION_TIMESTAMP}
generated_by_role: pipeline-detail
generated_by_server: agent-05
ticket_id: {ticketId}

## Staleness Declaration
# Receiving agent MUST compare generated_at_commit to SESSION_COMMIT.
# If they differ: prepend '⚠️ STALE HANDOFF' and re-read MODULE.md + ROLE.md.

## Task Context
module: pipeline
task_type: pipeline
ticket_description: {description}

## Outputs
overall_status: APPROVED | BLOCKED | IN-REVIEW
reviewers_passed: {list}
reviewers_failed: {list or NONE}
reviewers_pending: {list or NONE}

## Next Role
next_role: fix-reviewer | execute
next_server: agent-03 | agent-04
priority: normal | urgent
