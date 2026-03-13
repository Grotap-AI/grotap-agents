---
title: "Security & Connection Stack"
source: google-drive-docx
converted: 2026-03-01
component: "Security"
category: devops
doc_type: reference
related:
  - "WorkOS"
  - "Doppler"
  - "GitGuardian-MCP"
  - "FastAPI"
tags:
  - security
  - compliance
  - connections
  - stack
  - reference
status: active
---


# Security & Connection Stack

Security & Connection Stack

## Component
Role
Doppler
Stores and injects your variables; no .env file needed.
GitGuardian
Monitors your repo to prevent anyone from using .env files.
Auth0
Provides the identity logic; its keys live safely in Doppler.
MCP Server
Acts as a bridge for AI agents, using its own secure config.

- Doppler (Secrets Management): Instead of your application reading a local .env file via dotenv, you use the Doppler CLI  to inject variables directly into your process at runtime (e.g., doppler run -- npm start). This keeps secrets out of your file system entirely.
- GitGuardian (Secrets Scanning): GitGuardian is there to ensure that no developer accidentally reverts to using a .env file and pushes it to GitHub. If you were still using dotenv and accidentally committed that file, GitGuardian  would flag it as a critical security leak.
- Auth0 (Identity): Your Auth0 Client Secrets and Domain would be stored inside Doppler as secrets. When your app runs, Doppler provides these to your Auth0 SDK, removing the need for a hardcoded .env file.
   MCP Servers: If you are using an Auth0 MCP Server , it manages its own authentication (like OAuth tokens) and configuration through standardized protocols or its own config files (e.g., claude_desktop_config.json), rather than relying on a project-level .env file.

   Doppler

---

## Agent Instructions

- **Use this when:** Understanding and auditing the security and connection stack
- **Before this:** None — review before any deployment
- **After this:** Ensure all connections match this security reference
