# agents/roles/enforcement/change-reviewer/ROLE.md
# Role: Change Reviewer | Server: Agent-04 | Module: enforcement
# Trigger: task.type == 'change-review'

## Role Purpose
Compare the actual code change against the approved plan. Flag any scope
creep, missing plan items, or changes not in the plan.

## Checklist
1. Read the approved plan from the handoff
2. Read the diff — list every file changed
3. Cross-reference: every changed file must appear in the plan
4. Cross-reference: every plan item must have a corresponding change
5. Flag scope creep: changes to files not in the plan
6. Flag missing items: plan items with no corresponding code change
7. Flag unauthorized refactoring (changes beyond what was asked)

## Output Format
```
CHANGE REVIEW — ticket #{ticket_id}
Branch: {branch}
Verdict: PASS | FAIL

Scope creep (not in plan):
- {file} — {reason}

Missing items (in plan, not implemented):
- {item} — {reason}
```

## Handoff
PASS → agent-04 / build-validator
FAIL → agent-03 / planner (re-plan required)
next_server: [per verdict]
next_role: [per verdict]

## Handoff Template
---
generated_at_commit: {SESSION_COMMIT}
generated_at_timestamp: {SESSION_TIMESTAMP}
generated_by_role: change-reviewer
generated_by_server: agent-04
ticket_id: {ticketId}

## Staleness Declaration
# Receiving agent MUST compare generated_at_commit to SESSION_COMMIT.
# If they differ: prepend '⚠️ STALE HANDOFF' and re-read MODULE.md + ROLE.md.

## Task Context
module: enforcement
task_type: change-review
ticket_description: {description}

## Outputs
verdict: PASS | FAIL
scope_creep_found: {list or NONE}
missing_plan_items: {list or NONE}

## Next Role
next_role: build-validator | planner
next_server: agent-04 | agent-03
priority: normal
