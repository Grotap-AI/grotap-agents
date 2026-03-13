---
title: "Neon Inngest per-tenant throttling"
source: google-drive-docx
converted: 2026-03-01
component: "INNGEST"
category: backend
doc_type: how-to
related:
  - "Neon"
  - "FastAPI"
tags:
  - inngest
  - neon
  - throttling
  - multitenant
  - rate-limiting
status: active
---


# Neon Inngest per-tenant throttling

Inngest handles per-tenant throttling through a feature called Concurrency. In a Neon database-per-tenant model, this is critical because it prevents a single client from hitting their Neon autoscaling limits or exhausting your AI API rate limits.
Implementation: Throttling by Tenant Key
You can define a concurrency block inside your Inngest function that uses the tenant_id as a dynamic key. This limits how many parallel jobs can run for that specific tenant across your entire worker cluster.
javascript
export const ingestDocument = inngest.createFunction(
  {
    id: "ingest-document",
    // 1. Define the throttling strategy
    concurrency: {
      limit: 2,           // Only 2 documents processing at once per tenant
      key: "event.data.tenantId", // Scope the limit to the individual tenant
    }
  },
  { event: "erp/document.uploaded" },
  async ({ event, step }) => {
    // 2. This code only runs if the tenant has < 2 active jobs
    const tree = await step.run("pageindex-gen", async () => {
      return await pi.getTree(event.data.docId);
    });

    await step.run("save-to-neon", async () => {
      const sql = neon(event.data.tenantDbUrl);
      return await sql`INSERT INTO knowledge ...`;
    });
  }
);

Use code with caution.
Sources: Inngest Concurrency Documentation, Fixing Multi-tenant Queueing - Inngest
How This Protects Your Neon/PageIndex Stack
- Preventing Neon "Cold Starts" Overload: If a tenant uploads 100 files at once, Inngest will queue them. Without this, 100 parallel connections could hit a Neon compute instance  that is just waking up, causing connection timeouts.
- Fair-Share Scheduling: If Tenant A is processing 100 documents and Tenant B uploads 1, Tenant B's job will start immediately (because their specific "key" has 0 active jobs), while Tenant A's jobs are throttled. Inngest handles this Virtual Queue behavior automatically with no extra infrastructure.
- Rate Limit Protection: PageIndex and LLM providers have strict RPM (Requests Per Minute)  limits. You can set a global concurrency limit alongside your tenant limit to ensure you never get banned by your AI providers.
Advanced: Multi-Level Throttling
You can even combine limits. For example: "Limit the whole system to 50 active AI jobs, but ensure no single tenant takes more than 5 of those slots."
javascript
concurrency: [
  { limit: 50 },                     // Global system safety
  { limit: 5, key: "event.data.tenantId" } // Per-tenant fairness
]

Use code with caution.
Pro-Tip: Since Neon charges based on Compute Unit (CU) usage, throttling heavy AI writes helps keep your infrastructure costs predictable per tenant.

---

## Agent Instructions

- **Use this when:** Implementing per-tenant throttling in INNGEST workflows
- **Before this:** INNGEST and Neon per-tenant setup complete
- **After this:** Prevents any single tenant from monopolising background jobs
