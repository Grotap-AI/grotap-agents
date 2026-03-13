---
title: "LangSmith - Agent Builder Template Library"
source: google-drive-docx
converted: 2026-03-01
component: "LangSmith"
category: ai
doc_type: reference
related:
  - "LangGraph"
  - "LangChain"
tags:
  - langsmith
  - templates
  - agents
  - library
status: active
---


# LangSmith - Agent Builder Template Library

Yes, LangSmith offers a dedicated Agent Builder Template Library  featuring off-the-shelf, ready-to-deploy agentic templates. These templates are designed for common tasks and come pre-configured with the necessary instructions, tools, and triggers.

## Key Features of Off-the-Shelf Templates
- Ready-to-Deploy: Templates include predefined system prompts and integrated tools (connected via OAuth or API keys) for immediate use.
- Collaborative Design: Many templates are built in partnership with domain experts like Tavily, PagerDuty, Box, and Arcade.
- Full Customization: Users can clone a template to create an independent copy, allowing for modification of prompts, tools, and model selection without affecting the original.
   No-Code Building: For unique needs, you can describe a goal in natural language, and the Agent Builder  will draft instructions and suggest subagents for execution.

   LangChain

## Available Template Examples
The library includes several "starter" templates for various business functions:

- Sales/Productivity: Daily Calendar Brief (scans Google Calendar/Gmail for meeting context).
- Support: Email Assistant (automates email triage and drafting replies).
- Marketing: Social Media AI Monitor (tracks discussions on X and Hacker News and sends Slack updates).
- Recruiting: LinkedIn Recruiter (analyzes candidate requirements and outputs filtered lists).
   Intelligence: Competitor Intelligence via Tavily and On-call Triage via PagerDuty.

For developers needing deeper control, LangChain also provides LangGraph Templates  which offer access to the underlying code for complex, stateful multi-agent workflows.

## LangChain -
To get started, you can:
- Browse the full template library
- Check the Agent Builder documentation
- Learn how to connect custom tools via MCP servers

---

## Agent Instructions

- **Use this when:** Selecting and using pre-built agent templates
- **Before this:** LangSmith account and API key configured
- **After this:** Customise templates for specific ERP modules
