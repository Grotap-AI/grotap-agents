---
title: "Deployment Guide 1"
source: google-drive-docx
converted: 2026-03-01
component: "Deployment"
category: devops
doc_type: setup-guide
related:
  - "Vercel"
  - "FastAPI"
  - "Neon"
  - "WorkOS"
  - "Doppler"
tags:
  - deployment
  - guide
  - step-1
  - vercel
  - fastapi
  - neon
status: active
---


# Deployment Guide 1

Deployment Guide 1

To deploy this ERP platform with integrated native apps, follow a tiered architecture that separates the frontend (Vercel), serverless backend (FastAPI/Inngest), and persistent storage (Neon/Cloudflare R2), all managed via Infrastructure as Code (Terraform).
1. Infrastructure and Environment Setup
- Infrastructure as Code (IaC): Use the Vercel Terraform Provider  to automate project creation and domain management. Use the Cloudflare Terraform Provider  to manage R2 buckets and DNS.
- Secret Management: Centralize all API keys (WorkOS, Neon, Inngest) in Doppler. Inject these secrets into Vercel and your Agentics Linux Cluster using the Doppler CLI to ensure consistency across environments.
- Version Control: Host your source code on GitBucket (self-hosted Git platform). Mirror or sync critical repositories to a provider supported by Vercel (GitHub/GitLab/Bitbucket) to trigger automatic deployments .
2. Backend and Database Layer
- Database (Neon): Provision a serverless PostgreSQL instance on Neon.
     Enable Database Branching to match Vercel's preview deployments, ensuring isolated environments for every pull request.
     Connect via the Neon serverless driver  for optimized performance in serverless functions.
- API (FastAPI): Deploy your FastAPI application to Vercel as a single Vercel Function .
     Configure vercel.json with the @vercel/python builder and route all requests to your main.py.
   Object Storage: Use Cloudflare R2 for S3-compatible, zero-egress storage of ERP documents and media.

3. Application Services and Logic
- Background Jobs (Inngest): Use Inngest for reliable, event-driven workflows (e.g., invoice generation, email sync).
     Deploy the Inngest "serve" handler within your FastAPI/Vercel project at an /api/inngest endpoint.
     Connect your Vercel project via the Inngest Vercel Integration.
- Auth & SSO (WorkOS): Integrate WorkOS for Enterprise SSO and Directory Sync. Store WorkOS API keys in Doppler and access them in your FastAPI middleware.
- AI Orchestration:
     Central Bus: Implement a message bus (or use Inngest events) to coordinate between LangChain.js agents.
      Observability: Connect LangSmith Studio for tracing and evaluating your LLM chains during development on the Agentics Linux Cluster.

4. Native App Delivery
- Mobile Offering: Use Expo to build and deploy cross-platform native apps.
- Expo MCP: Utilize the Expo Model Context Protocol (MCP) to allow AI agents (running on your Linux cluster) to interact with and automate your mobile development environment, such as triggering builds or running simulations.
5. Development Workflow
- Agentics Linux Cluster: Host your heavy development workloads, AI model testing, and the Terraform MCP Server here. This cluster serves as a private, powerful sandbox for AI agents to manage infrastructure and code.
- Pageindex: Use this for indexing and searching internal ERP documentation or metadata to assist the "Agentic" workflows

---

## Agent Instructions

- **Use this when:** Following Step 1 of the deployment guide
- **Before this:** All Phase 1 and Phase 2 services configured and tested locally
- **After this:** Proceed to multi-tenant context switching validation
