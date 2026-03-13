---
title: "Support Portal — grotap Internal Data Views"
updated: 2026-03-05
doc_type: reference
category: platform
tags: [support, admin, internal, grotap, tenants]
status: active
---

# Support Portal — grotap Internal App

**Route:** `/support`
**Access:** `@grotap.com` email only (enforced in backend + frontend)
**App registry:** `slug: support-portal`, `is_internal: true`

---

## Purpose

Grotap support and admin team can:
1. View all client (tenant) data organized by app or by client
2. Switch into any tenant's context to test their experience
3. Monitor app health, usage, and subscription status across all tenants

---

## Access Control

### Backend guard (all `/support` routes)
```python
# app/routers/support.py
async def require_grotap_user(current_user = Depends(get_current_user)):
    email = current_user.get("email", "")
    if not email.endswith("@grotap.com"):
        raise HTTPException(403, "Support portal: grotap users only")
    return current_user
```

### Frontend guard (TopNav + routing)
```typescript
// TopNav.tsx
const isGrotapUser = user?.email?.endsWith('@grotap.com') ?? false;

// App.tsx
<Route path="/support" element={
  <PrivateRoute requireGrotap>
    <SupportPage />
  </PrivateRoute>
} />
```

`requireGrotap` prop on `PrivateRoute` redirects non-grotap users to `/` with a toast: "Access restricted".

---

## Page Structure (`SupportPage.tsx`)

Seven tabs/screens:

### Tab 1: By App
- Dropdown/search: select any app from `apps` table
- Table below: all tenants using that app
  - Tenant name, org ID, subscription status, subscribed date, session count, last activity
  - Action: "View as Tenant" button → triggers tenant context switch
- Summary stats: total subscribers, avg sessions/month, top users

### Tab 2: By Client
- Dropdown/search: select any tenant
- Shows all apps they have subscribed, their billing status, Stripe customer ID
- Session stats, last activity, error rate
- Action: "View as this Client" → tenant context switch
- Export button: `GET /support/tenants/{id}/export` → JSON of all tenant data

### Tab 3: Tenant Switcher
- Search all tenants by name or org ID
- Click → context switch
- **Banner appears in TopNav** while switched: `"Viewing as: [Tenant Name] — [Exit]"`
- Exit button restores original grotap user context

### Tab 4: Active Users
- Lists all currently logged-in users across all tenants
- Columns: User email, Tenant name, App they're currently on, Last activity, Status
- **Join Session** button per row — initiates a Cobrowse session with that user
  - User must click "Allow" in their browser before the support agent can see their screen
  - Session uses `lib/cobrowse.ts` wrapper (Rule 9 — never call Cobrowse SDK directly)
- Grotap users with "Open for Support = true" receive pop-up pings from any user who clicks "Ping for Live Help Now" in the Help menu

### Tab 5: Scheduled Appointments
- Grid of all live-help meetings scheduled via the "Schedule a Live Meet Up" option in the app Help menu
- Columns: Tenant, User email, App, Requested date/time, Duration (15/30/45 min), Assigned to, Status
- **Assign** dropdown per row — assign to any Grotap team member
- Status options: Pending, Assigned, Completed, Cancelled
- Grotap team member receives notification when an appointment is assigned to them

### Tab 6: New App Requests
- Grid of all items submitted via "Submit an App Enhancement" or "Submit an App Issue" or "Submit a New App Idea" from any app's Help menu
- Columns: Type (Enhancement / Issue / New App), App, Submitted by, Tenant, Date, Title, Status
- Click a row to open detail view
- **In detail view:** Grotap user can work with the Claude plugin directly in the support app to generate a set of MD files for that app/feature
  - MD files are stored as a new project: project name = app name
  - Once MD files exist for the project, a **"Submit to Agent Queue"** button appears
  - Clicking submits the project to the agent build queue (see `app-suggestions.md` for queue behavior)
