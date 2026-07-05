# agents/roles/execution/MODULE.md
# Execution module — Layer 2 domain context.
# Covers: implementing approved plans — writing code, running migrations, deploying.

## Module Scope
The execution module is where approved plans become real code. It activates
only after a plan has been approved by Agent-03 / planner. It has one role:
Execute.

Nothing is built without a plan. Nothing is deployed without passing the
4-reviewer pipeline first.

## Executor Pool
Executor pool: agent-04 primary (3 slots); overflow agent-02/03/05 (3 each);
agent-06 (2 slots, 1 reserved for dispatch). Roster: `agents/SERVERS.md`.

Concurrency is per-slot via git worktrees — each task gets an isolated working
directory at `/home/agent/worktrees/<session>/` with its own branch; no conflicts
between concurrent tasks on the same server.

Execute (overflow) yields to primary roles. Overflow executors follow the exact
same checklist, hard stops, and review requirements as primary executors. Use
`dispatch-execute.sh` to auto-route to the server with the most free slots —
primary first, then overflow.

## Execution Sequence (always in this order)
1. Read the approved plan from the task handoff
2. Implement code changes (files to create/modify per plan)
3. Run DB migrations via `doppler run -- psql` (never ask user to run SQL — conventions.md DB access)
4. Verify build compiles and lints clean
5. Submit branch to 4-reviewer pipeline
6. Deploy only after all 4 reviewers PASS

## New App Execution Checklist
When a task creates a new app, ALL of these must be done or it won't appear:
1. Pages in `frontend/src/pages/`
2. Routes in `frontend/src/App.tsx` — `<PrivateRoute><><TopNav />...</>`
3. Tile in MODULES array in `AppLibraryPage.tsx`
4. Category in CATEGORIES array if new category
5. DB row in `apps` table — `doppler run -- psql "$DATABASE_URL"` (control plane, Neon project `green-rice-76766370`)
6. Tenant subscription in `tenant_app_subscriptions` — same psql path
7. DB migration on tenant DB — `doppler run -- psql "$TENANT_DATABASE_URL"` (Neon project `proud-union-74070434`)
8. Deploy per GLOBAL "Deployment" — confirm the frontend actually shipped (CI runs only on `frontend/**` paths)

## Deployment
See `agents/GLOBAL.md` "Deployment" (push to master → Railway auto-deploy + Vercel CI;
agents on Hetzner push their branch and request merge+deploy from the coordinator).
Manual redeploy commands live in `agents/roles/deployment-ops/deploy-executor/ROLE.md`.

## Key References
- App template: `docs/12-app-platform/app-template-guide.md`
- DB access: direct SQL only — see "Database Access Convention" in `agents/roles/shared/conventions.md`
