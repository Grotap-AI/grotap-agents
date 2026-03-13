---
title: "Work OS - Auth Resource"
source: google-drive-docx
converted: 2026-03-01
component: "WorkOS"
category: auth
doc_type: reference
related:
  - "Neon"
  - "FastAPI"
  - "React"
tags:
  - workos
  - auth
  - enterprise
  - sso
  - reference
status: active
---


# Work OS - Auth Resource

Work OS - Auth Resource

## As a Developer Tool (WorkOS.com )
"WorkOS" (often written as one word) is also the name of a popular API platform for software developers. It provides the infrastructure needed to make a SaaS application "Enterprise Ready".
Important Option to research
AuthKit: A pre-built authentication UI and user management system that is free for the first 1 million monthly active users.
WorkOS: Enterprise-Ready Identity
WorkOS acts as your authentication and user management hub.
- AuthKit Integration: Use the @workos-inc/node or @workos-inc/authkit-nextjs SDKs to add SSO, Magic Links, and MFA.
- Sign in with Vercel: You can now enable Vercel as an OAuth provider directly in the WorkOS Dashboard , allowing users to log in with their Vercel credentials.
- MCP Documentation: For AI-assisted coding (e.g., Cursor, Claude), install the WorkOS MCP Server  to let your agent query the latest WorkOS docs directly.
2. Infrastructure: Vercel, Railway, and Neon
- Frontend (Vercel): Connect your GitHub repo to Vercel  for automated deployments.
- Backend & Workers (Railway): Use Railway  to host long-running services and background workers. Link your Railway project to Vercel via the Railway for Vercel Integration  to share environment variables like DATABASE_URL.
- Database (Neon): Neon is a serverless Postgres DB.
     Vercel Integration: Use the Neon Vercel Integration  to automatically create database branches for every Vercel preview deployment.
     Direct Connection: In Railway, add your Neon connection string as a DATABASE_URL variable in the Variables tab.
3. Management & Utilities
- Secrets (Doppler): Stop using .env files.
     1. --------------------------------------------------------------------------------
     Centralize secrets in Doppler .
     2. --------------------------------------------------------------------------------
     Set up Syncs for Vercel and Railway.
     3. --------------------------------------------------------------------------------
     When you update a secret in Doppler, it automatically triggers a redeploy or update in both Vercel and Railway.
- Payments (Stripe): Use the Stripe MCP Server  to allow AI agents to manage customers, subscriptions, or products via natural language commands.
- Mobile (Expo MCP): If building a mobile app, the Expo MCP Server  enables AI-driven UI modifications and interaction testing.
- Support (Cobrowse): Integrate the Cobrowse.io SDK into your frontend to provide real-time remote support and "see what the user sees" within your Vercel-hosted app.
- Background Jobs (Inngest): Use Inngest for durable async workflows and task queues between your Vercel frontend and Railway workers. Configure INNGEST_SIGNING_KEY and INNGEST_EVENT_KEY in Doppler.
Implementation Checklist
  1. --------------------------------------------------------------------------------
- Identity: Set up WorkOS AuthKit and link Vercel OAuth.
  2. --------------------------------------------------------------------------------
- Storage: Connect Neon to Vercel for automatic DB branching.
  3. --------------------------------------------------------------------------------
- Secrets: Install Doppler CLI and sync to both Vercel and Railway.
  4. --------------------------------------------------------------------------------
- Payments: Configure Stripe API keys in Doppler and test with the Stripe MCP.
  5. --------------------------------------------------------------------------------
- Compute: Configure Inngest for background jobs and async workflows on Railway

- Main Features for Developers:
     Enterprise SSO: A single integration that supports multiple identity providers like Okta, Azure AD, and Google Workspace.
     Directory Sync: Automatically handles user provisioning and deprovisioning via SCIM.
     AuthKit: A pre-built authentication UI and user management system that is free for the first 1 million monthly active users.
      Audit Logs: Provides the activity trails that enterprise customers require for compliance.

      WorkOS  --  Your app, Enterprise

---

## Agent Instructions

- **Use this when:** Understanding WorkOS auth capabilities and configuration
- **Before this:** None — read this before starting auth implementation
- **After this:** Follow setup steps in Work OS - Setup Steps for Resources
