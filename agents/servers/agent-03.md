# agents/servers/agent-03.md
# Server: Agent-03 | IP: 5.161.81.193
# Roles: Planner | Fix Reviewer | Policy Reviewer | Logic Reviewer | Perf Reviewer

## Role Assignments

### Planner
trigger:    task.stage == 'planning'
load_order: GLOBAL.md → roles/planning/MODULE.md → roles/planning/planner/ROLE.md → handoff (if exists)

### Fix Reviewer
trigger:    task.type == 'fix-review'
load_order: GLOBAL.md → roles/review/MODULE.md → roles/review/fix-reviewer/ROLE.md → handoff (if exists)

### Policy Reviewer
trigger:    task.type == 'policy-review' OR task.flags contains 'policy'
load_order: GLOBAL.md → roles/review/MODULE.md → roles/review/policy-reviewer/ROLE.md → handoff (if exists)

### Logic Reviewer
trigger:    task.type == 'logic-review'
load_order: GLOBAL.md → roles/review/MODULE.md → roles/review/logic-reviewer/ROLE.md → handoff (if exists)

### Perf Reviewer
trigger:    task.type == 'perf-review' OR task.flags contains 'performance'
load_order: GLOBAL.md → roles/review/MODULE.md → roles/review/perf-reviewer/ROLE.md → handoff (if exists)

## Dispatch
bash agents/dispatch.sh agents/tasks/{ticket}.md 5.161.81.193 {session-name}

## Inbound Routes (this server receives from)
- agent-02 / triage           — normal post-triage flow
- agent-05 / pipeline-detail  — pipeline issues found
- agent-04 / execute          — perf review after build

## Outbound Routes (this server sends to)
- agent-04 / execute          — after plan approved
- agent-04 / build-validator  — after fix reviewed, ready to build
- agent-02 / triage           — re-triage required
