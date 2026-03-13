---
title: "App Store Model — Full DB & API Spec"
updated: 2026-03-05
doc_type: reference
category: architecture
tags: [app-store, database, api, workos, stripe]
status: active
---

# App Store Model — DB & API Spec

## Control Plane Tables

### `apps` — Master app registry
```sql
CREATE TABLE apps (
    app_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug TEXT NOT NULL UNIQUE,               -- e.g. 'agent-pipeline'
    name TEXT NOT NULL,
    description TEXT,
    long_description TEXT,
    icon TEXT NOT NULL DEFAULT '📦',
    category TEXT NOT NULL DEFAULT 'Platform', -- Finance|Legal|HR|Operations|Platform|Infrastructure|Internal
    has_mobile BOOLEAN DEFAULT false,         -- shows 📱 icon on card
    status TEXT DEFAULT 'beta'
        CHECK (status IN ('active','beta','building','deprecated')),
    is_free BOOLEAN DEFAULT false,            -- included for all tenants
    is_internal BOOLEAN DEFAULT false,        -- grotap.com users only
    creator_tenant_id UUID REFERENCES tenants(tenant_id), -- null = Grotap built-in
    creator_revenue_pct INTEGER DEFAULT 80,   -- 0 for Grotap apps
    workos_feature_id TEXT,                   -- WorkOS Feature slug
    stripe_price_id TEXT,                     -- null if free
    version TEXT DEFAULT '1.0.0',
    screenshots JSONB DEFAULT '[]',           -- R2 keys
    tags TEXT[] DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
```

### `tenant_app_subscriptions`
```sql
CREATE TABLE tenant_app_subscriptions (
    tenant_id UUID NOT NULL REFERENCES tenants(tenant_id),
    app_id UUID NOT NULL REFERENCES apps(app_id),
    stripe_subscription_item_id TEXT,
    status TEXT DEFAULT 'active'
        CHECK (status IN ('active','cancelled','trial')),
    subscribed_at TIMESTAMPTZ DEFAULT now(),
    cancelled_at TIMESTAMPTZ,
    PRIMARY KEY (tenant_id, app_id)
);
CREATE INDEX ON tenant_app_subscriptions(tenant_id);
CREATE INDEX ON tenant_app_subscriptions(app_id);
```

### `app_suggestions` — Community idea board
```sql
CREATE TABLE app_suggestions (
    suggestion_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(tenant_id),
    submitter_user_id TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    use_case TEXT,
    target_industry TEXT,
    images JSONB DEFAULT '[]',
    vote_count INTEGER DEFAULT 0,
    status TEXT DEFAULT 'submitted'
        CHECK (status IN ('submitted','voting','accepted','building','rejected','launched')),
    linked_app_id UUID REFERENCES apps(app_id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
```

### `app_suggestion_votes`
```sql
CREATE TABLE app_suggestion_votes (
    suggestion_id UUID NOT NULL REFERENCES app_suggestions(suggestion_id),
    user_id TEXT NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (suggestion_id, user_id)
);
```

### `app_earnings` — Creator revenue tracking
```sql
CREATE TABLE app_earnings (
    earning_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    app_id UUID NOT NULL REFERENCES apps(app_id),
    paying_tenant_id UUID NOT NULL REFERENCES tenants(tenant_id),
    amount_cents INTEGER NOT NULL,
    creator_amount_cents INTEGER NOT NULL,  -- amount_cents * creator_revenue_pct / 100
    stripe_invoice_id TEXT,
    period_start TIMESTAMPTZ,
    period_end TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

### `app_schema_migrations` — App schema lifecycle per tenant

```sql
CREATE TABLE app_schema_migrations (
  tenant_id          UUID NOT NULL REFERENCES tenants(tenant_id),
  app_slug           TEXT NOT NULL REFERENCES apps(slug),
  migration_version  TEXT NOT NULL,          -- e.g. 'v001_initial'
  applied_at         TIMESTAMPTZ DEFAULT now(),
  schema_status      TEXT DEFAULT 'active'
    CHECK (schema_status IN ('active','suspended','dropped')),
  neon_project_id    TEXT NOT NULL,          -- tenant's Neon project ID
  PRIMARY KEY (tenant_id, app_slug, migration_version)
);
CREATE INDEX ON app_schema_migrations(tenant_id);
CREATE INDEX ON app_schema_migrations(app_slug);
```

> Full schema-per-app design: `docs/03-database/neon-app-schema-architecture.md`

---

### `bug_reports` — Extended with Cobrowse/Neon snapshot fields
```sql
-- Added to existing bug_reports table:
ALTER TABLE bug_reports ADD COLUMN cobrowse_session_id TEXT;
ALTER TABLE bug_reports ADD COLUMN neon_branch_id TEXT;
ALTER TABLE bug_reports ADD COLUMN snapshot_db_url TEXT;
ALTER TABLE bug_reports ADD COLUMN cobrowse_replay_url TEXT;
ALTER TABLE bug_reports ADD COLUMN test_run_id TEXT;
```

---

## Support Views

```sql
-- View: all tenants using a given app
CREATE VIEW app_tenant_summary AS
SELECT a.app_id, a.name AS app_name, a.slug, a.status AS app_status,
    t.tenant_id, t.name AS tenant_name, t.organization_id,
    sub.status AS sub_status, sub.subscribed_at,
    COUNT(DISTINCT s.id) AS session_count,
    MAX(s.created_at) AS last_activity
