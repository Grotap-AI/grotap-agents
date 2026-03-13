---
title: "Neon PageIndex Inngest background Jobs"
source: google-drive-docx
converted: 2026-03-01
component: "INNGEST"
category: backend
doc_type: how-to
related:
  - "Neon"
  - "PageIndex"
tags:
  - inngest
  - pageindex
  - neon
  - background-jobs
  - async
  - ingestion
status: active
---


# Neon PageIndex Inngest background Jobs

--------------------------------------------------------------------------------
- In a multitenant ERP, real-time status updates are critical for long-running AI tasks like PageIndex tree generation. Because you are using a database-per-tenant Neon model, your status updates must also be tenant-aware.
  1. Inngest Realtime (Recommended)
If you use Inngest  for your background jobs, you can use its native publish method to stream updates directly from your function to your frontend without managing your own WebSocket server.

- Worker Side (Inngest Function):
  javascript
  export const ingestDocument = inngest.createFunction(
    { id: "ingest-document" },
    { event: "erp/document.uploaded" },
    async ({ event, step, realtime }) => {
      // 1. Initial status
      await realtime.publish({
        channel: `tenant-${event.data.tenantId}`,
        topic: "upload-progress",
        data: { status: "Generating Tree...", progress: 25 }
      });

      const tree = await step.run("pageindex-tree", async () => {
        return await pi.getTree(event.data.docId);
      });

      // 2. Mid-point status
      await realtime.publish({
        channel: `tenant-${event.data.tenantId}`,
        topic: "upload-progress",
        data: { status: "Saving to Neon...", progress: 75 }
      });

      // ... Save to Neon ...
    }
  );

- Use code with caution.
  2. Neon "Outbox" Pattern (Database-Driven)
For a purely database-driven approach, you can create an outbox table in each tenant's Neon database. When the background worker updates a status row, a PostgreSQL trigger  uses pg_notify to signal a small listener service, which then pushes the update to the user.

## Neon
- Summary of Benefits
- User Feedback: Users see exactly where their document is in the pipeline (e.g., "Summarizing Page 40 of 100").
- Security: By using tenant-specific channels (Inngest) or Socket.io rooms, you ensure that a user from Tenant A never sees the ingestion progress of Tenant B.
- Resilience: If the connection drops, the frontend can simply re-subscribe to the channel and receive the latest state from the job

---

## Agent Instructions

- **Use this when:** Running background document ingestion jobs via INNGEST
- **Before this:** INNGEST, Neon, and PageIndex all configured
- **After this:** Documents are ingested and indexed automatically on upload
