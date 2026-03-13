---
title: "Cloudfare R2 and Neon Integration for AI Vectors and Document Storage"
source: google-drive-docx
converted: 2026-03-01
component: "Cloudflare-R2"
category: storage
doc_type: how-to
related:
  - "Neon"
  - "PageIndex"
  - "INNGEST"
tags:
  - cloudflare
  - r2
  - storage
  - neon
  - vectors
  - documents
  - integration
status: active
---


# Cloudfare R2 and Neon Integration for AI Vectors and Document Storage

Cloudfare R2 and Neon Integration for AI Vectors and Document Storage

To build an agentic document processing pipeline with Cloudflare R2 and Neon, you use a "Metadata-First" architecture. You store the raw binary files in R2 (unstructured) and the searchable "knowledge" (vector embeddings) in Neon.

1. High-Level Tech Stack
This stack is optimized for low latency and zero egress fees between storage and compute.

- Storage (The Archive): Cloudflare R2 stores raw PDFs, images, and logs.
- Database (The Brain): Neon PostgreSQL  with the pgvector extension stores text chunks and their embeddings.
- Orchestration: LangChain.js handles document loading, chunking, and querying. PageIndex is the retrieval layer — LlamaIndex is NOT used in this platform.
- Processing (The Worker): Cloudflare Workers  (serverless) can trigger indexing as soon as a file hits R2.

---

## Agent Instructions

- **Use this when:** Using Cloudflare R2 as the upload landing zone before Neon/PageIndex ingestion
- **Before this:** Cloudflare R2 bucket created, Neon and PageIndex ready
- **After this:** INNGEST job triggered on upload to ingest into PageIndex
