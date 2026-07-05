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
Routes: PASS → build-validator | FAIL → planner (rework)
Output fields: see `agents/roles/shared/handoff-schema.md` → fix-reviewer
