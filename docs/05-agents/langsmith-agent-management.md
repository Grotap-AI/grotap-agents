---
title: "LangSmith Studio - Agent Management"
source: google-drive-docx
converted: 2026-03-01
component: "LangSmith"
category: ai
doc_type: setup-guide
related:
  - "LangGraph"
  - "LangChain"
  - "Claude-Code"
tags:
  - langsmith
  - studio
  - agents
  - deployment
  - management
status: active
---


# LangSmith Studio - Agent Management

LangSmith Studio (formerly LangGraph Studio) is not a standalone software package you install on your local machine like a traditional application. Instead, it is a web-based IDE that you "connect" to your agent's code.

Depending on your workflow, you access it in one of two ways:
1. Local Development (For Building/Debugging)
You don't install the Studio UI; you install the LangGraph CLI to serve your code locally and then view it in the LangSmith web interface.
- Install the CLI: Run pip install langgraph-cli.
- Run the Server: Navigate to your project directory and run langgraph dev. This starts a local development server.
   Access the Studio: Open your browser to the LangSmith Studio UI and connect it to your local server (usually http://127.0.0.1:2024).

2. Cloud Deployment (For Production)
If your agent is already deployed on LangSmith Cloud, the Studio is built directly into the platform.

- Access: Log in to LangSmith , navigate to Deployments in the sidebar, select your deployment, and click the Studio tab.
   Hosting Options: LangSmith offers Cloud (fully managed), Hybrid, or Self-hosted (via Docker/Kubernetes) infrastructure.

## Prerequisites:
- A LangSmith account and an API Key.
- Your application must be structured as a LangGraph project with a langgraph.json configuration file

---

## Agent Instructions

- **Use this when:** Setting up LangSmith Studio for agent management and tracing
- **Before this:** LangGraph project must exist with langgraph.json
- **After this:** Connect Claude Code agents to LangSmith for tracing
