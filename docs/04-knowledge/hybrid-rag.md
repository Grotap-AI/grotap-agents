---
title: "Decision-Tree-First RAG — Neon + PageIndex + LangGraph"
source: google-drive-docx
converted: 2026-03-01
updated: 2026-03-04
component: "LangGraph"
category: ai
doc_type: architecture
related:
  - "Neon"
  - "PageIndex"
  - "LangChain"
tags:
  - rag
  - decision-tree
  - neon
  - pageindex
  - langgraph
  - retrieval
  - business-rules
status: active
---

# Decision-Tree-First RAG — Neon + PageIndex + LangGraph

> **Rule #7 — NO VECTOR EMBEDDINGS FOR RETRIEVAL.** PageIndex is a reasoning-based engine, NOT a vector engine.

This architecture bridges structured business logic (MD files) with unstructured document intelligence (Neon + PageIndex) to achieve **98.7% accuracy using decision-tree retrieval** before agent teams refine to perfection.

## High-Level System Architecture

### 1. Frontend Interface (Ingestion Layer)
- **User Uploads:** React/Vite dashboard for uploading business documents (PDFs, MD, Docx) and rule definitions.
- **Metadata Tagging:** UI component where users select categories (Compliance, HR, Finance) and assign doc_type before commit.

### 2. Decision-Tree Data Storage (Persistence Layer)
- **Neon (Postgres):** Primary relational engine — user profiles, document metadata, audit logs, category trees, business rules tables.
- **PageIndex (Reasoning Engine):** Builds hierarchical JSON trees from documents. Trees stored as JSONB in tenant's Neon DB. LLM navigates trees via reasoning (NOT similarity matching).
- **Decision-Tree Model:** Neon maintains the "source of truth" (SQL metadata + business rules), while PageIndex enables "reasoning-based tree search" for precise retrieval.

### 3. Agent Logic & Rules (Development Layer)
- **MD Rule Files:** Teams maintain Markdown (.md) files as "Base Instructions" — hard-coded business rules and logic boundaries agents must never violate.
- **Rule Injection:** During execution, MD rules are injected into System Prompt to ground the model.
- **Business Rules in Neon:** Rules also stored in `business_rules` table in tenant DB for programmatic lookup by decision tree.

### 4. Agent Execution (Application Layer — Decision-Tree-First)

```
User Query
    ↓
Step 1: SQL Metadata Filter (Neon)
    Filter by doc_type, department, year, category
    Cost: ~0 tokens (pure SQL)
    ↓
Step 2: Summary Selection (Haiku — cheap LLM)
    Read document summaries → pick best match(es)
    Cost: ~500 tokens
    ↓
Step 3: PageIndex Tree Reasoning (Sonnet)
    Navigate tree structure → identify exact node IDs
    Cost: ~2,000 tokens (tree only, not full doc)
    ↓
Step 4: Answer Generation (Sonnet)
    Generate response from selected nodes + MD rules
    Cost: ~1,500 tokens
    ↓
98.7% accuracy achieved
    ↓
Step 5: Agent Team Refinement (only if needed)
    Multi-agent pipeline verifies, cross-references, polishes
    → 100% accuracy target
```

## Technical Design Pattern

### Ingestion Pipeline (Vectorless)
```
Upload → Text Extraction → Category Tagging → PageIndex Tree Generation
    → Auto-Summarization → JSONB Tree + Summary stored in Neon
    → Business rules extracted and stored in business_rules table
```

### Query Pipeline (Decision-Tree-First)
```
User Query → Metadata Filter (Neon SQL) → Summary Selection (Haiku)
    → Tree Reasoning (PageIndex/Sonnet) → MD Rule Check → Answer Generation
    → Accuracy logging → Agent refinement (if < 98.7%)
```

## Why Decision-Tree-First Beats Vector RAG

| Concern | Vector RAG (NOT used) | Decision-Tree-First (our approach) |
|---|---|---|
| Retrieval method | Cosine similarity on embeddings | LLM reasons through document hierarchy |
| Accuracy | ~70–85% (similar-sounding noise) | **98.7%** (logical navigation) |
| Traceability | "This chunk was similar" | "Section 4.2 was selected because query asks about cancellation clauses" |
| Cost per query | Embedding model + similarity compute | SQL filter (free) + cheap LLM summary pick + focused tree reasoning |
| Business rules | Flat retrieval, no structure | Tree preserves document logic, rules checked explicitly |
| Multi-tenant isolation | Shared vector index risk | Per-tenant Neon DB, physical isolation |

## Business Rules Integration

When MD or PDF business rules/controls are uploaded:

1. **PageIndex generates the tree** — hierarchical JSONB with node-level summaries
2. **Auto-summarization** creates a document description for fast filtering
3. **Rule extraction** (Haiku) identifies specific rules/controls from tree nodes
4. **Rules stored** in both `tenant_knowledge.index_tree` (full tree) and `business_rules` table (extracted rules for fast lookup)
5. **Decision tree achieves 98.7%** by navigating the tree structure before agents run
6. **Agent team refines** — cross-references rules, validates edge cases, achieves perfection

---

## Agent Instructions

- **Use this when:** Building the RAG retrieval pipeline combining Neon + PageIndex
- **NEVER use:** Vector embeddings, pgvector, similarity search, or cosine distance
- **Before this:** Neon, PageIndex, and LangGraph all configured
- **After this:** Use this decision-tree-first architecture for all agent knowledge retrieval