FROM apps a
JOIN tenant_app_subscriptions sub ON sub.app_id = a.app_id
JOIN tenants t ON t.tenant_id = sub.tenant_id
LEFT JOIN agent_sessions s ON s.tenant_id = t.tenant_id::TEXT AND s.app_id = a.slug
GROUP BY a.app_id, a.name, a.slug, a.status, t.tenant_id, t.name, t.organization_id,
    sub.status, sub.subscribed_at;

-- View: all apps for a given tenant
CREATE VIEW tenant_app_summary AS
SELECT t.tenant_id, t.name AS tenant_name, t.organization_id,
    t.subscription_status, t.stripe_customer_id,
    COUNT(DISTINCT sub.app_id) AS app_count,
    COUNT(DISTINCT s.id) AS total_sessions,
    MAX(s.created_at) AS last_activity
FROM tenants t
LEFT JOIN tenant_app_subscriptions sub ON sub.tenant_id = t.tenant_id AND sub.status = 'active'
LEFT JOIN agent_sessions s ON s.tenant_id = t.tenant_id::TEXT
GROUP BY t.tenant_id, t.name, t.organization_id, t.subscription_status, t.stripe_customer_id;
```

---

## API Endpoints

### `GET /app-registry/apps`
Returns full app catalog. For grotap users: all apps. For tenant users: all apps with `is_subscribed` flag based on `tenant_app_subscriptions`.

### `GET /app-registry/apps/my`
Returns only apps the current tenant is subscribed to (or all for grotap users).

### `POST /app-registry/apps/{app_id}/subscribe`
1. Insert `tenant_app_subscriptions` row
2. Call `workos_provider.enable_feature(org_id, app_slug)`
3. Create Stripe subscription item if `stripe_price_id` set

### `DELETE /app-registry/apps/{app_id}/subscribe`
1. Set `tenant_app_subscriptions.status = 'cancelled'`
2. Call `workos_provider.disable_feature(org_id, app_slug)`
3. Cancel Stripe subscription item

### `POST /app-registry/register` *(agent-use)*
Agents call this after building a new app. Accepts `app.manifest.json` body.
1. Validate manifest fields
2. Insert into `apps` table
3. Create WorkOS Feature
4. Create Stripe Price (if paid)

### `GET /app-suggestions`
Paginated list of suggestions, sorted by vote_count DESC.

### `POST /app-suggestions`
Submit new idea. Body: `{title, description, use_case, target_industry, images}`.

### `POST /app-suggestions/{id}/vote`
Upsert vote. One vote per user per suggestion.

### `PATCH /app-suggestions/{id}/status` *(grotap admin only)*
Update suggestion status. When set to `building`, trigger Inngest event `app/suggestion.accepted`.

### `GET /support/apps`
Grotap-only. Returns `app_tenant_summary` view data.

### `GET /support/tenants`
Grotap-only. Returns `tenant_app_summary` view data.

### `POST /auth/switch-tenant` *(grotap users only)*
Body: `{target_org_id}`. Returns new JWT scoped to target org. Used for testing client experiences.

---

## WorkOS Feature Integration

```python
# providers/workos_provider.py additions
def enable_feature(org_id: str, feature_slug: str):
    """Enable a WorkOS Feature for an org on app subscribe"""
    workos.features.create_feature_grant(
        organization_id=org_id,
        feature_key=feature_slug
    )

def disable_feature(org_id: str, feature_slug: str):
    """Disable a WorkOS Feature for an org on app cancel"""
    workos.features.delete_feature_grant(
        organization_id=org_id,
        feature_key=feature_slug
    )

def get_active_features(org_id: str) -> list[str]:
    """Get list of active feature slugs for JWT claims"""
    grants = workos.features.list_feature_grants(organization_id=org_id)
    return [g.feature_key for g in grants.data]
```

Frontend reads active features from JWT → renders only subscribed app cards in My Apps.

---

## Migration Files

| File | Purpose |
|---|---|
| `platform/migrations/control_plane_apps.sql` | apps, tenant_app_subscriptions, app_suggestions, app_suggestion_votes, app_earnings, views |
| `platform/migrations/control_plane_app_schema_migrations.sql` | app_schema_migrations table |
| `platform/migrations/bug_reports_cobrowse_fields.sql` | Add cobrowse_session_id, neon_branch_id, cobrowse_replay_url, test_run_id to bug_reports |
| `platform/migrations/apps/{slug}/v001_initial.sql` | Per-app schema migration (one folder per app) |

## Agent Instructions

- **Use this when:** Building the app registry backend, writing migrations, or implementing subscribe/unsubscribe flows
- **Before this:** `platform-summary.md` for UX context
- **Deep dive DB design:** `docs/03-database/neon-app-schema-architecture.md`
- **After this:** `app-lifecycle.md` for status transitions, `app-revenue-model.md` for billing
