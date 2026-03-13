---
title: "Agent development teams - How To"
source: google-drive-docx
converted: 2026-03-01
component: "Claude-Code"
category: ai
doc_type: how-to
related:
  - "LangSmith"
  - "LangGraph"
  - "GitGuardian-MCP"
tags:
  - agents
  - teams
  - development
  - workflow
status: active
---


# Agent development teams - How To

how best to do this with for agent development teams
For agent development teams in 2026, the most effective approach shifts from "building a chatbot" to
orchestrating a modular workforce. Success is driven by treating agents as specialized team members with clear roles, defined interfaces, and rigorous evaluation.

1. Team Structure & Roles
Effective AI agent teams are typically cross-functional and scale in complexity based on the project's maturity:

8
- Core Squad (MVP level): Minimum of an AI Product Manager (defines the problem/KPIs), an AI/ML Engineer (builds the reasoning logic), and a Software Engineer (integrates tools and handles productionization).
- Specialized Roles (Scale level): As complexity grows, teams add Data Engineers for infrastructure, MLOps for deployment, and Domain Experts to ground the agent's logic in industry reality.
   Compliance: For regulated industries like Finance, an AI Compliance Specialist is essential from day one to manage risk and auditability.

   8allocate

2. Standardized Development Workflow
Teams should move away from "spaghetti" manual wiring toward structured frameworks that map to human team dynamics.

## Medium
- Decomposition: Break complex goals into discrete sub-tasks with specialized agents (e.g., a Research Agent, a Fact-Checker, and a Reviewer).
- The "Manager" Pattern: Implement a Manager Agent to orchestrate the flow, delegate tasks, and synthesize outputs from sub-agents.
   Baseline then Optimize: Start prototypes with the most capable models (e.g., GPT-4o or Claude 3.5) to set a performance baseline, then swap in smaller, cheaper models for specific tasks to optimize cost and latency.

3. Key Frameworks & Tools for 2026
This platform uses LangGraph exclusively for all agent orchestration. LangGraph was selected for its deterministic control flow, built-in state persistence, and first-class human-in-the-loop support via `interrupt()` — all of which are required for ERP-grade reliability.

Framework
Best Use Case
Key Strength
LangGraph
Production-grade, stateful workflows
Deterministic control, state persistence, and easier debugging

Note: Frameworks such as CrewAI, AutoGen, LlamaIndex, and Semantic Kernel are NOT used in this platform. All agent graphs are implemented in LangGraph (TypeScript). For knowledge retrieval, the platform uses PageIndex + Neon pgvector — not LlamaIndex or any alternative vector framework.
4. Essential Guardrails & Observability
Development teams must prioritize "Production Preparedness" over novelty:

## LinkedIn
- Observability: Implement tracing tools (e.g., LangSmith, Langfuse, or Fiddler) to track every decision, tool call, and error from day one.
- Evaluation (Evals): Use libraries to measure not just final output, but individual agent components and underlying LLM performance against "golden tasks".
   Safe Execution: Use Model Context Protocol (MCP) to securely expose tools and data sources via read-only APIs with RBAC, ensuring agents don't have raw database credentials.

For a deep dive into how to orchestrate these different agent roles and tools effectively:
For a deep dive into how to orchestrate these different agent roles and tools effectively:

---

## Agent Instructions

- **Use this when:** Setting up and coordinating agent development teams
- **Before this:** LangSmith Studio and LangGraph must be configured
- **After this:** Run GitGuardian MCP to scan agent-generated code
