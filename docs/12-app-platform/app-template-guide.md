---
title: "App Template Guide — Agent Step-by-Step Build Instructions"
updated: 2026-03-06
doc_type: how-to
category: agents
tags: [app-template, agents, build, cobrowse, workos]
status: active
---

# App Template Guide — Agent Build Instructions

> This is the primary guide agents follow when building a new grotap app from the base template.

## Prerequisites

1. `app/suggestion.accepted` Inngest event received with suggestion metadata
2. GitHub branch created: `feature/app-{suggestion-id}`
3. Agent has access to: `platform/app-template/`, Neon branching API, Cobrowse API

---

## ⛔ CRITICAL — Where App Code Lives

**NEVER build an app as a standalone Vite project inside `platform/apps/{slug}/`.**
The `platform/apps/{slug}/` directory holds **only** `app.manifest.json`.

All app UI code lives in the **main frontend**:
- Page components → `frontend/src/pages/MyAppNamePage.tsx`
- Routes → `frontend/src/App.tsx`
- Shared components → `frontend/src/components/`

The app-template (`platform/app-template/`) exists as a **reference for agents to read** — use it to understand the AppSidebar pattern, but do NOT copy it as a standalone Vite project.

---

## Step 1: Create Manifest Only

Create `platform/apps/{slug}/app.manifest.json`:
```json
{
  "slug": "my-app-slug",
  "name": "My App Name",
  "description": "One or two sentence description",
  "long_description": "Full markdown description of what this app does and who it's for",
  "icon": "📊",
  "category": "Finance",
  "has_mobile": false,
  "status": "beta",
  "version": "1.0.0",
  "routes": ["/my-app", "/my-app/:id"],
  "tags": ["finance", "invoicing", "automation"],
  "db_schema": "my_app_slug",
  "migrations": ["v001_initial.sql"],
  "knowledge_project_id": "",
  "business_rules_docs": ["apps/my-app-slug.md"]
}
```

`db_schema` = slug in snake_case. This schema is created in the tenant's Neon project when they subscribe. See `docs/03-database/neon-app-schema-architecture.md`.

That manifest is the **only** file in `platform/apps/{slug}/`.

---

## Step 1b: Create App Database Migration

Create the schema migration file at `platform/migrations/apps/{slug}/v001_initial.sql`.

Every migration **must**:
1. `CREATE SCHEMA IF NOT EXISTS {db_schema};`
2. Prefix every table with `{db_schema}.`
3. Include `tenant_id UUID NOT NULL` on every table
4. Enable RLS + `tenant_isolation` policy on every table

```sql
CREATE SCHEMA IF NOT EXISTS my_app_slug;

CREATE TABLE my_app_slug.records (
  record_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  UUID NOT NULL,
  -- app-specific columns here
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE my_app_slug.records ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON my_app_slug.records
  USING (tenant_id = (SELECT current_setting('app.current_tenant_id')::uuid));
```

Reference: `platform/migrations/apps/rfid-pipe/v001_initial.sql`

---

## Step 2: Build Pages in the Main Frontend

Create page files directly in `frontend/src/pages/`:
```
frontend/src/pages/
├── MyAppDashboardPage.tsx   ← Main landing page
├── MyAppRecordsPage.tsx     ← Detail/list pages
└── MyAppDetailPage.tsx      ← etc.
```

**Calling backend APIs** — import from the shared lib:
```typescript
import api from '../lib/api';  // JWT-intercepted Axios client

const res = await api.get('/my-app/data');
```

**Cobrowse redaction** — mask sensitive fields with `cb-mask` class:
```tsx
<input className="cb-mask" type="text" placeholder="SSN" />
```

Read `platform/app-template/src/components/AppSidebar.tsx` as a reference for the sidebar/help menu pattern, then implement it directly in your page components.

---

## Step 3: Wire Routes in the Main Frontend App.tsx

Add imports and `<Route>` entries to `frontend/src/App.tsx`:
```tsx
import { MyAppDashboardPage } from './pages/MyAppDashboardPage';
import { MyAppRecordsPage } from './pages/MyAppRecordsPage';
// ...inside <Routes>:
<Route path="/my-app" element={<PrivateRoute><><TopNav /><MyAppDashboardPage /></></PrivateRoute>} />
<Route path="/my-app/records" element={<PrivateRoute><><TopNav /><MyAppRecordsPage /></></PrivateRoute>} />
```

---

## Step 4: Register App in Platform

```bash
curl -X POST https://api.grotap.com/app-registry/register \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -H "Content-Type: application/json" \
  -d @app.manifest.json
```

