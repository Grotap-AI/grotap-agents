---
title: "Neon Inngest Teir-based Prioritization"
source: google-drive-docx
converted: 2026-03-01
component: "INNGEST"
category: backend
doc_type: how-to
related:
  - "Neon"
  - "Stripe"
tags:
  - inngest
  - neon
  - tiers
  - prioritization
  - workflow
status: active
---


# Neon Inngest Teir-based Prioritization

To implement Tier-based Prioritization in your ERP, you use Inngest's Priority feature. Inngest allows you to use a single function that dynamically adjusts its urgency based on the tenant's metadata — no separate physical queues or additional infrastructure required.
1. Dynamic Priority Configuration
You can define a priority block that looks at the tenantTier inside your event data. Inngest uses a numeric scale (typically -600 to 600) where higher numbers jump to the front of the backlog.
javascript
export const ingestDocument = inngest.createFunction(
  {
    id: "ingest-document",
    // 1. Prioritize 'Gold' tenants so they jump the queue
    priority: {
      run: "event.data.tenantTier === 'Gold' ? 100 : 0",
    },
    // 2. Combine with concurrency to ensure 'Gold' tenants
    // don't just jump the queue but also get dedicated slots
    concurrency: {
      limit: 5,
      key: "event.data.tenantId",
    }
  },
  { event: "erp/document.uploaded" },
  async ({ event, step }) => {
    const sql = neon(event.data.tenantDbUrl);
    // ... PageIndex & Neon Logic ...
  }
);

Use code with caution.
Source: Inngest Priority Documentation
2. How This Optimizes Your ERP
- Zero Infrastructure Overhead: You don't need to manage "Gold-Queue" vs "Free-Queue" workers. Inngest handles the Virtual Queueing  internally.
- Neon Efficiency: Since Gold Tier tenants likely pay more for higher Neon Compute Limits , prioritizing their AI indexing ensures they see the "instant" experience they pay for.
- PageIndex Rate Limiting: If you are nearing your PageIndex or LLM rate limits, the system will naturally process your "Gold" documents first and let "Free" tier documents wait until the rate-limit window resets.
Pro-Tip: If a "Free" tier document is stuck in the queue for too long, you can use Inngest's step.waitForEvent to send a Real-time Status Update to the UI saying "Heavy traffic: Your document is #4 in line."

---

## Agent Instructions

- **Use this when:** Implementing tier-based job prioritisation with INNGEST and Neon
- **Before this:** INNGEST configured, Neon per-tenant databases ready
- **After this:** Higher-tier tenants get priority background job execution
