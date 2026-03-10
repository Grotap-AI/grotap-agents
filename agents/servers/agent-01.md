# agents/servers/agent-01.md
# Server: Agent-01 | IP: 5.161.189.143
# Type: cpx21 (3 vCPU / 4 GB) | DC: Ashburn, VA (ash-dc1)
# Roles: Execute
# Hetzner Project: Primary (HETZNER_API_TOKEN)

## Role Assignments

### Execute
trigger:    task.stage == 'execution'
priority:   primary
load_order: GLOBAL.md → roles/execution/MODULE.md → roles/execution/execute/ROLE.md → handoff (if exists)

## Dispatch
bash agents/dispatch.sh agents/tasks/{ticket}.md 5.161.189.143 {session-name}

## Inbound Routes (this server receives from)
- agent-03 / planner          — after plan approved
- agent-03 / fix-reviewer     — fix reviewed, ready to build
- agent-05 / audit-filters    — audit passed, ready to execute
- dispatch-execute.sh         — auto-routed execution tasks (primary tier)

## Outbound Routes (this server sends to)
- agent-03 / perf-reviewer    — after build, for performance review
- agent-04 / rule-enforcer    — rule violation flagged mid-execution
- agent-02 / security-reviewer — security flag raised
- none                        — terminal (task complete)
