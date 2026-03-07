# agents/roles/execution/MODULE.md
# Execution module — Layer 2 domain context.
# Covers: implementing approved plans — writing code, running migrations, deploying.

## Module Scope
The execution module is where approved plans become real code. It activates
only after a plan has been approved by Agent-03 / planner. It has one role:
Execute.

Nothing is built without a plan. Nothing is deployed without passing the
4-reviewer pipeline first.

## Execution Sequence (always in this order)
1. Read the approved plan from the task handoff
2. Implement code changes (files to create/modify per plan)
3. Run DB migrations via Neon MCP (never ask user to run SQL)
4. Verify build compiles and lints clean
5. Submit branch to 4-reviewer pipeline
6. Deploy only after all 4 reviewers PASS

## New App Execution Checklist
When a task creates a new app, ALL of these must be done or it won't appear:
1. Pages in `frontend/src/pages/`
2. Routes in `frontend/src/App.tsx` — `<PrivateRoute><><TopNav />...</>`
3. Tile in MODULES array in `AppLibraryPage.tsx`
4. Category in CATEGORIES array if new category
5. DB row in `apps` table — Neon MCP (`green-rice-76766370`)
6. Tenant subscription in `tenant_app_subscriptions` — Neon MCP
7. DB migration on tenant DB — Neon MCP (`proud-union-74070434`)
8. Vercel deploy — manual (NOT auto from git push)

## Deployment Commands
```bash
# Frontend (Vercel)
VTOKEN=$(doppler secrets get VERCEL_TOKEN --project grotap --config dev --plain)
cd platform/frontend && npx vercel --token "$VTOKEN" --prod --yes

# Backend (Railway)
cd platform/backend && doppler run --project grotap --config dev -- railway up --detach --service grotap-backend
```

## Key References
- App template: `docs/12-app-platform/app-template-guide.md`
- Neon MCP: run SQL via `mcp__Neon__run_sql` / `mcp__Neon__run_sql_transaction`
