---
title: "Agent Management - Claude Command Line"
source: google-drive-docx
converted: 2026-03-01
component: "Claude-Code"
category: ai
doc_type: setup-guide
related:
  - "LangSmith"
  - "LangGraph"
tags:
  - claude-code
  - cli
  - agents
  - management
status: active
---


# Agent Management - Claude Command Line

Agent Management - Claude Command Line

   The Better Option: Claude Code for Linux Servers
If you need to manage an agent team on a Linux server, Claude Code is the correct tool. It is a CLI-based agent that runs natively on Linux and includes dedicated team management features.

- Native Linux Support: Unlike Cowork, Claude Code runs directly in your Linux terminal and can be installed via npm.
- Agent Teams Mode: By setting the experimental flag CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1, you can enable a "Lead Agent" that spawns and manages multiple parallel "Teammate Agents".
- Server Orchestration: Because it has terminal access, it can execute bash commands, manage Docker containers, and interact with the server's filesystem to coordinate complex workflows.
   Security Sandboxing: On Linux, it uses bubblewrap for OS-level isolation, ensuring agents stay within defined boundaries while working on your server.

   Summary of Capabilities
   Feature
   Claude Cowork
   Claude Code
   Primary OS
   macOS Only
   Linux, macOS, Windows
   Interface
   GUI (Visual Task List)
   CLI (Terminal-based)
   Agent Management
   Parallel sub-agents (Internal)
   Formalized Agent Teams (Lead/Teammates)
   Server Use
   Not supported
   Best for servers/Docker

---

## Agent Instructions

- **Use this when:** Managing Claude Code agents from the command line
- **Before this:** Claude Code must be installed
- **After this:** Set up LangSmith Studio for visual agent management
