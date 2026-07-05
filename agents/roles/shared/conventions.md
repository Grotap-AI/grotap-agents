# agents/roles/shared/conventions.md
# Shared conventions — promoted patterns used across multiple modules.
# Load this when a role needs cross-cutting conventions not in GLOBAL.md.

## Handoff Format Convention
Common fields, staleness rule, and per-role output fields: `agents/roles/shared/handoff-schema.md`.

## Verdict Format Convention
All reviewer roles must use exactly:
```
Verdict: PASS | FAIL | WARN
Findings:
- [FAIL] {file}:{line} — {description}
- [WARN] {file}:{line} — {description}
```
Never return a free-form verdict. Structured output only.

## Database Access Convention (NO MCP — direct SQL only)
Neon MCP is retired fleet-wide (token bloat; the tools were never provisioned on agent servers).
Secrets come from Doppler — never inline connection strings.
- Single query: `doppler run -- psql "$DATABASE_URL" -Atc "<sql>"` (control plane)
- Tenant DB: same with `$TENANT_DATABASE_URL`
- Migrations / multiple statements: write a `.sql` file, run `doppler run -- psql "$DATABASE_URL" -1 -f <file>` (`-1` = single transaction), then verify with a SELECT
- Neon project/branch management (rare): Neon API via `$NEON_API_KEY` with curl — never MCP
- Never tell the user to run SQL. Always run it yourself.

## File Path Conventions
- Frontend pages: `platform/frontend/src/pages/{AppName}Page.tsx`
- Frontend routes: `platform/frontend/src/App.tsx`
- Backend routers: `platform/backend/app/routers/{domain}.py`
- Agent tasks: `agents/tasks/{ticket_id}-{slug}.md`
- Handoff files: `state/handoffs/handoff-{ticketId}-{timestamp}.md`

## Branch Naming Convention
`feature/{ticket_id}-{short-slug}` — e.g., `feature/940-inngest-subscribe-worker`