- Status options: New, In Review, MD Files Created, In Agent Queue, Building, Done, Rejected

### Tab 7: Agent Questions Queue
- Lists all pending questions raised by the agent team during a build, grouped by App or Bug Report
- Columns: App/Bug Report name, Question text, Asked at, Status (Unanswered / Answered), Answered by
- Grotap users or the submitting tenant can answer questions directly in this screen
- **Answer** button per question → opens a text input; saving changes status to Answered and notifies the agent
- Additional details and context can be added as follow-up notes per question
- Once all questions for a project are answered, the agent team resumes the build

---

## Tenant Context Switching

### Backend endpoint
```python
@router.post("/auth/switch-tenant")
async def switch_tenant(
    target_org_id: str,
    current_user = Depends(require_grotap_user)
):
    tenant = await control_plane.get_tenant_by_org(target_org_id)
    # Issue a short-lived JWT scoped to target org
    # Original user identity preserved in 'switched_by' claim
    new_token = create_impersonation_jwt(
        user_id=current_user["user_id"],
        email=current_user["email"],
        org_id=target_org_id,
        tenant_id=str(tenant["tenant_id"]),
        switched_by=current_user["email"],
        expires_in=3600  # 1 hour max
    )
    return {"access_token": new_token, "tenant_name": tenant["name"]}
```

### Frontend behavior
```typescript
// AuthContext.tsx
const switchTenant = async (targetOrgId: string) => {
    const { access_token, tenant_name } = await api.post('/auth/switch-tenant', { target_org_id: targetOrgId });
    setSwitchedFrom(currentOrgId);
    setSwitchedTenantName(tenant_name);
    setToken(access_token);  // replaces current JWT
    navigate('/');           // goes to My Apps for that tenant
};

const exitSwitch = () => {
    setToken(originalToken);  // restore grotap user JWT
    setSwitchedFrom(null);
    navigate('/support');
};
```

---

## API Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| `GET` | `/support/apps` | grotap only | `app_tenant_summary` view — list all apps with subscriber data |
| `GET` | `/support/apps/{slug}/tenants` | grotap only | All tenants using specific app |
| `GET` | `/support/tenants` | grotap only | `tenant_app_summary` view — all tenants with app counts |
| `GET` | `/support/tenants/{id}` | grotap only | Specific tenant: all apps, billing, sessions |
| `GET` | `/support/tenants/{id}/export` | grotap only | Full tenant data export as JSON |
| `POST` | `/auth/switch-tenant` | grotap only | Get impersonation JWT for target org |
| `GET` | `/support/active-users` | grotap only | All currently logged-in users across tenants |
| `GET` | `/support/appointments` | grotap only | All scheduled live-help appointments |
| `PATCH` | `/support/appointments/{id}` | grotap only | Assign or update appointment status |
| `GET` | `/support/app-requests` | grotap only | All app enhancement/issue/idea submissions |
| `PATCH` | `/support/app-requests/{id}` | grotap only | Update status, attach MD project |
| `GET` | `/support/agent-questions` | grotap only | All pending agent questions across builds |
| `POST` | `/support/agent-questions/{id}/answer` | grotap only | Submit answer to an agent question |

---

## Data Views (from control plane)

The support portal reads from the two views in the control plane:

**`app_tenant_summary`** — queried for "By App" tab:
```sql
SELECT * FROM app_tenant_summary WHERE slug = 'agent-pipeline'
ORDER BY subscribed_at DESC;
```

**`tenant_app_summary`** — queried for "By Client" tab:
```sql
SELECT * FROM tenant_app_summary WHERE tenant_id = $1;
```

---

## Agent Instructions

- **Use this when:** Building the Support Portal app (`/support` route, `SupportPage.tsx`, `app/routers/support.py`)
- **Before this:** `app-store-model.md` for DB views spec
- **Rules:** Access guard is required on ALL support endpoints. Never return data to non-grotap users.
