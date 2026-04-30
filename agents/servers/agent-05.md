# agents/servers/agent-05.md
# Server: Agent-05 | IP: 5.161.73.195
# Roles: Pipeline Detail | Audit Filters | Mobile Approvals | Marketing | Execute (overflow)
# Note: Marketing role consolidated from agent-11 (2026-04-29)

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

### Marketing (consolidated from agent-11, 2026-04-29)
trigger:    task.type == 'marketing'
priority:   primary
capabilities:
  - Squarespace content management (website, blog, pages)
  - Instagram publishing & analytics (Meta Business API)
  - Facebook page management & ads (Meta Business API)
  - YouTube channel management & uploads (YouTube Data API v3)
  - TikTok content publishing & analytics (TikTok API)

### Execute (overflow)
trigger:    task.stage == 'execution' AND server.idle == true
priority:   overflow — yields immediately when any primary role is requested
load_order: GLOBAL.md → roles/execution/MODULE.md → roles/execution/execute/ROLE.md → handoff (if exists)

## Overflow Rules
See `agents/roles/shared/overflow-rules.md` — primary roles (pipeline, audit, approval) always take priority.

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
