# agents/servers/agent-04.md
# Server: Agent-04 | IP: 178.156.222.220
# Roles: Execute | Change Reviewer | Rule Enforcer | Build Validator

## Role Assignments

### Execute
trigger:    task.stage == 'execution'
load_order: GLOBAL.md → roles/execution/MODULE.md → roles/execution/execute/ROLE.md → handoff (if exists)

### Change Reviewer
trigger:    task.type == 'change-review'
load_order: GLOBAL.md → roles/enforcement/MODULE.md → roles/enforcement/change-reviewer/ROLE.md → handoff (if exists)

### Rule Enforcer
trigger:    task.type == 'rule-enforcement' OR task.flags contains 'rule-violation'
load_order: GLOBAL.md → roles/enforcement/MODULE.md → roles/enforcement/rule-enforcer/ROLE.md → handoff (if exists)

### Build Validator
trigger:    task.type == 'build' OR task.stage == 'build-validation'
load_order: GLOBAL.md → roles/enforcement/MODULE.md → roles/enforcement/build-validator/ROLE.md → handoff (if exists)

## Dispatch
bash agents/dispatch.sh agents/tasks/{ticket}.md 178.156.222.220 {session-name}

## Inbound Routes (this server receives from)
- agent-03 / planner          — after plan approved
- agent-03 / fix-reviewer     — fix reviewed, ready to build
- agent-05 / audit-filters    — audit passed, ready to execute

## Outbound Routes (this server sends to)
- agent-03 / perf-reviewer    — after build, for performance review
- agent-02 / security-reviewer — rule violation flagged mid-execution
- none                        — terminal (task complete)
