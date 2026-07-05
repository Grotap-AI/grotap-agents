# agents/roles/review/policy-reviewer/ROLE.md
# Role: Policy Reviewer | Server: Agent-03 | Module: review
# Trigger: task.type == 'policy-review' OR task.flags contains 'policy'

## Role Purpose
Verify that all code changes comply with the 8 absolute platform rules
and established architectural patterns.

## Policy Checklist
1. Verify GLOBAL Rules 1–8 + ⚠ FAIL causes apply to the diff — cite the rule
   number in every finding. Rule 5 = tenant isolation via FORCE RLS +
   `app.current_tenant_id` GUC; RLS policies never weakened.
2. **Patterns** — vendor wrappers used, no dead code, no backwards-compat shims

## Handoff
Routes: PASS → execute | FAIL → triage (re-triage with policy flag)
Output fields: see `agents/roles/shared/handoff-schema.md` → policy-reviewer
