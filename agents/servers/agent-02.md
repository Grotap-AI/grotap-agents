# agents/servers/agent-02.md
# Server: Agent-02 | IP: 5.161.74.39
# Roles: Intake | Triage | Security Reviewer | Execute (overflow)

## Role Assignments

### Intake
trigger:    task.stage == 'new'
priority:   primary
load_order: GLOBAL.md → roles/intake/MODULE.md → roles/intake/intake/ROLE.md → handoff (if exists)

### Triage
trigger:    task.stage == 'triaged' OR task.type == 'triage'
priority:   primary
load_order: GLOBAL.md → roles/intake/MODULE.md → roles/intake/triage/ROLE.md → handoff (if exists)

### Security Reviewer
trigger:    task.type == 'security-review' OR task.flags contains 'security'
priority:   primary
load_order: GLOBAL.md → roles/security/MODULE.md → roles/security/security-reviewer/ROLE.md → handoff (if exists)

### Execute (overflow)
trigger:    task.stage == 'execution' AND server.idle == true
priority:   overflow — yields immediately when any primary role is requested
load_order: GLOBAL.md → roles/execution/MODULE.md → roles/execution/execute/ROLE.md → handoff (if exists)

## Overflow Rules
- Execute tasks are only dispatched here when primary executors (Agent-01, Agent-04) are busy
- If a primary-role task arrives (intake, triage, security review), it takes priority
- Overflow execution does NOT change this server's identity — primary roles always win
- dispatch-execute.sh handles routing; never manually dispatch execution here

## Dispatch
bash agents/dispatch.sh agents/tasks/{ticket}.md 5.161.74.39 {session-name}

## Inbound Routes (this server receives from)
- Any new task (stage == 'new') from dispatcher
- agent-03 / triage re-routes (stage == 'triaged')
- agent-04 / rule-enforcer escalations (flags contain 'security')
- dispatch-execute.sh — overflow execution tasks (when idle)

## Outbound Routes (this server sends to)
- agent-03 / planner          — normal flow after triage
- agent-03 / policy-reviewer  — security flag raised
- agent-05 / audit-filters    — audit required
- agent-03 / perf-reviewer    — after overflow execution build
