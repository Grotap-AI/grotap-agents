# agents/roles/shared/conventions.md
# Shared conventions — promoted patterns used across multiple modules.
# Load this when a role needs cross-cutting conventions not in GLOBAL.md.

## Handoff Format Convention
All handoff files must use this structure (see plan Section 3.1):
```
generated_at_commit: {40-char Git SHA}
generated_at_timestamp: {UTC ISO 8601}
generated_by_role: {role-name}
generated_by_server: {agent-XX}
ticket_id: {id}
next_role: {role or 'none'}
next_server: {agent-XX or 'none'}
priority: normal | urgent | blocked
```

## Verdict Format Convention
All reviewer roles must use exactly:
```
Verdict: PASS | FAIL | WARN
Findings:
- [FAIL] {file}:{line} — {description}
- [WARN] {file}:{line} — {description}
```
Never return a free-form verdict. Structured output only.

## Neon MCP Convention
- Single query: `mcp__Neon__run_sql`
- Multiple statements: `mcp__Neon__run_sql_transaction`
- Migrations: `mcp__Neon__prepare_database_migration` → verify → `mcp__Neon__complete_database_migration`
- Never tell the user to run SQL. Always run it yourself.

## File Path Conventions
- Frontend pages: `platform/frontend/src/pages/{AppName}Page.tsx`
- Frontend routes: `platform/frontend/src/App.tsx`
- Backend routers: `platform/backend/app/routers/{domain}.py`
- Agent tasks: `agents/tasks/{ticket_id}-{slug}.md`
- Handoff files: `state/handoffs/handoff-{ticketId}-{timestamp}.md`

## Branch Naming Convention
`feature/{ticket_id}-{short-slug}` — e.g., `feature/940-inngest-subscribe-worker`
