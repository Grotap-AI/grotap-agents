---
title: "Neon PageIndex Asyncronous Job Queue"
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
  - async
  - queue
  - jobs
  - ingestion
status: active
---


# Neon PageIndex Asyncronous Job Queue

In a multitenant ERP with a database-per-tenant Neon model, use Inngest as the asynchronous job queue to handle resource-heavy PageIndex ingestion.

This prevents your UI from freezing during the multi-step process of file uploading, tree generation, and database insertion.

## Microsoft
The Background Worker Architecture
  1. --------------------------------------------------------------------------------
- Job Enqueueing: When a user uploads a document, the ERP API saves the raw file to object storage (like S3) and enqueues a job containing the tenant_db_url, file_url, and document_name.
  2. --------------------------------------------------------------------------------
- Isolated Processing: The background worker picks up the job, initializes the PageIndex SDK , and generates the hierarchical tree and document summary.
  3. --------------------------------------------------------------------------------
   Tenant-Specific Storage: The worker uses the provided tenant_db_url to connect directly to that tenant's isolated Neon database and insert the resulting JSONB tree.
  4. --------------------------------------------------------------------------------

  5. --------------------------------------------------------------------------------

  6. --------------------------------------------------------------------------------

## Example Worker Implementation (Node.js + Inngest)
This worker ensures that each document is processed and stored in its respective tenant's database without blocking the main application.
javascript
import { inngest } from '../inngest';
import { PageIndex } from 'pageindex';
import { neon } from '@neondatabase/serverless';

const pi = new PageIndex({ apiKey: process.env.PAGEINDEX_API_KEY });

export const ingestDocument = inngest.createFunction(
  { id: 'ingest-document', retries: 3 },
  { event: 'erp/document.uploaded' },
  async ({ event, step }) => {
    const { tenantDbUrl, fileUrl, docName } = event.data;

    // 1. Generate the PageIndex tree (Reasoning-based RAG preparation)
    const tree = await step.run('pageindex-tree', async () => {
      const uploadRes = await pi.upload(fileUrl);
      const treeRes = await pi.getTree(uploadRes.doc_id, { node_summary: true });
      const docDescription = await pi.generateDocDescription(treeRes.result);
      return { treeRes, docDescription };
    });

    // 2. Connect to the isolated Neon Tenant DB and persist
    await step.run('save-to-neon', async () => {
      const sql = neon(tenantDbUrl);
      await sql`
        INSERT INTO tenant_knowledge (document_name, index_tree, summary)
        VALUES (${docName}, ${JSON.stringify(tree.treeRes.result)}, ${tree.docDescription})
      `;
    });

    return { status: 'completed', docName };
  }
);

Use code with caution.
Strategic Advantages
- Scalability: Because Neon autoscales compute per tenant , the background worker only consumes the resources needed for that specific tenant's database during the write operation.
- Reliability: Long-running PageIndex processes (especially for massive PDFs) won't time out your HTTP request.
- Security: By passing the tenant_db_url directly to the worker, you maintain strict physical isolation; the worker never needs access to a "master" database containing all tenants' data

---

## Agent Instructions

- **Use this when:** Building async job queues for document ingestion
- **Before this:** INNGEST and PageIndex configured
- **After this:** Background ingestion jobs run automatically on upload
