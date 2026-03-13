---
title: "Multi-tenant Switching"
source: google-drive-docx
converted: 2026-03-01
component: "Architecture"
category: architecture
doc_type: how-to
related:
  - "WorkOS"
  - "Neon"
  - "FastAPI"
tags:
  - multitenant
  - context-switching
  - architecture
  - workos
  - neon
status: active
---


# Multi-tenant Switching

To implement multi-tenant context switching across your stack -- from React and WorkOS to an Inngest central event bus and FastAPI -- you must establish a consistent "tenant context" that travels with every request and event.
1. Multi-Tenant Context Switching (Core Implementation)
- Authentication & Organization Switching: Use the WorkOS Organization Switcher  in your React frontend to allow users to toggle between tenants. When a user switches, WorkOS retrieves a fresh token with the new organization_id.
- Context Propagation:
     Frontend to Backend: Send the organization_id (extracted from the JWT) in the header of every FastAPI request.
     Backend to Event Bus: When dispatching events to Inngest, include the organization_id in the event payload (e.g., event.data.tenant_id).
   Database Isolation (Neon): Use the tenant ID to scope all Neon SQL queries. In a shared schema, every table should include a tenant_id column to ensure data isolation.

   WorkOS  --  Your app, Enterprise

2. Agent Management & Source Code (GitHub + LangChain)
- Source Control: Store your agent logic and LangChain.js  code in GitHub.
- Agent Deployment: Use the LangSmith Deployment  UI to connect your GitHub repository and specify the agent path. This provides a "Studio" environment for real-time debugging and visualizing agent traces.
   Multi-Tenant Agents: Transform your Inngest AgentKit  network into an Inngest function that accepts tenant-specific inputs, allowing you to run the same agent logic scoped to different customer data.

   AgentKit by

3. Infrastructure & Secret Management
- Infrastructure as Code: Use the Terraform MCP Server to manage your Linux Clusters and cloud resources (Vercel, Neon) programmatically.
- Secrets (Doppler): Use Doppler to manage environment variables (like INNGEST_EVENT_KEY or STRIPE_SECRET_KEY) across different environments (staging/production) and tenants.
   Storage (Backblaze B2 / Cloudflare R2): Use these for cost-effective object storage, ensuring each tenant's files are stored in folders prefixed by their organization_id for isolation.

4. Integration Summary Table
Component
Role in Multi-Tenancy
WorkOS
Manages organization_id and SSO/MFA per tenant.
Inngest
Acts as the Central Event Bus, routing tenant-specific background tasks.
Vercel
Hosts the React frontend and FastAPI (as Serverless Functions), handling routing.
Neon
Serverless Postgres for isolated tenant data storage.
GitGuardian
Scans your GitHub repo and MCP Servers for leaked secrets or misconfigurations.

---

## Agent Instructions

- **Use this when:** Implementing multi-tenant context switching
- **Before this:** WorkOS auth and Neon per-tenant databases configured
- **After this:** All API requests automatically route to correct tenant database
