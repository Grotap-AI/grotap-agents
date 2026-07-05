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
Routes: PASS → agent-04 / build-validator
FAIL → agent-03 / planner (re-plan required)
Output fields: see `agents/roles/shared/handoff-schema.md` → change-reviewer
