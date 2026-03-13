---
title: "Cobrowse SDK Features to Implement"
source: google-drive-docx
converted: 2026-03-01
component: "Cobrowse-IO"
category: frontend
doc_type: how-to
related:
  - "React"
  - "FastAPI"
tags:
  - cobrowse
  - sdk
  - implementation
  - screenshare
  - ai-agent
status: active
---


# Cobrowse SDK Features to Implement

Cobrowse

## List all Cobrowse features in SDK for web and native
Cobrowse.io
 provides a unified SDK suite for Web, Android, and iOS (native) that enables real-time collaboration. While many features are cross-platform, some capabilities are specific to the environment.
Core Features (Web & Native)
- Real-time Screenshare: View the user's screen in real-time with high performance and low latency.
- Remote Control: Request permission to point, click, and type on the user's behalf.
- Annotations: Visual guidance tools including:
     Laser Pointer: Directing the user with a temporary light.
     Drawing & Shapes: Drawing directly on the screen or using arrows and rectangles.
- Data Masking & Redaction: Hide sensitive information (e.g., PII, credit card numbers) so it never leaves the user's device.
- Session Initiation: Multiple ways to start a session, including 6-digit codes, SMS/email links, and push notifications.
  100% White-label: Fully customizable UI to match your brand's existing components and styles.
   Audit & Compliance: Detailed audit logs and optional session video recordings.
Platform-Specific Capabilities
Feature
Web SDK
Native SDK (iOS/Android)
Disappearing Ink
Available for quick visual cues.
Generally not listed for native.
Scroll & Select
Specifically enabled for web page navigation.
Handled via native gestures.
Universal Cobrowse
Browse 3rd party websites via a proxy without code.
N/A (Focused on app-specific views).
Full Device Mode
Share entire desktop (requires user permission).
Share the entire mobile OS screen.
Mobile Camera Share
N/A
Use the device camera to see what the user sees in real life.

## Advanced & Enterprise Features
- Agent Present Mode: Allows agents to share their own screen or approved content back to the customer.
- PDF Collaboration: View and collaborate on PDF documents within the session.

---

## Agent Instructions

- **Use this when:** Implementing Cobrowse SDK features in the React app
- **Before this:** Cobrowse features list reviewed, vendor wrapper created
- **After this:** AI agents can now co-browse with users
