# agents/servers/agent-05.md
# Server: Agent-05 | IP: 5.161.73.195
# Roles: Pipeline Detail | Audit Filters | Mobile Approvals | Execute (overflow)

## Role Assignments

### Pipeline Detail
trigger:    task.type == 'pipeline' AND task.detail == true
priority:   primary
load_order: GLOBAL.md → roles/pipeline/MODULE.md → roles/pipeline/pipeline-detail/ROLE.md → handoff (if exists)

### Audit Filters
trigger:    task.type == 'audit' OR task.type == 'filter-review'
priority:   primary
load_order: GLOBAL.md → roles/pipeline/MODULE.md → roles/pipeline/audit-filters/ROLE.md → handoff (if exists)

### Mobile Approvals
trigger:    task.channel == 'mobile' AND task.type == 'approval'
priority:   primary
load_order: GLOBAL.md → roles/approvals/MODULE.md → roles/approvals/mobile-approvals/ROLE.md → handoff (if exists)

### Execute (overflow)
trigger:    task.stage == 'execution' AND server.idle == true
priority:   overflow — yields immediately when any primary role is requested
load_order: GLOBAL.md → roles/execution/MODULE.md → roles/execution/execute/ROLE.md → handoff (if exists)

## Overflow Rules
- Execute tasks are only dispatched here when primary executors (Agent-01, Agent-04) are busy
- If a primary-role task arrives (pipeline, audit, approval), it takes priority
- Overflow execution does NOT change this server's identity — primary roles always win
- dispatch-execute.sh handles routing; never manually dispatch execution here

## Dispatch
bash agents/dispatch.sh agents/tasks/{ticket}.md 5.161.73.195 {session-name}

## Inbound Routes (this server receives from)
- agent-02 / triage       — audit required
- Any approval interrupt from LangGraph pipeline
- dispatch-execute.sh     — overflow execution tasks (when idle)

## Outbound Routes (this server sends to)
- agent-03 / fix-reviewer  — pipeline issues found
- agent-04 / execute       — approved and ready to execute
- agent-03 / perf-reviewer — after overflow execution build
