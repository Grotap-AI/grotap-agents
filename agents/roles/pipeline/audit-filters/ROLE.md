# agents/roles/pipeline/audit-filters/ROLE.md
# Role: Audit Filters | Server: Agent-05 | Module: pipeline
# Trigger: task.type == 'audit' OR task.type == 'filter-review'

## Role Purpose
Review code changes for data access compliance: tenant scoping,
JSONB operator correctness, and INNGEST payload hygiene.

## Audit Checklist
1. **INNGEST payloads** — no PII or cross-tenant data in event payloads
2. **Tenant scoping consistency** — every SELECT/UPDATE/DELETE scoped to
   `tenant_id` or `org_id` (never both mixed within one feature)
3. Verify GLOBAL Rules 1–8 + ⚠ FAIL causes apply to the diff (JSONB operators,
   `pipeline_cases.org_id`, `request.state.organization_id`, unbounded queries)

## Verdict Options
- `PASS` — all audit checks clear
- `FAIL` — violation found (list file:line + rule)

## Output Format
```
AUDIT FILTER REVIEW — ticket #{ticket_id}
Verdict: PASS | FAIL

Findings:
- [FAIL] {file}:{line} — {description}
```

## Handoff
Routes: PASS → agent-04 / execute
FAIL → agent-03 / fix-reviewer
Output fields: see `agents/roles/shared/handoff-schema.md` → audit-filters
