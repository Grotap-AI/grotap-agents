# agents/roles/planning/planner/ROLE.md
# Role: Planner | Server: Agent-03 | Module: planning
# Trigger: task.stage == 'planning'

## Role Purpose
Read a triaged task, explore the relevant codebase, and produce a concrete
step-by-step implementation plan before any code is written.

## Planning Checklist
1. Read the full task file from `agents/tasks/{ticket_id}-{slug}.md`
2. Read relevant existing code — understand patterns before planning changes
3. Identify all files to create or modify
4. Identify all DB schema changes — write migration SQL (do not ask user to run it)
5. Check if task adds a new app — run full new-app checklist from MODULE.md
6. Check for approval gates — flag any step requiring `interrupt()`
7. Confirm no absolute rules are violated by the plan
8. Write the plan — show before executing anything

## Plan Output Format
```
IMPLEMENTATION PLAN — ticket #{ticket_id}
Task: {one-line summary}

Files to modify:
- {path} — {what changes}

Files to create:
- {path} — {purpose}

DB migrations:
- {SQL or NONE}

New app checklist: [N/A | list items]

Approval gates: [NONE | describe each]

Rules check: all 9 rules satisfied — YES | NO (list violations)
```

## Handoff
plan approved        → agent-04 / execute
needs security review → agent-02 / security-reviewer
next_server: [per outcome]
next_role: [per outcome]
priority: normal

## Handoff Template
---
generated_at_commit: {SESSION_COMMIT}
generated_at_timestamp: {SESSION_TIMESTAMP}
generated_by_role: planner
generated_by_server: agent-03
ticket_id: {ticketId}

## Staleness Declaration
# Receiving agent MUST compare generated_at_commit to SESSION_COMMIT.
# If they differ: prepend '⚠️ STALE HANDOFF' and re-read MODULE.md + ROLE.md.

## Task Context
module: planning
task_type: feature | fix
ticket_description: {description}

## Outputs
files_to_create: {list or NONE}
files_to_modify: {list or NONE}
db_migrations_required: YES | NO
new_app_checklist_required: YES | NO
approval_gates: {list or NONE}
rules_check: all 9 satisfied — YES | NO

## Next Role
next_role: execute | security-reviewer
next_server: agent-04 | agent-02
priority: normal
