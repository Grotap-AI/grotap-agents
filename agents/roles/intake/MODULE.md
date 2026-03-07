# agents/roles/intake/MODULE.md
# Intake module — Layer 2 domain context.
# Covers: new task reception, validation, and routing to the correct pipeline stage.

## Module Scope
The intake module is the entry point for all new tasks entering the agent pipeline.
It covers two roles: Intake (first reception) and Triage (routing decision).

No task enters the review or execution pipeline without passing through intake first.

## Task Structure
Every task dispatched to an agent must include:
- `ticket_id` — unique identifier (e.g., `938`, `939`)
- `stage` — lifecycle stage: `new` | `triaged` | `planning` | `execution` | `review` | `done`
- `type` — task type: `feature` | `fix` | `security-review` | `build` | `audit` | `policy-review`
- `module` — ERP domain (e.g., `pipeline`, `approvals`, `enforcement`)
- `flags` — optional array: `security` | `performance` | `policy` | `rule-violation`
- `channel` — `web` | `mobile` | `api`

Task files live in: `agents/tasks/{ticket_id}-{slug}.md`

## Key Constraints
- Never accept a task with missing `ticket_id` or `stage`
- Never route a task to execution without triage sign-off
- All tasks with `flags` containing `security` must route through security-reviewer on Agent-02

## Outbound Routes from This Module
| Destination | Condition |
|---|---|
| agent-03 / planner | Normal flow after triage |
| agent-03 / policy-reviewer | Task flags contain `security` |
| agent-05 / audit-filters | Task requires audit |
