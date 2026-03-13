---
title: "App UX Patterns — Universal Standards for All Apps"
updated: 2026-03-06
doc_type: reference
category: platform
tags: [ux, navigation, sidebar, help, cobrowse, live-support]
status: active
---

# App UX Patterns — Universal Standards

> These patterns apply to every app built on the grotap platform. Agents must implement all of them when building from the app template.

---

## Left Sidebar Navigation

Every app has a **left sidebar** that lists all screens/sections within that app.

```
┌─────────────────────────────────────────┐
│ [App Name]                    [TopNav]  │
├──────────┬──────────────────────────────┤
│ Sidebar  │  Main Content               │
│          │                             │
│ Screen 1 │                             │
│ Screen 2 │                             │
│ Screen 3 │                             │
│          │                             │
│          │                             │
│          │                             │
│ ──────── │                             │
│ Help     │                             │
│ ──────── │                             │
│ Back to  │                             │
│ Apps     │                             │
│ ──────── │                             │
│ user@... │                             │
└──────────┴──────────────────────────────┘
```

### Sidebar structure (top to bottom)
1. App name / logo at top
2. Navigation links — one per screen in the app
3. Divider
4. **Help** (with hover-expand menu — see below)
5. Divider
6. **Back to Apps** link
7. Divider
8. User email address

### Sidebar requirements
- Same font size for Help, Back to Apps, and nav links — no small/muted text for these
- Active screen highlighted in sidebar
- Sidebar always visible (not collapsible by default)

---

## Back to Apps Link

- Location: **lower-left sidebar**, above the user's email address
- Separated from email by a horizontal divider line
- Font size: same as other sidebar labels
- Navigates to `/apps/my` (My Apps page)

---

## Help Menu

**Location:** Lower-left sidebar, above the "Back to Apps" link, separated by a divider.

**Behavior:** On hover, expands upward to show these links:

```
┌─────────────────────────────┐
│ Submit a New App Idea       │
│ Submit an App Issue         │
│ Submit an App Enhancement   │
│ Share Screen                │
│ Request Live Help     ►     │
├─────────────────────────────┤
│ Help ▲                      │
└─────────────────────────────┘
```

### Help menu items

#### Request Live Help
Expands to two options:

**1. Schedule a Live Meet Up**
- Opens a calendar picker showing available time slots
- User selects 15, 30, or 45 minute duration
- Appointment is created and appears in the **Support App → Scheduled Appointments** screen
- Grotap team can assign the appointment to any team member in that screen
- User receives confirmation with meeting details

**2. Ping for Live Help Now**
- Broadcasts a notification to all Grotap users who have **"Open for Support" = true** in their status
- Those users receive a pop-up with the option to join
- Joining initiates a **Cobrowse session** — the requesting user must click "Allow" before the support agent can see their screen
- Live session appears in **Support App → Active Users** for any Grotap user to monitor or join

#### Share Screen
- Initiates a Cobrowse session directly from the app
- User is prompted to confirm before session starts
- Session is visible in **Support App → Active Users**

#### Submit an App Enhancement
- Opens a form to describe an improvement request for the current app
- Submitted items land in **Support App → New App Requests** grid

#### Submit an App Issue
- Opens a bug/issue report form for the current app
- Submitted items create a `bug_reports` record

#### Submit a New App Idea
- Links to `/apps/suggest` (the community idea board)

---

## Agent Checklist — UX Patterns

Every app built from the template must include:

- [ ] Left sidebar with all app screens listed
- [ ] Help hover menu with all 5 options implemented
- [ ] "Back to Apps" in lower-left sidebar, above user email, with divider
- [ ] App name displayed at top of screen/sidebar (not replaced by back-nav text)
- [ ] Cobrowse session capability wired into Share Screen and Ping for Live Help
- [ ] Live help forms submit to correct backend endpoints

---

## Agent Instructions

- **Use this when:** Building any new app — these patterns are required in every app
- **Before this:** `app-template-guide.md` for build steps
- **Related:** `support-portal.md` for the Grotap-side screens that receive live help requests, scheduled appointments, and app enhancement submissions
- **Cobrowse:** All session initiation must go through `lib/cobrowse.ts` — never call Cobrowse SDK directly (Rule 9)
