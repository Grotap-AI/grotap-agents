# agents/servers/agent-03.md
# Server: Agent-03 | IP: 5.161.81.193
# Roles: Planner | Fix Reviewer | Policy Reviewer | Logic Reviewer | Perf Reviewer | Execute (overflow)

## Role Assignments

### Planner
trigger:    task.stage == 'planning'
priority:   primary
load_order: GLOBAL.md → roles/planning/MODULE.md → roles/planning/planner/ROLE.md → handoff (if exists)

### Fix Reviewer
trigger:    task.type == 'fix-review'
priority:   primary
load_order: GLOBAL.md → roles/review/MODULE.md → roles/review/fix-reviewer/ROLE.md → handoff (if exists)

### Policy Reviewer
trigger:    task.type == 'policy-review' OR task.flags contains 'policy'
priority:   primary
load_order: GLOBAL.md → roles/review/MODULE.md → roles/review/policy-reviewer/ROLE.md → handoff (if exists)

### Logic Reviewer
trigger:    task.type == 'logic-review'
priority:   primary
load_order: GLOBAL.md → roles/review/MODULE.md → roles/review/logic-reviewer/ROLE.md → handoff (if exists)

### Perf Reviewer
trigger:    task.type == 'perf-review' OR task.flags contains 'performance'
priority:   primary
load_order: GLOBAL.md → roles/review/MODULE.md → roles/review/perf-reviewer/ROLE.md → handoff (if exists)

### Execute (overflow)
trigger:    task.stage == 'execution' AND server.idle == true
priority:   overflow — yields immediately when any primary role is requested
load_order: GLOBAL.md → roles/execution/MODULE.md → roles/execution/execute/ROLE.md → handoff (if exists)

## Overflow Rules
- Execute tasks are only dispatched here when primary executors (Agent-01, Agent-04) are busy
- If a primary-role task arrives (planning, review), it takes priority
- Overflow execution does NOT change this server's identity — primary roles always win
- dispatch-execute.sh handles routing; never manually dispatch execution here

## Dispatch
bash agents/dispatch.sh agents/tasks/{ticket}.md 5.161.81.193 {session-name}

## Inbound Routes (this server receives from)
- agent-02 / triage           — normal post-triage flow
- agent-05 / pipeline-detail  — pipeline issues found
- agent-04 / execute          — perf review after build
- dispatch-execute.sh         — overflow execution tasks (when idle)

## Outbound Routes (this server sends to)
- agent-04 / execute          — after plan approved
- agent-04 / build-validator  — after fix reviewed, ready to build
- agent-02 / triage           — re-triage required
- agent-03 / perf-reviewer    — after overflow execution build (self-review route)
