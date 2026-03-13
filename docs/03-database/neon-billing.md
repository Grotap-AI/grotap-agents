---
title: "Neon Per-Tenant Billing & Consumption"
component: "Neon"
category: database
doc_type: reference
related: ["Stripe", "FastAPI", "INNGEST"]
tags: [neon, billing, consumption, multitenant, metering]
status: active
---

# Neon Per-Tenant Billing & Consumption

## 1. Provision a Tenant Project (Create Project API)

```bash
curl 'https://console.neon.tech/api/v2/projects' \
  -H "Authorization: Bearer $NEON_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"project": {"name": "tenant-acme-corp", "pg_version": 17, "region_id": "aws-us-east-1"}}'
```

**Node.js SDK:**
```javascript
import { createApiClient } from '@neondatabase/api-client';
const apiClient = createApiClient({ apiKey: process.env.NEON_API_KEY });

async function provisionTenant(tenantName) {
  const res = await apiClient.createProject({
    project: { name: tenantName, pg_version: 17, region_id: 'aws-us-east-1' }
  });
  return {
    projectId: res.data.project.id,
    connectionUri: res.data.connection_uris[0].connection_uri
  };
}
```

**Important:** Save `projectId` → your catalog DB `tenants` table immediately. Required for all consumption queries.

---

## 2. Catalog Table (Control Plane DB)
```sql
CREATE TABLE tenants (
  tenant_id   TEXT PRIMARY KEY,
  neon_project_id TEXT,   -- e.g. 'bold-flower-99'
  billing_tier TEXT,      -- 'Gold' | 'Silver' | 'Free'
  status      TEXT DEFAULT 'active'
);
```

---

## 3. Fetch Consumption Metrics

**API (cURL):**
```bash
curl 'https://console.neon.tech/api/v2/consumption_history/projects?org_id=ORG&from=2024-01-01T00:00:00Z&to=2024-02-01T00:00:00Z&granularity=monthly' \
  -H "Authorization: Bearer $NEON_API_KEY"
```

**Response:**
```json
{
  "projects": [{
    "project_id": "tenant-project-abc-123",
    "consumption": [{
      "period_start": "2024-01-01T00:00:00Z",
      "metrics": { "compute_hours": 145.2, "data_storage_bytes_hour": 1073741824 }
    }]
  }]
}
```

**Node.js sync:**
```javascript
async function syncTenantBilling(orgId, apiKey, tenantMap) {
  const res = await fetch(
    `https://console.neon.tech/api/v2/consumption_history/projects?org_id=${orgId}&granularity=monthly`,
    { headers: { Authorization: `Bearer ${apiKey}` } }
  );
  const { projects } = await res.json();
  for (const project of projects) {
    const tenantId = tenantMap[project.project_id];
    if (tenantId) {
      const cu = project.consumption[0].metrics.compute_hours;
      // Update billing_records table for this tenant
    }
  }
}
```

---

## Key Notes
- **Billing unit:** CU-hours (1 CU ≈ 4 GB RAM running for 1 hour)
- **Granularity:** `monthly` | `daily` | `hourly`
- **Update frequency:** ~15 min — don't poll more often
- **Pagination:** Cursor-based — handle `pagination.cursor` for large tenant counts

---
**Before this:** Neon account + API key in Doppler, Stripe configured
**After this:** Feed `compute_hours` into Stripe for invoice generation via INNGEST
