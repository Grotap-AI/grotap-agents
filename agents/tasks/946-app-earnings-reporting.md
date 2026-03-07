You are working on the grotap platform codebase at /home/agent/grotap-platform.

## Task #946 — App Earnings Reporting

The `app_earnings` table exists on the control plane DB but there are no reporting endpoints or UI.

### Step 1 — Read existing code

Read these files:
- backend/app/routers/app_registry.py — understand existing app registry patterns
- frontend/src/App.tsx — find where to add route
- frontend/src/components/TopNav.tsx — check if there's a billing/earnings nav entry

Also inspect the app_earnings table schema by reading:
platform/migrations/control_plane_apps.sql (or search for app_earnings in migration files)

### Step 2 — Add backend endpoint

Add to `platform/backend/app/routers/app_registry.py` (or a new `billing.py` router if one exists — check main.py):

```python
@router.get("/earnings/summary")
async def get_earnings_summary(
    current_user: dict = Depends(get_current_user),
    db=Depends(get_control_plane_db)
):
    """Returns earnings summary. Grotap users see all apps; creators see only their apps."""
    email = current_user.get("email", "")
    is_grotap = email.endswith("@grotap.com")

    if is_grotap:
        rows = await db.fetch("""
            SELECT
                a.app_id, a.slug, a.name, a.icon,
                COALESCE(a.creator_revenue_pct, 0) AS creator_revenue_pct,
                COUNT(e.earning_id) AS payment_count,
                COALESCE(SUM(e.amount_cents), 0) AS total_cents,
                COALESCE(SUM(e.creator_share_cents), 0) AS creator_share_cents,
                COALESCE(SUM(e.platform_share_cents), 0) AS platform_share_cents
            FROM apps a
            LEFT JOIN app_earnings e ON e.app_id = a.app_id
            GROUP BY a.app_id, a.slug, a.name, a.icon, a.creator_revenue_pct
            ORDER BY total_cents DESC
        """)
    else:
        tenant_id = current_user.get("tenant_id")
        rows = await db.fetch("""
            SELECT
                a.app_id, a.slug, a.name, a.icon,
                COALESCE(a.creator_revenue_pct, 0) AS creator_revenue_pct,
                COUNT(e.earning_id) AS payment_count,
                COALESCE(SUM(e.amount_cents), 0) AS total_cents,
                COALESCE(SUM(e.creator_share_cents), 0) AS creator_share_cents,
                COALESCE(SUM(e.platform_share_cents), 0) AS platform_share_cents
            FROM apps a
            LEFT JOIN app_earnings e ON e.app_id = a.app_id
            WHERE a.creator_tenant_id = $1
            GROUP BY a.app_id, a.slug, a.name, a.icon, a.creator_revenue_pct
            ORDER BY total_cents DESC
        """, tenant_id)

    return {
        "earnings": [dict(r) for r in rows],
        "total_platform_cents": sum(r["platform_share_cents"] for r in rows),
        "total_creator_cents": sum(r["creator_share_cents"] for r in rows),
    }
```

Check if `app_earnings` has columns `earning_id`, `app_id`, `amount_cents`, `creator_share_cents`, `platform_share_cents`. If the column names differ, adjust the query to match. Run:
```
SELECT column_name FROM information_schema.columns WHERE table_name='app_earnings';
```
via the Neon HTTP API (NEON_API_KEY from process.env, project green-rice-76766370) to confirm columns, then adjust the query.

If there's no `/billing` router, add the endpoint to `app_registry.py` with prefix `/app-registry/earnings/summary` or create a `billing.py` router — check main.py for existing routers.

### Step 3 — Create EarningsPage.tsx

Create `frontend/src/pages/EarningsPage.tsx`.

Simple table showing:
- App icon + name
- Revenue split (e.g. "80% creator / 20% platform")
- Payments count
- Total revenue (format cents as "$X.XX")
- Creator share / Platform share

Show total row at bottom.

If no earnings data: show "No earnings recorded yet."

Use `GET /app-registry/earnings/summary` (or wherever you added the endpoint).

Grotap users see all apps. Non-grotap users see only their creator apps.

### Step 4 — Add route

In App.tsx add:
```tsx
<Route path="/earnings" element={<PrivateRoute><EarningsPage /></PrivateRoute>} />
```

In TopNav.tsx — check if there's a billing/setup section. Add an "Earnings" link visible when user has creator apps or is grotap user. Add it near "Setup" or after "My Apps". Read TopNav.tsx first to find the right location.

### Step 5 — Deploy backend

```bash
cd platform/backend
railway up --service 6cad7f74-9329-406e-b733-719a33c53ac3
```
Check: `railway deployment list --service 6cad7f74-9329-406e-b733-719a33c53ac3`
If FAILED: `railway logs <deployment_id>`

### Step 6 — Commit

```
git add -A
git commit -m "feat: app earnings reporting endpoint + UI (#946)"
git push origin master
```
