---
title: "Neon Sample Schema — App Schemas + Tenant Knowledge"
updated: 2026-03-06
doc_type: reference
category: database
tags: [neon, pageindex, schema, sample, reference]
status: active
---

# Neon Sample Schema

Reference SQL for app schemas and the tenant knowledge AI layer. See `neon-app-schema-architecture.md` for the full 4-layer model.

## App Schema (per subscribed app)

Each app creates its own PostgreSQL schema in the tenant's Neon project via the subscribe Inngest worker. Template to follow for every app migration:

```sql
-- Example: RFID Pipe app — platform/migrations/apps/rfid-pipe/v001_initial.sql
CREATE SCHEMA IF NOT EXISTS rfid_pipe;

CREATE TABLE rfid_pipe.scan_sessions (
  session_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   UUID NOT NULL,
  scanned_by  TEXT NOT NULL,
  device_name TEXT,
  scan_date   DATE NOT NULL,
  time_synced TIMESTAMPTZ DEFAULT now(),
  total_scans INTEGER DEFAULT 0,
  status      TEXT DEFAULT 'new'
    CHECK (status IN ('new','reviewed','applied','archived','deleted')),
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- RLS on every table — mandatory
ALTER TABLE rfid_pipe.scan_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON rfid_pipe.scan_sessions
  USING (tenant_id = (SELECT current_setting('app.current_tenant_id')::uuid));
```

**Schema naming:** app slug → snake_case (`rfid-pipe` → `rfid_pipe`, `knowledge-base` → `knowledge_base`)

## Tenant Knowledge Schema (AI layer)

Created once per tenant project during tenant provisioning. Not per-app — shared across all apps for that tenant.

```sql
CREATE SCHEMA IF NOT EXISTS tenant_knowledge;

-- Document registry
CREATE TABLE tenant_knowledge.documents (
  doc_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID NOT NULL,
  document_name TEXT NOT NULL,
  source_r2_key TEXT,             -- R2 object key for original file
  metadata      JSONB DEFAULT '{}',
  created_at    TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON tenant_knowledge.documents USING GIN (metadata);

-- PageIndex trees (reasoning-based retrieval)
CREATE TABLE tenant_knowledge.index_trees (
  tree_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_id     UUID REFERENCES tenant_knowledge.documents(doc_id),
  tenant_id  UUID NOT NULL,
  index_tree JSONB NOT NULL,     -- Full hierarchical PageIndex tree
  raw_text   TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON tenant_knowledge.index_trees USING GIN (index_tree);

-- Vector chunks (pgvector similarity search)
CREATE TABLE tenant_knowledge.chunks (
  chunk_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_id      UUID REFERENCES tenant_knowledge.documents(doc_id),
  tenant_id   UUID NOT NULL,
  content     TEXT NOT NULL,
  embedding   vector(1536),
  chunk_index INTEGER,
  created_at  TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX ON tenant_knowledge.chunks USING hnsw (embedding vector_cosine_ops);

-- RLS on all knowledge tables
ALTER TABLE tenant_knowledge.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_knowledge.index_trees ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_knowledge.chunks ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON tenant_knowledge.documents
  USING (tenant_id = (SELECT current_setting('app.current_tenant_id')::uuid));
CREATE POLICY tenant_isolation ON tenant_knowledge.index_trees
  USING (tenant_id = (SELECT current_setting('app.current_tenant_id')::uuid));
CREATE POLICY tenant_isolation ON tenant_knowledge.chunks
  USING (tenant_id = (SELECT current_setting('app.current_tenant_id')::uuid));
```

---

## Agent Instructions

- **Use this when:** Writing app schema migrations or setting up tenant knowledge layer
- **Architecture context:** `neon-app-schema-architecture.md`
- **Ingestion pipeline:** `neon-pageindex-integration.md`
- **After this:** Implement schema migrations for each app under `platform/migrations/apps/{slug}/`
