---
title: "Agent Install and types - Claude Code (AITMPL)"
source: google-drive-docx
converted: 2026-03-01
component: "Claude-Code"
category: ai
doc_type: setup-guide
related:
  - "LangSmith"
  - "Hetzner"
tags:
  - claude-code
  - agents
  - install
  - types
  - aitmpl
status: active
---


# Agent Install and types - Claude Code (AITMPL)

Claude Code Agent Team Templates (AITMPL)
The most comprehensive resource is Claude Code Templates (aitmpl.com), an open-source project featuring over 400 ready-to-use configurations. You can install specific agent "teammates" or entire stacks via their CLI:

- Install a Full Team:npx claude-code-templates@latest --agent development-team/frontend-developer --yes
- Available Pre-built Types: Includes roles for Frontend Developer, Code Reviewer, Tester, and DevOps.
   Interactive Browser: You can run npx claude-code-templates@latest to interactively browse and select agents to add to your project.

2. Built-in "Sub-agent" Types
Claude Code includes three native, pre-configured sub-agent types that do not require external templates:
- Explore: Read-only agents optimized for codebase navigation and research.
- Plan: Agents designed to propose structured approaches and architectural trade-offs.
   General-purpose: Full-capability agents that can analyze, modify files, and run commands.

   Excellent AI

3. Experimental "Agent Teams" (Multi-Instance)
For complex tasks, you can spawn a team where independent instances coordinate through a shared task list.

- Enable: Set "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" in your ~/.claude/settings.json.
   Deployment: You can define a team on the fly by describing the roles you need. For example:"Create an agent team: one for UX, one for Technical Architecture, and one for Security Review."

4. Community Governance Templates
For standardized team structures, developers use governance templates (like agent-spec) that define roles, coding conventions, and project invariants in a structured JSON file to prevent "AI drift" across the team.

---

## Agent Instructions

- **Use this when:** Installing and configuring Claude Code agent types on a Linux cluster
- **Before this:** Hetzner Linux cluster must be provisioned via Terraform MCP
- **After this:** Configure LangSmith for agent tracing and management
