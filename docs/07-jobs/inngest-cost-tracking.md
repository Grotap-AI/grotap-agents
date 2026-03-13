---
title: "Neon Inngest Tracking Client Costs Middleware to track granular usage data"
source: google-drive-docx
converted: 2026-03-01
component: "INNGEST"
category: backend
doc_type: how-to
related:
  - "Neon"
  - "Stripe"
  - "FastAPI"
tags:
  - inngest
  - neon
  - billing
  - costs
  - middleware
  - tracking
  - usage
status: active
---


# Neon Inngest Tracking Client Costs Middleware to track granular usage data

In a multitenant ERP, you can use Inngest Middleware  to intercept every function execution and log granular usage data (like AI tokens or database compute units) to a central billing table. This ensures that even in a database-per-tenant Neon model, you have a unified view of costs.
1. Inngest Middleware for Billing
Middleware allows you to run code during the function lifecycle , such as onFunctionRun. You can use this to capture the tenant_id from the event and record the resources used by PageIndex or Neon.
javascript
const billingMiddleware = new InngestMiddleware({
  name: "Usage Billing",
  init: () => ({
    onFunctionRun: ({ fn, runId, event }) => ({
      // This runs after the function finishes (success or failure)
      transformOutput: async ({ result, error }) => {
        const tenantId = event.data.tenantId;

        // Log AI usage (e.g., from PageIndex or step.ai.infer metadata)
        // You can capture tokens, execution time, or custom metrics
        await logUsageToBillingDB({
          tenantId,
          runId,
          functionId: fn.id,
          tokens: result?.usage?.total_tokens || 0,
          status: error ? "failed" : "success"
        });
      },
    }),
  }),
});

export const inngest = new Inngest({ id: "erp-app", middleware: [billingMiddleware] });

Use code with caution.
Sources: Inngest Middleware Lifecycle, AI Inference Observability
2. Tracking Neon & PageIndex Usage
To bill accurately, you need to pull data from two different sources:
- AI Compute (PageIndex/LLM): If you use step.ai.infer(), Inngest automatically captures metadata like token counts and model names in AI Traces . You can access this metadata in your middleware to bill per 1,000 tokens.
- Neon Database Usage: Use the Neon Consumption API  to poll for per-project metrics (compute hours, storage, and data transfer). Since you have a database-per-tenant, each tenant's Neon project_id maps directly to their specific bill.
3. Integrated Billing Architecture
Resource
Tracking Method
Billing Metric
PageIndex AI
Inngest AI Traces
Tokens (Input/Output) or Page Count.
Neon Database
Neon Consumption API
Compute Unit (CU) hours & Storage.
Background Jobs
Inngest Middleware
Execution time or "Job Units."
4. Implementation Tip: The "Usage Buffer"
Instead of writing to your billing database for every small step, use the middleware to push usage events back into an Inngest Batching Queue. This aggregates a tenant's usage over 1 hour and performs a single bulk write to your central Neon "Catalog" database, reducing write IOPS and costs .
Would you like to see the Neon API call for fetching a specific tenant's monthly Compute Unit (CU) usage?

---

## Agent Instructions

- **Use this when:** Tracking granular per-tenant usage costs via INNGEST middleware
- **Before this:** INNGEST and FastAPI middleware configured
- **After this:** Feed usage data into Stripe for per-tenant billing
