# agents/servers/agent-02.md
# Server: Agent-02 | IP: 5.161.74.39
# Roles: Intake | Triage | Security Reviewer

## Role Assignments

### Intake
trigger:    task.stage == 'new'
load_order: GLOBAL.md → roles/intake/MODULE.md → roles/intake/intake/ROLE.md → handoff (if exists)

### Triage
trigger:    task.stage == 'triaged' OR task.type == 'triage'
load_order: GLOBAL.md → roles/intake/MODULE.md → roles/intake/triage/ROLE.md → handoff (if exists)

### Security Reviewer
trigger:    task.type == 'security-review' OR task.flags contains 'security'
load_order: GLOBAL.md → roles/security/MODULE.md → roles/security/security-reviewer/ROLE.md → handoff (if exists)

## Dispatch
bash agents/dispatch.sh agents/tasks/{ticket}.md 5.161.74.39 {session-name}

## Inbound Routes (this server receives from)
- Any new task (stage == 'new') from dispatcher
- agent-03 / triage re-routes (stage == 'triaged')
- agent-04 / rule-enforcer escalations (flags contain 'security')

## Outbound Routes (this server sends to)
- agent-03 / planner          — normal flow after triage
- agent-03 / policy-reviewer  — security flag raised
- agent-05 / audit-filters    — audit required
