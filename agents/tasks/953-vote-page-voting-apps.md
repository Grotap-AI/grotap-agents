# Task 953 — Vote page: show apps in `voting` status as app cards (+ audit app status changes)

## Context (bug report from owner, 2026-07-02)

Apps whose `apps.status` is set to `'voting'` (via App Manager's status dropdown →
`PATCH /app-registry/apps/{app_id}/status`) currently vanish from the ENTIRE product:

- `BetaAppsPage.tsx` filters `status === 'beta' || status === 'building'` → hidden from Beta Apps.
- My Beta calls `/apps/my?status=beta` → hidden from My Beta even with an active subscription.
- `VoteIdeasPage.tsx` renders ONLY `app_suggestions` (ideas) on its vote tabs; apps with
  `status='voting'` are never rendered anywhere on the page ("Being Built" = beta|building,
  "Apps Live" = active).

So demoting an app from Beta back to Voting makes it invisible everywhere — this hid ScanTap
from a live customer (Manorview Farms) today. ScanTap has been manually restored to `beta`;
this task fixes the black hole and the missing audit trail.

There are currently ~20 apps in `voting` status (e.g. welcome, ranch-plan, forecast-tool,
farm-dashboard, cobrowse-console, agent-manager, agent-teams, knowledge-manager + internal ones).
Use these as live test data.

## Changes required

### 1. Frontend — `frontend/src/pages/VoteIdeasPage.tsx`

Show ALL apps with `status === 'voting'` on the Vote to Innovate page, rendered with the SAME
`AppCard` component and grid format used by `BetaAppsPage.tsx` (owner requirement: "show all
apps in Vote status in same format they show on Beta Apps").

- Data is already available: the page already fetches `GET /app-registry/apps`, which returns
  all apps regardless of status. No backend change needed for the listing.
- Render the voting-status apps under the **Apps** toggle on BOTH the **New Apps** and
  **Vote Ranking** tabs, in the same grid as the idea cards (apps first, then ideas is fine).
- Use `<AppCard app={a} ... />` exactly like BetaAppsPage does. Pass
  `showSubscribeButton={false}` — an app in voting is not subscribable; promotion back to
  beta happens in App Manager.
- Do NOT filter `is_internal` (Beta Apps doesn't either).
- Update the local `AppItem` interface: its `status` union is missing `'voting'` and `'live'`
  — widen it (or use `string`) so the filter compiles.
- Do not change idea-card behavior, brand toggle, Being Built, or Apps Live tabs.

### 2. Backend — `backend/app/routers/app_registry.py`

The status-change endpoint leaves no trace, which made today's incident unattributable.
In `update_app_status` (PATCH `/apps/{app_id}/status`), after a successful update:

- Insert a row into `audit_log`: `action='app.status_change'`, `resource_id=<app_id>`,
  `user_id=<request.state.user_id or 'node-secret'>`, `metadata` JSONB with
  `{"slug": ..., "old_status": ..., "new_status": ...}` (fetch old status before updating).
- REMEMBER: asyncpg JSONB params must be passed through `json.dumps()` (no codec registered).
- Also set `updated_at=NOW()` in both UPDATE statements in that endpoint so status flips are
  datable.
- Best-effort: wrap the audit insert in try/except with a logger.warning — never fail the
  status change because auditing failed.

## Acceptance criteria

1. `npx tsc --noEmit` passes in `frontend/`; `python -m py_compile` passes on changed backend files.
2. Vote to Innovate → Apps toggle → "New Apps" and "Vote Ranking" tabs show app cards for every
   app with status `voting` (e.g. "Welcome", "Ranch Plan"), styled identically to Beta Apps cards.
3. Idea cards still render and vote/fund/design/test actions still work.
4. Changing an app's status via App Manager writes an `audit_log` row with old/new status.
5. Playwright: extend or add an e2e spec asserting a known voting app's card is visible on the
   Vote page (JWT self-test pattern per existing specs — org_id org_01KJVXNF61J06X5YD1XKHRZENE).

## Guardrails

- Frontend-only rendering change + one backend endpoint touch. Do NOT change `/apps/my`,
  Beta Apps filtering, or subscription logic.
- No new dependencies. Follow existing inline-style idiom of VoteIdeasPage.
- Commit style: `fix(vote): show voting-status apps as app cards + audit app status changes`