This creates:
- `apps` table row with `status='building'`
- WorkOS Feature with slug matching app slug
- Stripe Price (if `stripe_price_id` provided in manifest)

---

## Step 5: Run Cobrowse Snapshot Tests

Before setting status to `beta`, run automated tests against a Neon snapshot:

```bash
curl -X POST https://api.grotap.com/cobrowse/agent-test \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "app_slug": "my-app-slug",
    "target_url": "https://app.grotap.com/my-app",
    "scenarios": ["load", "create", "edit", "delete"],
    "use_neon_snapshot": true
  }'
```

The test pipeline:
1. Creates Neon branch snapshot of production DB
2. Starts Cobrowse session (live-viewable in CobrowseConsolePage)
3. Playwright + Claude Vision run each scenario
4. Records .webm → R2, saves Cobrowse session ID
5. Submits bug_reports with `neon_branch_id` + `cobrowse_replay_url`
6. Deletes Neon branch

**Pass criteria:** No CRITICAL or HIGH severity bugs. MEDIUM/LOW = advisory.

---

## Step 6: Submit for Review

```bash
git add .
git commit -m "feat: add {slug} app"
git push origin feature/app-{suggestion-id}
# Run code review pipeline
./agents/review-pipeline.sh feature/app-{suggestion-id}
./agents/collect-reviews.sh --wait feature/app-{suggestion-id}
```

All 4 reviewers must PASS before merge (Rule 8).

---

## Step 7: Promote to Beta

After merge to master, update app status:
```bash
curl -X PATCH https://api.grotap.com/app-registry/apps/{app_id} \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d '{"status": "beta"}'
```

App now appears in Beta Apps tab — free for all tenants to try.

---

## App UX Standards (Required)

Every app must implement the universal UX patterns documented in `app-ux-patterns.md`:

1. **Left sidebar** with all app screens listed
2. **Help hover menu** (lower-left sidebar) with: Request Live Help, Share Screen, Submit an App Enhancement, Submit an App Issue, Submit a New App Idea
3. **Back to Apps** link (lower-left sidebar, above user email, with divider)
4. **App name** displayed at the top — never replaced with back-navigation text

These are non-negotiable layout requirements for every app. See `app-ux-patterns.md` for full spec and ASCII layout diagram.

---

## AppShell — Never Modify

Every app page must be wrapped in `AppShell`:
```tsx
// src/components/AppShell.tsx — DO NOT MODIFY
import { TopNav } from '../../../frontend/src/components/TopNav';
import { CobrowseRemoteControlBanner } from '../../../frontend/src/components/CobrowseRemoteControlBanner';
import { CobrowseRedactionManager } from '../../../frontend/src/components/CobrowseRedactionManager';
import { CobrowseButton } from '../../../frontend/src/components/CobrowseButton';

export function AppShell({ children }) {
  return (
    <>
      <TopNav />
      <CobrowseRemoteControlBanner />
      <CobrowseRedactionManager />
      <CobrowseButton />
      <main style={{ paddingTop: 56 }}>
        {children}
      </main>
    </>
  );
}
```

---

## Checklist for Agents

- [ ] `app.manifest.json` filled in with slug, icon, category, routes, **db_schema, migrations, business_rules_docs**
- [ ] `platform/migrations/apps/{slug}/v001_initial.sql` created (schema + tables + RLS on every table)
- [ ] All page components built in `frontend/src/pages/`
- [ ] `lib/api.ts` used for all API calls (never raw fetch with hardcoded URLs)
- [ ] Sensitive fields marked with `cb-mask` class
- [ ] Left sidebar implemented with all app screens
- [ ] Help hover menu present with all 5 options
- [ ] Back to Apps in lower-left sidebar above user email (with divider)
- [ ] App name at top (not replaced by nav text)
- [ ] `AppShell` used on every page (never removed Cobrowse components)
- [ ] `POST /app-registry/register` called — app in DB with status `building`
- [ ] Cobrowse snapshot test run — no CRITICAL/HIGH bugs
- [ ] 4-reviewer pipeline passed (Build Validator, Logic, Security, Performance)
- [ ] Status promoted to `beta` after merge

---

## Agent Instructions

- **Use this when:** Building a new app from the template — follow steps in order
- **Before this:** `app-lifecycle.md` for status context
- **Also read:** `app-ux-patterns.md` for required sidebar, Help menu, and Back to Apps layout
- **After this:** `app-store-model.md` for DB/API reference if needed
