# agents/roles/intake/intake/ROLE.md
# Role: Intake | Server: Agent-02 | Module: intake
# Trigger: task.stage == 'new'

## Role Purpose
First handler for any new task. Validate structure, check completeness,
reject malformed tasks, and hand off to triage.

## Inputs
- Task file: `agents/tasks/{ticket_id}-{slug}.md`
- Session commit hash from BOOTSTRAP.md step 1

## Checklist — Run in Order
1. Confirm task file exists and is readable
2. Verify all required fields present: `ticket_id`, `stage`, `type`, `module`
3. Verify `stage == 'new'` — reject if already triaged or beyond
4. Check for duplicate: search `agents/tasks/` for same ticket_id
5. Flag any `security` or `rule-violation` in `flags` field
6. Set `stage = 'triaged'` in the task record upon successful intake

## Outputs
- Validated task summary (ticket_id, type, module, flags)
- Pass to: triage role (same server, Agent-02)
- Reject path: return error to dispatcher with reason

## Hard Stops (do not proceed if any are true)
- `ticket_id` missing or non-numeric
- `stage` is not `new`
- Task file is empty or malformed JSON/MD

## Handoff → Triage
next_role: triage
next_server: agent-02
priority: normal (urgent if flags contain `security`)

## Handoff Template
---
generated_at_commit: {SESSION_COMMIT}
generated_at_timestamp: {SESSION_TIMESTAMP}
generated_by_role: intake
generated_by_server: agent-02
ticket_id: {ticketId}

## Staleness Declaration
# Receiving agent MUST compare generated_at_commit to SESSION_COMMIT.
# If they differ: prepend '⚠️ STALE HANDOFF' and re-read MODULE.md + ROLE.md.

## Task Context
module: intake
task_type: intake-validation
ticket_description: {description}

## Outputs
stage_set_to: triaged
flags_detected: {list or NONE}
validation_result: PASS | REJECT
rejection_reason: {reason or NONE}

## Next Role
next_role: triage
next_server: agent-02
priority: normal | urgent
