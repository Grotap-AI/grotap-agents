You are working on the grotap platform codebase at /home/agent/grotap-platform.

## Task #942 — Wire auto-dispatch + Cobrowse test → beta status

Two gaps to close in the app build pipeline.

### Part 1 — Auto-dispatch in build-app-from-suggestion.ts

Read platform/ingestion-worker/src/functions/build-app-from-suggestion.ts

There is a TODO comment where agent farm dispatch should happen (around "When agent farm auto-dispatch is ready").

Replace the TODO with actual dispatch logic:

1. After creating the GitHub branch, send an Inngest event to trigger agent dispatch:
```typescript
await inngest.send({
  name: 'agent/task.dispatch',
  data: {
    task_type: 'build_app',
    suggestion_id: event.data.suggestion_id,
    app_slug: slug,
    branch: branchName,
    manifest: manifest,
    priority: 'normal',
  }
});
```

2. Also update the suggestion status to 'queued' (not just 'building') at the point of dispatch:
```typescript
// Update status: accepted → queued (dispatched to agent, awaiting pickup)
await db.query(
  "UPDATE app_suggestions SET status = 'queued' WHERE suggestion_id = $1",
  [event.data.suggestion_id]
);
```

3. Add 'queued' to the status CHECK constraint in the app_suggestions table. Run this on the control plane DB (green-rice-76766370) using the Neon HTTP API:
```sql
ALTER TABLE app_suggestions DROP CONSTRAINT IF EXISTS app_suggestions_status_check;
ALTER TABLE app_suggestions ADD CONSTRAINT app_suggestions_status_check
  CHECK (status IN ('submitted','voting','accepted','queued','building','launched','rejected'));
```
Use NEON_API_KEY from process.env to call: POST https://console.neon.tech/api/v2/projects/green-rice-76766370/query

### Part 2 — Cobrowse snapshot test → promote app to beta

Read platform/ingestion-worker/src/functions/cobrowse-snapshot-test.ts

After the test completes (all scenarios run), add logic to auto-promote the app to beta if no CRITICAL or HIGH severity bugs were found:

```typescript
const criticalOrHigh = bugReports.filter(b =>
  b.severity === 'CRITICAL' || b.severity === 'HIGH'
);

if (criticalOrHigh.length === 0) {
  // All clear — promote to beta
  await fetch(`${process.env.API_URL || 'https://api.grotap.com'}/app-registry/apps/${appId}/status`, {
    method: 'PATCH',
    headers: {
      'Authorization': `Bearer ${process.env.AGENT_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ status: 'beta' }),
  });
  // Also update suggestion to 'launched'
  if (suggestionId) {
    await db.query(
      "UPDATE app_suggestions SET status = 'launched' WHERE suggestion_id = $1",
      [suggestionId]
    );
  }
}
```

Check platform/backend/app/routers/app_registry.py for the PATCH status endpoint — add it if missing:
```python
@router.patch("/apps/{app_id}/status")
async def update_app_status(app_id: str, payload: dict, request: Request, db=Depends(get_control_plane_db)):
    await db.execute("UPDATE apps SET status=$1 WHERE app_id=$2", payload['status'], app_id)
    return {"status": payload['status']}
```

### Deploy

```bash
cd platform/ingestion-worker
npm install
railway up --service 179c40ce-cd06-4c66-a10b-35b347f1ac67
```

Check: railway deployment list --service 179c40ce-cd06-4c66-a10b-35b347f1ac67
If FAILED: railway logs <deployment_id>

Also deploy backend if app_registry.py was changed:
```bash
cd platform/backend
railway up --service 6cad7f74-9329-406e-b733-719a33c53ac3
```

### Commit

```
git add -A
git commit -m "feat: auto-dispatch on suggestion accept + Cobrowse test auto-promote to beta (#942)"
git push origin master
```
