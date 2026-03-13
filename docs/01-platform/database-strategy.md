---
title: "Database Strategy — Multi-Tenant App Platform"
updated: 2026-03-06
doc_type: architecture
category: database
tags: [neon, multitenant, schema, strategy]
status: active
---

# Database Strategy — Multi-Tenant App Platform

> Full detail: `docs/03-database/neon-app-schema-architecture.md`

## Model: Schema-per-App within Project-per-Tenant

Each tenant has one Neon project. Each app they subscribe to gets its own **PostgreSQL schema** within that project.

**Do not use:**
- Shared tables with `app_slug` discriminator — schemas are independently migratable and cleaner
- Project-per-app-per-tenant — too many projects, breaks Neon branching for Cobrowse snapshot tests
- Flat tables at `public.*` — naming collisions as app count grows

## Isolation Layers

| Layer | Mechanism | Purpose |
|---|---|---|
| Project | One Neon project per tenant | Physical isolation between tenants |
| Schema | One schema per subscribed app | Structural isolation between apps |
| RLS | `tenant_id` on every table | Enforcement isolation (defense in depth) |
| Branch | Neon branch = full tenant state | Safe snapshot testing across all apps |

## The 4 Neon Project Types

| Type | Count | What lives there |
|---|---|---|
| Control Plane | 1 total | App registry, tenant catalog, subscription state, migration tracking |
| Per-Tenant Ops | 1 per tenant | All app schemas + `tenant_knowledge` AI layer |
| App Knowledge | 1 per app type | Domain rules, agent prompts, reference docs (pgvector + PageIndex) |
| Platform Rules | 1 total | 9 absolute rules, never-do constraints — queryable by agents at runtime |

## Key Convention

App slug → snake_case schema name: `rfid-pipe` → `rfid_pipe`, `knowledge-base` → `knowledge_base`

Migration files live at: `platform/migrations/apps/{slug}/v001_initial.sql`

## Terraform

Use Neon Terraform provider to automate tenant project provisioning. Each new project starts with `public` schema only — app schemas are added by the subscribe Inngest worker when a tenant subscribes to each app.

```hcl
resource "neon_project" "tenant" {
  name       = "tenant-${var.tenant_slug}"
  pg_version = 17
  region_id  = "aws-us-east-1"
}
```

---

## Agent Instructions

- **Use this when:** Understanding the overall database strategy
- **Before this:** None — foundational doc, read early
- **Deep dive:** `docs/03-database/neon-app-schema-architecture.md`
- **After this:** `neon-billing.md` for tenant project provisioning API
