# agents/roles/intake/triage/ROLE.md
# Role: Triage | Server: agent-02-claude | Module: intake
# Trigger: task.stage == 'triaged' OR task.type == 'triage'

## Role Purpose
Assess a validated task, determine its correct pipeline path, assign priority,
and route it to the right server and role.

## Routing Decision Table
| Condition | Route to |
|---|---|
| `flags` contains `security` | agent-02-claude / security-reviewer |
| `type == 'audit'` or `type == 'filter-review'` | agent-05-claude / audit-filters |
| `type == 'policy-review'` | agent-03-claude / policy-reviewer |
| `type == 'build'` | agent-04-claude / build-validator |
| Default (feature/fix, no flags) | agent-03-claude / planner |

## Triage Checklist
1. Read full task description — confirm scope is understood
2. Identify which ERP module owns this task (pipeline, enforcement, etc.)
3. Apply routing table above — pick exactly one next route
4. Assign priority: `urgent` if security/rule-violation flag, else `normal`
5. Write triage decision to handoff

## Outputs
- Triage decision: next_server, next_role, priority
- Module assignment recorded

## Handoff
Routes: next_role/next_server per routing table above; priority urgent if security/rule-violation flag
Output fields: see `agents/roles/shared/handoff-schema.md` → triage
