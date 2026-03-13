---
title: "Neon App Schema Architecture — 4-Layer Design"
updated: 2026-03-06
doc_type: architecture
category: database
tags: [neon, schema, multitenant, app-isolation, vector, pageindex]
status: active
---

# Neon App Schema Architecture — 4-Layer Design

> **Source of truth** for all database structure decisions on this platform. All app development must follow this model.

## Overview

The platform uses 4 distinct Neon layers to cleanly separate operational data, AI knowledge, and platform rules — without commingling app data across tenants or between different apps.

```
Layer 1 — Control Plane DB     (1 project total)    green-rice-76766370
Layer 2 — Per-Tenant Ops DB    (1 per tenant)       e.g. proud-union-74070434
Layer 3 — App Knowledge DBs    (1 per app type)     e.g. rfid-pipe-knowledge
Layer 4 — Platform Rules DB    (1 project total)    ingested from docs/
```

---

## Layer 1: Control Plane DB

**Project:** `green-rice-76766370`

Platform metadata only. No tenant operational data, no app business data.

Tables: `apps`, `tenants`, `tenant_app_subscriptions`, `app_suggestions`, `app_suggestion_votes`, `app_earnings`, **`app_schema_migrations`**

### `app_schema_migrations` (added 2026-03-06)

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

---

## Layer 2: Per-Tenant Operational DB

One Neon project per tenant. Each subscribed app gets its own **PostgreSQL schema** within that project.

```
tenant DB (e.g. proud-union-74070434)
├── public.*                  ← Platform baseline (users, audit_log)
├── rfid_pipe.*               ← RFID Pipe app (if subscribed)
│   ├── scan_sessions
│   ├── batch_templates
│   └── ignored_rfid_tags
├── finance.*                 ← Finance app (if subscribed)
│   ├── invoices
│   └── ledger_entries
├── hr.*                      ← HR app (if subscribed)
│   ├── employees
│   └── payroll_runs
└── tenant_knowledge.*        ← Tenant AI layer (their uploaded docs)
    ├── documents
    ├── chunks                ← pgvector embeddings
    └── index_trees           ← PageIndex JSONB trees
```

**Schema naming convention:** app slug → snake_case (`rfid-pipe` → `rfid_pipe`, `knowledge-base` → `knowledge_base`)

**Why schema-per-app (not project-per-app):**
- `neon branch` = snapshot of ALL app data for that tenant — critical for Cobrowse snapshot testing
- One connection pool per tenant regardless of how many apps they have
- Cross-app joins are possible when needed (e.g., HR + Finance for payroll)
- Independent migrations per schema, no naming collisions

**Defense in depth:** Every table in every schema includes `tenant_id` + RLS policy. Schema provides structural isolation; RLS provides enforcement isolation.

```sql
-- Pattern for every app table
ALTER TABLE rfid_pipe.scan_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON rfid_pipe.scan_sessions
  USING (tenant_id = (SELECT current_setting('app.current_tenant_id')::uuid));
```

### Subscribe Flow

```
app.subscribed Inngest event
→ Connect to tenant's Neon project (from tenants.neon_project_id)
→ CREATE SCHEMA IF NOT EXISTS {app_slug_snake}
→ Run platform/migrations/apps/{slug}/v001_initial.sql
→ Run subsequent versions in order
→ Record each version in control plane app_schema_migrations
→ WorkOS feature enabled → app appears in tenant's My Apps
```

### Unsubscribe Flow

```
Tenant cancels
→ schema_status = 'suspended' (data preserved 30 days)
→ Day 30: export schema to R2 as pg_dump
→ DROP SCHEMA {app_slug} CASCADE
→ schema_status = 'dropped' in app_schema_migrations
```

### Migration File Convention

```
platform/migrations/apps/
├── rfid-pipe/
│   ├── v001_initial.sql
│   └── v002_add_ignored_tags.sql
├── finance/
│   └── v001_initial.sql
└── hr/
    └── v001_initial.sql
```

