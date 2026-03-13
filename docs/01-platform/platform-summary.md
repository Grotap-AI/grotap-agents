---
title: "Platform Summary — App Store Launcher Model"
source: internal
updated: 2026-03-05
component: "Platform-Architecture"
category: architecture
doc_type: reference
related:
  - "React"
  - "FastAPI"
  - "WorkOS"
  - "Neon"
  - "Cobrowse"
tags:
  - platform
  - app-store
  - launcher
  - requirements
  - ux
status: active
---

# grotap Platform — App Store Launcher Model

**Live URL**: https://app.grotap.com
**Model**: Multi-app marketplace. Every feature is a discrete app tenants subscribe to. WorkOS gates access; Stripe handles billing; Claude Agents build new apps from a base template.

---

## Core Concept

grotap is a **platform of apps**, not a single ERP. Think of it like an app store where:
- Grotap builds and publishes apps (keeps 100% revenue)
- Customers submit app ideas, vote on them, and can publish their own apps (creator gets 80%, Grotap keeps 20%)
- Claude Agents build new apps autonomously from a base template with WorkOS + Cobrowse pre-wired
- Every app inherits Cobrowse for live session support and agent-driven testing

---

## Navigation Shell (Top Nav — replaces left sidebar)

```
┌────────────────────────────────────────────────────────────────────────┐
│  grotap   [My Apps]  [Buy Apps]  [Beta Apps]  [Submit an Idea]  [Setup]│
│                                                  🔍  🔔  [Avatar ▼]   │
└────────────────────────────────────────────────────────────────────────┘
```

**Avatar dropdown:** Profile | Sign Out | *(grotap.com users only)* Tenant Switcher
**Tenant Switcher**: grotap internal users can switch to any tenant's org context for testing without re-authenticating.

---

## Top Nav Sections

### My Apps (default landing `/`)
- Grid of app icon cards for apps this tenant has subscribed to
- grotap domain users always see ALL apps without subscribing
- Search/filter bar, "X apps active" count
- Each card: icon, name, category, status badge, rating, phone icon (if has mobile version)

### Buy Apps (`/apps/buy`)
- Apps the tenant does NOT yet have
- Category tabs: All | Finance | Legal | HR | Operations | Platform | Infrastructure
- Subscribe button → WorkOS Feature enabled → app appears in My Apps

### Beta Apps (`/apps/beta`)
- Apps in beta testing (free during beta)
- Feedback button on each card feeds into app suggestion system

### Submit an App Idea (`/apps/suggest`)
- Submit form: title, long description, use case, images (R2 upload)
- Community voting board below — other users vote and add ideas
- Status badges: Submitted → Voting → Accepted → Building → Launched
- Grotap admin reviews ideas, decides to accept, then triggers agent pipeline
- Customers can be invited to collaborate with agents during build

### Setup (`/setup`)
- Tabbed: **Billing | Team | Settings | API Keys | Notifications | Audit | Reports**
- Replaces all separate utility pages — everything in one place

---

## App Card Design

```
┌───────────────────────┐
│   📄                  │
│                    📱 │  ← phone icon = mobile native version exists
│   Document Upload     │
│   Operations   [Beta] │
│   ⭐⭐⭐⭐ 4.2        │
│   Free / $12/mo       │
│   [Open] or [Subscribe]│
└───────────────────────┘
```

---

## App Registry — Built-In Apps (seed data)

All Grotap-built apps are free and auto-subscribed for all tenants:

| App | Icon | Category | Mobile | Notes |
|---|---|---|---|---|
| Dashboard | 📊 | Platform | ✅ | Main overview + quick actions |
| Document Upload | 📤 | Platform | — | R2 + PageIndex ingestion |
| Agent Pipeline | ⚡ | Operations | ✅ | 8-stage bug/enhancement pipeline |
| AI Agents | 🤖 | Operations | — | Agent session viewer |
| Servers | 🖥️ | Infrastructure | — | Hetzner node management |
| Farm Dashboard | 🌾 | Infrastructure | — | Terraform + scaling |
| Approvals | ✅ | Operations | ✅ | Human-in-the-loop gate |
| Cobrowse Console | 🎥 | Platform | — | QA testing + bug reports |
| Billing | 💳 | Platform | — | Stripe subscription management |
| Analytics | 📈 | Platform | — | System metrics |
| Audit Log | 📋 | Platform | — | Compliance log |
| Reports | 📑 | Platform | — | Pipeline analytics |
| Settings | ⚙️ | Platform | — | Org/tenant config |
| Notifications | 🔔 | Platform | ✅ | Alert preferences |
| App Ideas | 💡 | Platform | — | Community voting board |
| Support Portal | 🎧 | Internal | — | **grotap.com users only** |
| Admin | 🛡️ | Internal | — | **grotap.com users only** |

---

## Cobrowse — Mandatory in Every App

Every app (Grotap-built or agent-built) **always** has Cobrowse enabled:
- `CobrowseButton` — session trigger (bottom right)
- `CobrowseRemoteControlBanner` — red banner during remote control
- `CobrowseRedactionManager` — PII masking via `cb-mask` class
- `NarratedRecordingViewer` — session playback + AI ticket drafting

Enforced via `AppShell.tsx` in the base app template — agents cannot remove these.

---

## Agent-Built App Lifecycle

```
Idea submitted → voted → accepted by admin
    → agent pipeline triggered
    → agents clone base template (has WorkOS + Cobrowse pre-wired)
    → agents build unique features in src/features/
    → agents test via Neon snapshot + Cobrowse live recording
    → submitted with app.manifest.json → registered in apps table
    → status: building → beta → active
    → creator gets 80% of subscription revenue
```

---

## grotap Internal Users

Users with `@grotap.com` email:
- See ALL apps without subscribing
- Can switch tenant context via Tenant Switcher (view any client's data)
- Access Support Portal app (by-app and by-client views)
- Access Admin app

---

## Revenue Model

| App type | Grotap revenue | Creator revenue |
|---|---|---|
| Grotap-built apps | 100% | — |
| Customer-published apps | 20% commission | 80% |

Stripe handles payments; `app_earnings` table tracks per-payment splits.

---

## Agent Instructions

- **Use this when:** Understanding platform UX, app store model, navigation shell, or app lifecycle
- **Before this:** `CLAUDE.md` for rules, `00-INDEX.md` for doc map
- **After this:** `12-app-platform/app-store-model.md` for full DB/API spec
