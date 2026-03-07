# agents/servers/agent-05.md
# Server: Agent-05 | IP: 5.161.73.195
# Roles: Pipeline Detail | Audit Filters | Mobile Approvals

## Role Assignments

### Pipeline Detail
trigger:    task.type == 'pipeline' AND task.detail == true
load_order: GLOBAL.md → roles/pipeline/MODULE.md → roles/pipeline/pipeline-detail/ROLE.md → handoff (if exists)

### Audit Filters
trigger:    task.type == 'audit' OR task.type == 'filter-review'
load_order: GLOBAL.md → roles/pipeline/MODULE.md → roles/pipeline/audit-filters/ROLE.md → handoff (if exists)

### Mobile Approvals
trigger:    task.channel == 'mobile' AND task.type == 'approval'
load_order: GLOBAL.md → roles/approvals/MODULE.md → roles/approvals/mobile-approvals/ROLE.md → handoff (if exists)

## Dispatch
bash agents/dispatch.sh agents/tasks/{ticket}.md 5.161.73.195 {session-name}

## Inbound Routes (this server receives from)
- agent-02 / triage       — audit required
- Any approval interrupt from LangGraph pipeline

## Outbound Routes (this server sends to)
- agent-03 / fix-reviewer  — pipeline issues found
- agent-04 / execute       — approved and ready to execute
