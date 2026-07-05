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
Routes: approved → agent-04 / execute (resume from interrupt) | rejected → agent-03 / planner (re-plan)
expired → none (escalate to support portal) — priority: urgent (approvals block the pipeline)
Output fields: see `agents/roles/shared/handoff-schema.md` → mobile-approvals
