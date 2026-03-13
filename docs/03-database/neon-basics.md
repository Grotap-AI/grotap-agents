---
title: "Neon and PageIndex Basics"
updated: 2026-03-06
doc_type: reference
category: database
tags: [neon, pageindex, multitenant, basics, overview]
status: active
---

# Neon and PageIndex Basics

Neon handles relational data isolation (project-per-tenant, schema-per-app). PageIndex handles the AI knowledge layer by storing document structures as JSON hierarchical trees rather than vectors.

## How They Work Together

| Concern | Neon | PageIndex |
|---|---|---|
| Data storage | Relational tables in isolated tenant project | JSON trees stored in Neon JSONB column |
| Multitenancy | Physical isolation via project-per-tenant | Logical isolation via `tenant_id` association |
| AI Retrieval | pgvector for embedding similarity search | Reasoning-based tree search (no embedding needed) |
| Scaling | Autoscales to zero per tenant | Handles long docs without vector overhead |

## Key Concepts

**Vectorless RAG:** PageIndex uses reasoning-based retrieval rather than semantic similarity — removes the need to manage embedding models or vector indexes per tenant.

**Traceable Intelligence:** PageIndex maps content to a Table of Contents structure. Agents get precise section/page references — critical for audit and professional reporting.

**Independent Lifecycle:** A Neon branch includes both relational app tables AND PageIndex trees. Roll back or snapshot a tenant without affecting any other customer.

## Where Data Lives

| Data | Location |
|---|---|
| App operational data | `{tenant_db}.{app_schema}.*` (e.g., `rfid_pipe.scan_sessions`) |
| Tenant uploaded docs + trees | `{tenant_db}.tenant_knowledge.*` |
| App domain rules + vectors | App Knowledge Project (Layer 3) |
| Platform constraint rules | Platform Rules DB (Layer 4) |

Full architecture: `docs/03-database/neon-app-schema-architecture.md`

---

## Agent Instructions

- **Use this when:** Understanding how Neon and PageIndex work together
- **Before this:** None — read early in setup
- **Deep dive:** `docs/03-database/neon-app-schema-architecture.md`
- **After this:** `neon-pageindex-architecture.md`
