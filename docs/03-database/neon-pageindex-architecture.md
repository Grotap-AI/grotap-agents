---
title: "Neon PageIndex Database Architecture"
updated: 2026-03-06
doc_type: architecture
category: database
tags: [neon, pageindex, architecture, multitenant]
status: active
---

# Neon PageIndex Database Architecture

> Full 4-layer model: `neon-app-schema-architecture.md`. This doc focuses on PageIndex tree placement and retrieval patterns within that model.

## Core Strategy

PageIndex replaces flat vector stores with hierarchical JSON trees stored in Neon JSONB columns. This enables reasoning-based retrieval: agents navigate the tree structure rather than doing pure embedding similarity.

## Where Trees Live

| Tree Type | Neon Location | Queried By |
|---|---|---|
| Tenant uploaded docs | `{tenant_db}.tenant_knowledge.index_trees` | All app agents for that tenant |
| App domain rules | App Knowledge Project `app_rules.index_tree` | Agents within that app domain |
| Platform constraints | Platform Rules DB `platform_rules.index_tree` | All agents — pre-task check |

## Multi-Document Search Patterns

**1. Metadata filter (fastest):**
```sql
SELECT document_name, index_tree
FROM tenant_knowledge.documents
WHERE metadata @> '{"year": 2024, "category": "Legal"}'::jsonb;
```
Use GIN index on `metadata`. Best for structured ERP data with known filter fields.

**2. Description scan (medium volume):**
Store a brief text summary per document. LLM reads summaries first → selects which full trees to open. Avoids loading all trees into context.

**3. Hybrid semantic (high volume):**
pgvector broad similarity search on document summaries → top 3-5 candidates → PageIndex tree reasoning on those candidates. Combines speed of vectors with precision of tree reasoning.

## Component Responsibilities

| Component | Role |
|---|---|
| Tenant Router | Selects correct Neon project based on `tenant_id` |
| Neon (Tenant DB) | Stores relational app tables + PageIndex JSONB trees |
| PageIndex Engine | Reasoning-based navigation through selected trees |
| LLM Orchestrator | Decides which trees to open via metadata or summary scan |

## JSONB Performance

Always use `JSONB` (not `JSON`) for tree storage — binary format is faster to process and supports GIN indexing for complex tree searches.

```sql
CREATE INDEX ON tenant_knowledge.index_trees USING GIN (index_tree);
```

For high-traffic tenants, use partial indexes on known JSON keys:
```sql
CREATE INDEX ON tenant_knowledge.documents ((metadata->>'doc_type'))
  WHERE metadata->>'doc_type' IS NOT NULL;
```

---

## Agent Instructions

- **Use this when:** Implementing agent context loading, PageIndex ingestion, or tree search
- **Before this:** `neon-app-schema-architecture.md`, `neon-basics.md`
- **After this:** `neon-pageindex-integration.md` for implementation detail
