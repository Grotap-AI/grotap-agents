---
title: "Expo MCP - Implementing"
source: google-drive-docx
converted: 2026-03-01
component: "Expo-MCP"
category: frontend
doc_type: setup-guide
related:
  - "React"
  - "FastAPI"
  - "WorkOS"
tags:
  - expo
  - mcp
  - mobile
  - native
  - react-native
status: active
---


# Expo MCP - Implementing

Implementing Expo MCP across your specified stack involves connecting AI-assisted clients to the Expo MCP server and integrating secondary MCP servers (like GitHub, GitGuardian, and Terraform) to manage infrastructure and security.
1. Core Expo MCP Implementation
- Claude Code CLI: Add the Expo MCP server by running claude mcp add --transport http expo-mcp https://mcp.expo.dev/mcp. Authenticate using /mcp within your session.
- React & Expo SDK: Ensure your project uses Expo SDK 54+. Enable local MCP capabilities by starting the dev server with EXPO_UNSTABLE_MCP_SERVER=1 npx expo start.
   LangChain.js & LangSmith: Use the @langchain/mcp-adapters package to wrap MCP tools for use with LangChain agents. In LangSmith Studio, navigate to Settings > MCP Servers to add the remote Expo MCP URL for agent discovery.

2. Infrastructure & Backend (FastAPI, Vercel, Neon)
- FastAPI & Vercel: Deploy your FastAPI backend to Vercel. Vercel supports hosting MCP servers as functions, which can then be called by your AI frontend.
   Neon Database: Use the Neon MCP Server to manage Postgres branches and run natural language queries. You can add this alongside Expo MCP to Claude Code using npx @neondatabase/mcp-server-neon.

3. DevOps & Security (GitHub, GitGuardian, Terraform)
- GitHub & Terraform: Install the Terraform MCP Server to allow your AI agent to plan and apply infrastructure changes. GitHub integration allows the agent to fetch repo context or perform PR actions.
   GitGuardian & Doppler: Use the GitGuardian MCP Server for secret scanning within the AI workflow. Manage sensitive environment variables (like API keys for Stripe or WorkOS) via Doppler, ensuring they are injected into your Vercel or Linux Cluster environments.

4. Advanced Orchestration (Inngest, Multi-Tenancy, Event Bus)
- Inngest & Central Event Bus: Use Inngest as your central event bus to handle asynchronous tasks. For multi-tenant context switching, leverage Inngest's concurrency "keys" (e.g., user_id or tenant_slug) to isolate job queues and prevent "noisy neighbor" issues.
   WorkOS: Implement WorkOS for enterprise-grade Auth and SSO. In a multi-tenant MCP setup, use the tenant slug from WorkOS to route requests to isolated MCP server instances or configurations.

5. Specialized Tools
- Cobrowse & Stripe: These are integrated as standard APIs within your React/FastAPI stack. Your AI agent, via Expo MCP, can help write the implementation code for Stripe checkout flows or Cobrowse session initialization by referencing their respective documentation.
- Backblaze B2 & Cloudflare R2: Treat these as S3-compatible storage layers. The AI agent can assist in configuring the S3 clients within your LangChain tools to read/write persistent data for your agents

---

## Agent Instructions

- **Use this when:** Launching mobile apps using Expo MCP
- **Before this:** FastAPI backend and WorkOS auth configured
- **After this:** Mobile app connects to same FastAPI backend as React web app
