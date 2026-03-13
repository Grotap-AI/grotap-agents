---
title: "Work OS - Setup Steps for Resources"
source: google-drive-docx
converted: 2026-03-01
component: "WorkOS"
category: auth
doc_type: setup-guide
related:
  - "Neon"
  - "FastAPI"
  - "React"
  - "Doppler"
tags:
  - workos
  - auth
  - setup
  - enterprise
  - sso
status: active
---


# Work OS - Setup Steps for Resources

Work OS - Setup Steps for Resources

This implementation guide provides step-by-step checklists to integrate your stack, moving from identity to infrastructure and ending with asynchronous processing.
1. Identity: WorkOS & Vercel OAuth
Connect Enterprise SSO and enable your team to log in using their Vercel credentials.
- Create Vercel OAuth App: In Vercel Team Settings, create a new application and save the Client ID and Client Secret.
- Configure WorkOS: In the WorkOS Dashboard , enable AuthKit and add Vercel as a configured Identity Provider using the credentials from the previous step.
- Set Redirect URIs: Add your application's callback URL (e.g., http://localhost:3000/api/auth/callback) to the Redirects section in WorkOS.
- Install SDK: Run npm install @workos-inc/authkit-nextjs (or the equivalent for your framework) to handle the authentication flow.
2. Storage: Neon & Vercel Branching
Automate database environment management so every pull request gets its own isolated database.
- Install Integration: Use the Neon Vercel Integration  from the Vercel Marketplace to link your projects.
- Enable Branching: In the integration settings, toggle "Create a database branch for deployment" for the Preview environment.
- Verify Local Sync: Use vercel env pull to bring the dynamic DATABASE_URL into your local development environment.
- Set Cleanup Rules: Enable "Automatically delete obsolete Neon branches" to remove databases when GitHub PRs are merged or closed.
3. Secrets: Doppler CLI Sync
Centralize your environment variables to ensure Vercel and Railway stay in sync.
- Install Doppler CLI: Install the CLI locally and run doppler login to authenticate your machine.
- Authorize Integrations:
     In Doppler , navigate to Integrations and authorize Vercel.
     Repeat the process for Railway using a Railway API Token .
- Map Configs: Link specific Doppler project "configs" (e.g., Root/Production) to the corresponding environments in Vercel and Railway.
- Test Sync: Change a value in Doppler and verify it updates in the Vercel Dashboard and Railway Variables tab.
4. Payments: Stripe & MCP
Set up secure payment processing and test it using AI-powered tools.
- Generate Restricted Keys: Create a Restricted API Key in the Stripe Dashboard  with limited permissions for better security.
- Store in Doppler: Add your STRIPE_SECRET_KEY and STRIPE_PUBLISHABLE_KEY to your Doppler project.
- Setup Stripe MCP: Install the Stripe MCP Server  and provide it with your Stripe API key as a bearer token.
- Verify with AI: Use an MCP-compatible client (like Cursor) to "list recent customers" or "create a test product" to confirm the agent has API access.
5. Compute: Inngest for Background Jobs
Background jobs and async workflows are handled by Inngest — no separate message broker required.
- Deploy Inngest: Add your INNGEST_SIGNING_KEY and INNGEST_EVENT_KEY to Doppler and configure the Inngest SDK in your backend service.
- Define Functions: Write durable Inngest functions for heavy tasks (document ingestion, AI processing, tier-based workflows).
- Railway Integration: Inngest workers run as part of the existing Railway backend service — no additional infrastructure needed.
- Observability: Use the Inngest dashboard to monitor job status, retries, and execution history.

---

## Agent Instructions

- **Use this when:** Configuring WorkOS for enterprise auth
- **Before this:** Doppler secrets configured for WorkOS API keys
- **After this:** Integrate WorkOS token extraction into FastAPI middleware
