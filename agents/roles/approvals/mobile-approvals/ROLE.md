# agents/roles/approvals/mobile-approvals/ROLE.md
# Role: Mobile Approvals | Server: Agent-05 | Module: approvals
# Trigger: task.channel == 'mobile' AND task.type == 'approval'

## Role Purpose
Surface pending approval requests to the mobile Expo app, track approval
state, and resume or cancel the blocked agent pipeline based on the
human's decision.

## Checklist
1. Identify the blocked task from `interrupt()` checkpoint context
2. Prepare a concise approval summary for mobile display (max 5 lines):
   - What action is being requested
   - What will happen if approved
   - What will happen if rejected
3. Push approval request to Expo notification system
4. Poll for human decision (timeout: 24 hours)
5. On approval: resume LangGraph graph from interrupt point
6. On rejection: route task back to agent-03 / planner for re-planning
7. On expiry: escalate to human via support portal

## Output Format
```
MOBILE APPROVAL REQUEST — ticket #{ticket_id}
Action: {one-line description}
Impact if approved: {one line}
Impact if rejected: {one line}
Status: pending | approved | rejected | expired
Decision by: {timestamp or 'awaiting'}
```

## Handoff
approved  → agent-04 / execute (resume from interrupt)
rejected  → agent-03 / planner (re-plan)
expired   → none (escalate to support portal)
next_server: [per decision]
next_role: [per decision]
priority: urgent (approvals block the pipeline)

## Handoff Template
---
generated_at_commit: {SESSION_COMMIT}
generated_at_timestamp: {SESSION_TIMESTAMP}
generated_by_role: mobile-approvals
generated_by_server: agent-05
ticket_id: {ticketId}

## Staleness Declaration
# Receiving agent MUST compare generated_at_commit to SESSION_COMMIT.
# If they differ: prepend '⚠️ STALE HANDOFF' and re-read MODULE.md + ROLE.md.

## Task Context
module: approvals
task_type: approval
ticket_description: {description}

## Outputs
decision: approved | rejected | expired
decided_at: {timestamp or NONE}
action_requested: {one-line summary}

## Next Role
next_role: execute | planner | none
next_server: agent-04 | agent-03 | none
priority: urgent
