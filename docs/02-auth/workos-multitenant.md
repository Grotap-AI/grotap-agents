---
title: "Work Os - implement multi-tenant context switching"
source: google-drive-docx
converted: 2026-03-01
component: "WorkOS"
category: auth
doc_type: how-to
related:
  - "Neon"
  - "FastAPI"
  - "React"
tags:
  - workos
  - multitenant
  - context-switching
  - auth
status: active
---


# Work Os - implement multi-tenant context switching

implement multi-tenant context switching
To implement multi-tenant context switching across your stack, you must synchronize the Organization ID from WorkOS through your React frontend and FastAPI backend down to your Neon database and asynchronous workers.
1. Frontend: React + WorkOS
Use the WorkOS AuthKit React SDK  to manage organization state and provide the switcher UI.

- Organization Switcher: Integrate the <OrganizationSwitcher /> widget from @workos-inc/widgets. It handles the UI and logic for switching between organizations a user belongs to.
- Context Management: Use the useAuth hook to access the switchToOrganization function and the current organizationId.
   API Interceptor: Configure your API client (e.g., Axios) to include the current organizationId in every request header (e.g., X-Organization-ID).

   WorkOS  --  Your app, Enterprise

2. Backend: FastAPI Middleware
Create a dependency or middleware in FastAPI to extract the tenant context and enforce isolation.

- Tenant Extraction: Use a FastAPI dependency  to pull the organizationId from the request header or JWT.
- Context Var: Store this ID in a contextvars.ContextVar to ensure it is available throughout the request lifecycle, even in deep service layers, without manual prop drilling.
   Global Filter: Apply a global filter to your SQLModel/SQLAlchemy queries: query.filter(Table.organization_id == current_org_id).

3. Database: Neon + Multi-Tenancy
Neon's architecture  supports several isolation strategies:

- Shared Database (Recommended): Use a single Neon database with an organization_id column on every tenant-owned table. This is cost-effective and easiest for cross-tenant analytics.
- Schema Isolation: For stricter isolation, use a "One Schema per Tenant" approach. Your FastAPI middleware must run SET search_path TO tenant_id at the start of each request.
   Branching for Dev/Test: Use Neon's branching  to create ephemeral copies of your production schema (with anonymized data) for testing tenant-specific migrations.

4. Event Bus & Orchestration: INNGEST
For asynchronous tasks, ensure the tenant context is preserved in the Central Event Bus .
- Event Payload: Every event sent to INNGEST must include the organizationId.
- Tenant-Aware Functions: When INNGEST triggers a background function, use the organizationId from the event payload to re-establish the database context and file storage paths (R2/B2).
5. Infrastructure & Secrets: Doppler + Terraform
- Doppler: Centralize environment variables for your various MCP servers (GitGuardian, Expo, Terraform). Use Doppler's Configs to manage tenant-specific overrides if needed (e.g., different API keys for specific organizations).
- Terraform MCP: Automate the provisioning of Neon branches or Cloudflare R2 buckets for new tenants as they sign up via WorkOS webhooks.
6. Storage: Cloudflare R2 / Backblaze B2
- Path Isolation: Prefix all storage keys with the organization ID: s3://bucket-name/{organization_id}/uploads/{file_id}.
- Signed URLs: Generate tenant-specific signed URLs to ensure users can only access files belonging to their active organization

---

## Agent Instructions

- **Use this when:** Implementing multi-tenant context switching using WorkOS
- **Before this:** WorkOS auth configured, Neon database-per-tenant set up
- **After this:** Test tenant isolation with RLS in FastAPI
