---
title: "Neon PageIndex Multi-document Tree Storage"
source: google-drive-docx
converted: 2026-03-01
component: "Neon"
category: database
doc_type: architecture
related:
  - "PageIndex"
  - "INNGEST"
tags:
  - neon
  - pageindex
  - tree
  - storage
  - multi-document
  - structure
status: active
---


# Neon PageIndex Multi-document Tree Storage

In a multi-document ERP environment, you combine Neon's physical isolation (database-per-tenant) with PageIndex's hierarchical reasoning (tree-per-document) to maintain security and searchability.
Reference Architecture: Multi-Document Tree Storage
In this model, your application acts as the router. It identifies the correct tenant's Neon database and then selects the relevant document trees for PageIndex to process.
Component
Responsibility
Tenant Router
Application logic that selects the Neon Project Connection URL  based on the tenant_id.
Neon (Tenant DB)
Stores relational ERP data alongside a tenant_knowledge table containing JSONB PageIndex trees .
PageIndex Engine
Performs reasoning-based navigation  across the selected document trees.
LLM Orchestrator
Decides which documents to "open" based on metadata or high-level summaries.
SQL Metadata Filtering Example
To search across thousands of documents efficiently within a single tenant, use PostgreSQL's containment operator ( @> )  to filter by specific metadata before passing trees to the AI.
sql
-- Search for all 2024 'Legal' documents in the tenant's isolated database
SELECT document_name, index_tree
FROM tenant_knowledge
WHERE metadata @> '{"year": 2024, "category": "Legal"}'::jsonb;

Use code with caution.
Multi-Document Search Workflow
PageIndex recommends three primary multi-document search patterns :
  1. --------------------------------------------------------------------------------
- Search by Metadata: Best for structured ERP data (e.g., filtering by client_id or invoice_date). You use standard SQL GIN indexes  on your metadata column for sub-millisecond retrieval.
  2. --------------------------------------------------------------------------------
- Search by Description: A "lightweight" approach where you store a brief text summary of each document in a Neon column. The LLM reads these summaries first to decide which full document trees are relevant to the query.
  3. --------------------------------------------------------------------------------
- Search by Semantics (Hybrid): If a tenant has a massive volume of documents, you can use pgvector on Neon  to perform a broad similarity search on document summaries, narrowing the field to 3 - 5 candidates before initiating PageIndex tree reasoning for the final answer.
Pro-Tip for Neon: Since you are using a database-per-tenant model, you can create partial indexes on specific JSON keys (like doc_type) to further optimize search performance for high-traffic tenants without affecting the storage of others.

---

## Agent Instructions

- **Use this when:** Storing multi-document tree structures in Neon
- **Before this:** PageIndex ingestion pipeline set up
- **After this:** Trees are queryable by LangGraph agents
