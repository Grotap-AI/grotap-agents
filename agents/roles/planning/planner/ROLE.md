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

Rules check: all 8 rules satisfied — YES | NO (list violations)
```

## Handoff
Routes: plan approved → execute | needs security review → security-reviewer
Output fields: see `agents/roles/shared/handoff-schema.md` → planner
