# agents/roles/planning/MODULE.md
# Planning module — Layer 2 domain context.
# Covers: task planning, implementation strategy, and handoff to execution.

## Module Scope
The planning module translates a triaged task into a concrete implementation
plan that the execution module can act on. It has one role: Planner.

No task proceeds to execution without a written plan approved by the planner.

## What a Plan Must Include
- List of files to create or modify (with paths)
- Database migrations required (Neon MCP — never tell user to run SQL)
- API endpoints to add or change
- Frontend routes and components affected
- New app checklist items (if task adds a new app):
  1. Pages in `frontend/src/pages/`
  2. Routes in `frontend/src/App.tsx`
  3. Tile in MODULES array in `AppLibraryPage.tsx`
  4. DB row in `apps` table (control plane)
  5. Tenant subscription in `tenant_app_subscriptions`
  6. DB migration on tenant DB
  7. Vercel deploy (manual — not auto from git push)
- Estimated line count per file (flag if any file > 300 lines)

## Planning Constraints
- Never plan a Python agent — TypeScript only (Rule 2)
- Never plan direct 3rd-party SDK calls — vendor wrappers only (Rule 3)
- Always scope DB queries to `tenant_id` or `organization_id` in the plan
- Flag any plan item that requires human approval before execution

## Key References
- New app checklist: `docs/12-app-platform/app-template-guide.md`
- DB strategy: `docs/03-database/neon-app-schema-architecture.md`
