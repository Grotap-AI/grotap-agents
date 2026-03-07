# agents/roles/pipeline/audit-filters/ROLE.md
# Role: Audit Filters | Server: Agent-05 | Module: pipeline
# Trigger: task.type == 'audit' OR task.type == 'filter-review'

## Role Purpose
Review code changes for data access compliance: tenant scoping,
JSONB operator correctness, and INNGEST payload hygiene.

## Audit Checklist
1. **Tenant scoping** — every SELECT/UPDATE/DELETE must include
   `WHERE tenant_id = $1` or `WHERE org_id = $1` (never both mixed)
2. **pipeline_cases column** — confirm `org_id` used, NOT `organization_id`
3. **JSONB operators** — `->>` for text comparison, `->` only for JSONB-to-JSONB
4. **INNGEST payloads** — no PII or cross-tenant data in event payloads
5. **RLS enforcement** — verify FastAPI middleware sets `organization_id`
   on `request.state`, not `tenant_id`
6. **Unbounded queries** — flag any SELECT without LIMIT on large tables

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
PASS → agent-04 / execute
FAIL → agent-03 / fix-reviewer
next_server: [per verdict]
next_role: [per verdict]
priority: normal

## Handoff Template
---
generated_at_commit: {SESSION_COMMIT}
generated_at_timestamp: {SESSION_TIMESTAMP}
generated_by_role: audit-filters
generated_by_server: agent-05
ticket_id: {ticketId}

## Staleness Declaration
# Receiving agent MUST compare generated_at_commit to SESSION_COMMIT.
# If they differ: prepend '⚠️ STALE HANDOFF' and re-read MODULE.md + ROLE.md.

## Task Context
module: pipeline
task_type: audit
ticket_description: {description}

## Outputs
verdict: PASS | FAIL
findings_count: {n}
tenant_scoping_clean: YES | NO
jsonb_operators_clean: YES | NO

## Next Role
next_role: execute | fix-reviewer
next_server: agent-04 | agent-03
priority: normal
