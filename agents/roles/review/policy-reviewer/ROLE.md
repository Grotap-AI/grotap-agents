# agents/roles/review/policy-reviewer/ROLE.md
# Role: Policy Reviewer | Server: Agent-03 | Module: review
# Trigger: task.type == 'policy-review' OR task.flags contains 'policy'

## Role Purpose
Verify that all code changes comply with the 9 absolute platform rules
and established architectural patterns.

## Policy Checklist
1. **Rule 1** — No secrets outside Doppler; no inline tokens
2. **Rule 2** — No Python agent code; TypeScript only for agents
3. **Rule 3** — No direct 3rd-party SDK calls outside `app/providers/`
4. **Rule 4** — All DB queries scoped to `tenant_id`
5. **Rule 5** — No shared schemas; database-per-tenant enforced
6. **Rule 6** — Compliance checker node present and not bypassed
7. **Rule 7** — No pgvector similarity search; PageIndex only
8. **Rule 8** — Branch has 4-reviewer sign-off before merge
9. **Rule 9** — AppShell used; Cobrowse not bypassed or removed
10. **Patterns** — vendor wrappers used, no dead code, no backwards-compat shims

## Handoff
PASS → agent-04 / execute
FAIL → agent-02 / triage (re-triage with policy flag)
next_server: [per verdict]
next_role: [per verdict]

## Handoff Template
---
generated_at_commit: {SESSION_COMMIT}
generated_at_timestamp: {SESSION_TIMESTAMP}
generated_by_role: policy-reviewer
generated_by_server: agent-03
ticket_id: {ticketId}

## Staleness Declaration
# Receiving agent MUST compare generated_at_commit to SESSION_COMMIT.
# If they differ: prepend '⚠️ STALE HANDOFF' and re-read MODULE.md + ROLE.md.

## Task Context
module: review
task_type: policy-review
ticket_description: {description}

## Outputs
verdict: PASS | FAIL
rules_violated: {list or NONE}
patterns_violated: {list or NONE}

## Next Role
next_role: execute | triage
next_server: agent-04 | agent-02
priority: normal | urgent