Agents building a new app **must** create `v001_initial.sql` under `platform/migrations/apps/{slug}/`.

---

## Layer 3: App Knowledge Projects

One Neon project per app type — platform-managed, not tenant data.

**Purpose:** Domain business rules, agent prompts, industry reference docs specific to that app's problem domain. Agents consult this *after* Platform Rules (Layer 4) and *before* Tenant Knowledge.

**Provisioned when:** App status moves from `building` → `beta`.

```sql
-- Domain rules ingested from app spec .md files
CREATE TABLE app_rules (
  rule_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  app_slug   TEXT NOT NULL,
  rule_type  TEXT CHECK (rule_type IN ('constraint','workflow','validation','business_logic')),
  title      TEXT,
  content    TEXT,
  embedding  vector(1536),     -- pgvector similarity search
  index_tree JSONB,            -- PageIndex tree for reasoning
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON app_rules USING hnsw (embedding vector_cosine_ops);
CREATE INDEX ON app_rules USING GIN (index_tree);

-- Agent prompt templates scoped to app scenarios
CREATE TABLE agent_prompts (
  prompt_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  app_slug      TEXT NOT NULL,
  scenario      TEXT,          -- 'onboarding'|'bulk_scan'|'exception_handling'
  system_prompt TEXT,
  embedding     vector(1536),
  created_at    TIMESTAMPTZ DEFAULT now()
);

-- Domain reference data (industry standards, best practices)
CREATE TABLE domain_knowledge (
  doc_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title      TEXT,
  content    TEXT,
  embedding  vector(1536),
  index_tree JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

**App manifest declares the knowledge project:**
```json
{
  "db_schema": "rfid_pipe",
  "migrations": ["v001_initial.sql"],
  "knowledge_project_id": "<neon-project-id>",
  "business_rules_docs": ["rfid-scanning-rules.md", "batch-processing-rules.md"]
}
```

---

## Layer 4: Platform Rules DB

One Neon project — ingested from `docs/` platform rules (9 absolute rules, never-do constraints, CLAUDE.md). Agents query this **first** before any task begins.

**Purpose:** Makes platform rules queryable by agents at runtime, not just readable at build time.

```sql
CREATE TABLE platform_rules (
  rule_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_number INTEGER,
  title       TEXT,
  content     TEXT,
  severity    TEXT CHECK (severity IN ('absolute','mandatory','advisory')),
  embedding   vector(1536),
  index_tree  JSONB
);
CREATE INDEX ON platform_rules USING hnsw (embedding vector_cosine_ops);
```

---

## Agent RAG Query Hierarchy

Agents consult rules in this order before executing any task:

```
1. Layer 4 — Platform Rules DB    → "Can I do this at all?" (9 rules, never-do)
2. Layer 3 — App Knowledge DB     → "What are the domain rules for this app?"
3. Layer 2 — tenant_knowledge.*   → "What does THIS tenant's uploaded docs say?"
```

Result is injected into agent context before tool use.

---

## Rollout Phases

| Phase | Work | Trigger |
|---|---|---|
| 1 | Move RFID Pipe flat tables → `rfid_pipe` schema; add `app_schema_migrations` to control plane | After RFID Wave 2 agent build complete |
| 2 | Inngest subscribe worker: create schema + run migrations for all new subscriptions | After Phase 1 |
| 3 | Provision App Knowledge Projects per existing app; ingest spec docs | After Phase 2 |
| 4 | Platform Rules DB: ingest CLAUDE.md + never-do docs; wire into agent precheck node | After Phase 3 |

---

## Agent Instructions

- **Use this when:** Designing app DB structure, writing app migrations, building the subscribe worker, implementing agent knowledge context
- **Before this:** `app-store-model.md` for control plane schema, `neon-billing.md` for project provisioning
- **Also read:** `neon-sample-schema.md` for concrete SQL patterns, `neon-vector-data.md` for pgvector setup
- **After this:** Write migration files in `platform/migrations/apps/{slug}/`
