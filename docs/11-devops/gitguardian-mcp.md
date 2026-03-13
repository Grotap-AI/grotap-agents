---
title: "GitGuardian MCP - AI Agents secret manager"
source: google-drive-docx
converted: 2026-03-01
component: "GitGuardian-MCP"
category: devops
doc_type: setup-guide
related:
  - "Doppler"
  - "GitHub"
  - "Claude-Code"
tags:
  - gitguardian
  - mcp
  - secrets
  - security
  - agents
  - scanning
status: active
---


# GitGuardian MCP - AI Agents secret manager

Implementing the GitGuardian MCP (Model Context Protocol) Server as your AI agent's secret manager requires a multi-layered architecture to bridge secret scanning, multi-tenant orchestration, and modern web deployment.
1. Core Integration: Claude Code & LangChain
- Claude Code (CLI): Connect by adding the GitGuardian MCP server to your configuration using npx -y @gitguardian/ggmcp@latest. Use the /mcp command within the CLI to manage and verify the connection.
   LangChain.js & LangSmith: Use the @langchain/mcp-adapters package to load GitGuardian tools into your LangChain agents. Enable LangSmith  to trace tool calls and monitor secret-scanning performance.

2. Multi-Tenant Orchestration & Secrets
- Multi-tenant Context Switching: Leverage WorkOS for user authentication and organization-level context. Pass the tenant ID through your FastAPI middleware to dynamically select the correct Doppler project or GitGuardian workspace.
   Secret Strategy: Use Doppler as your primary "source of truth" for application secrets, while the GitGuardian MCP Server acts as the runtime "security guard" that prevents agents from leaking or hardcoding those secrets during generation.

   WorkOS  --  Your app, Enterprise

3. Backend & Event Architecture
- FastAPI & Vercel: Host your main agent logic on Vercel  as a FastAPI application. Use the Vercel MCP adapter  to provide live infrastructure context to your agents.
   Event Bus (Inngest): Implement Inngest as your central event bus to handle asynchronous tasks like scanning newly pushed code via GitHub webhooks or processing large file uploads to Backblaze B2 or Cloudflare R2.

4. Infrastructure & Data
- Linux Clusters: For heavy "Agentics" workloads, deploy worker nodes on Linux clusters that interface with the Terraform MCP Server to provision resources on-demand.
- Database & Search: Use Neon (Postgres) for structured tenant data and PageIndex for high-speed indexing and retrieval of agent-generated content.
5. Specialized Capabilities
- Cobrowse & Stripe: Integrate Cobrowse tools for agents to assist users in real-time and Stripe for handling multi-tenant subscription tiers.
- Expo MCP: For mobile workflows, use the Expo MCP to allow agents to interact with React Native project structures and deployment pipelines.

---

## Agent Instructions

- **Use this when:** Setting up GitGuardian MCP to scan agent-generated code for secrets
- **Before this:** GitHub repo connected, Doppler secrets manager configured
- **After this:** GitGuardian scans every agent commit automatically
