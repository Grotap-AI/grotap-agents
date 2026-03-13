---
title: "Cobrowse Features to include as components any App can call and use"
source: google-drive-docx
converted: 2026-03-01
component: "Cobrowse-IO"
category: frontend
doc_type: reference
related:
  - "React"
  - "FastAPI"
tags:
  - cobrowse
  - screenshare
  - ai-agent
  - components
  - features
status: active
---


# Cobrowse Features to include as components any App can call and use

Cobrowse Features to include as components any App can call and use

n Cobrowse.io , Universal Co-browsing refers specifically to the ability for agents to follow customers seamlessly across the entire digital journey, including third-party websites, apps, and content that you do not own or manage.

## Cobrowse.io
When using Universal Co-browsing, the following features and capabilities are supported:
Core Interaction Tools
These tools allow agents to provide visual guidance even on non-owned properties:

- Laser Pointer: A virtual pointer to highlight specific areas of the screen without taking control.
- Annotation & Drawing: Agents can draw, use disappearing ink (web only), or place arrows and rectangles to guide the customer.
   Remote Control: With permission, agents can scroll, click, and type on behalf of the customer.

   Cobrowse.io

## Privacy & Security Features
Universal Co-browsing maintains enterprise-grade security on third-party sites:

- Sensitive Data Redaction: Automatically masks sensitive information (like credit card numbers) using a "private by default" approach.
- User Consent Prompts: Customizable dialogs ensure customers remain in control and must explicitly grant permission before a session or specific action begins.
   Audit Trail & Session Replay: Captures a full record of agent actions for compliance and quality assurance.

## Deployment & Support
- No Code Integration: Supports 3rd-party websites without requiring any code to be added to those external sites, often utilizing a Cobrowse Proxy .
- Cross-Platform Support: Works across web, Android, iOS, Windows, and MacOS.
   PDF Co-browsing: Extends guidance capabilities to PDF documents and other static third-party content.

   Cobrowse.io

## Related Advanced Capabilities
While separate from the core "Universal" mode, these often work alongside it to enhance the experience:

- Full Device Screen Share: Allows agents to see outside the browser/app to system settings or other mobile apps.
- Agent Present Mode: A "reverse" co-browsing mode where the agent shares their own screen with the customer.
   Mobile Camera Share: Lets the agent see the customer's physical environment via their mobile camera for hardware troubleshooting.

---

## Agent Instructions

- **Use this when:** Understanding which Cobrowse features to implement as shared components
- **Before this:** React frontend scaffolded
- **After this:** Implement Cobrowse SDK features from the SDK guide
