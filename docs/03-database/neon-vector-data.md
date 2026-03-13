---
title: "Neon Vector Data — pgvector + pgrag"
updated: 2026-03-06
doc_type: reference
category: database
tags: [neon, pgvector, pgrag, rag, embeddings]
status: active
---

# Neon Vector Data — pgvector + pgrag

Neon supports document vectorization via the `pgrag` extension and vector storage/search via `pgvector`. Both are used in the `tenant_knowledge` schema and in App Knowledge Projects.

## Document Processing Pipeline

```
R2 (raw file storage)
  → pgrag: extract text from PDF/Word
  → pgrag: chunk by character or token count
  → pgvector: store embeddings in tenant_knowledge.chunks
  → PageIndex: build hierarchical tree → tenant_knowledge.index_trees
```

### pgrag Functions

```sql
rag.text_from_pdf(bytea)
rag.chunks_by_character_count(text, max_chars, max_overlap)
rag.chunks_by_token_count(text, max_tokens, max_overlap)
```

### pgvector Similarity Search

```sql
-- Find 3 most relevant chunks for a query vector
SELECT content FROM tenant_knowledge.chunks
ORDER BY embedding <=> '[query_vector]'::vector
LIMIT 3;
```

Use HNSW index for fast approximate nearest-neighbor search:
```sql
CREATE INDEX ON tenant_knowledge.chunks USING hnsw (embedding vector_cosine_ops);
```

## RAG Workflow

1. Embed user query with same model used for indexing (`text-embedding-3-small`)
2. pgvector similarity search → top 3-5 candidate chunks
3. PageIndex reasoning-based tree search on those candidates → exact node match
4. Inject retrieved context into LLM prompt

**Hybrid approach:** pgvector for broad candidate retrieval → PageIndex for precise reasoning within candidates.

## Where Vector Data Lives

| Data | Location | Schema |
|---|---|---|
| Tenant uploaded docs | Tenant DB | `tenant_knowledge.chunks` |
| Tenant PageIndex trees | Tenant DB | `tenant_knowledge.index_trees` |
| App domain rules | App Knowledge Project | `app_rules.embedding` |
| Platform constraint rules | Platform Rules DB | `platform_rules.embedding` |

See `neon-app-schema-architecture.md` for full layer breakdown.

## Tools

- **LangChain `PGVector`** — embedding storage and similarity search utilities
- **PageIndex** — reasoning-based tree retrieval (primary knowledge layer)
- **LangGraph** — agent orchestration over retrieved context

**Not used:** LlamaIndex. All retrieval flows through PageIndex + Neon pgvector via LangChain/LangGraph.

---

## Agent Instructions

- **Use this when:** Implementing document ingestion, embedding storage, or RAG retrieval
- **Before this:** `neon-app-schema-architecture.md` — understand where data lives
- **After this:** `neon-pageindex-integration.md` for full ingestion pipeline
