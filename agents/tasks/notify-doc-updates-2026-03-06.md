---
id: notify-doc-updates-2026-03-06
type: notification
priority: normal
---

# Doc Update Notification — 2026-03-06

Platform documentation has been updated. Read and acknowledge the following changes before taking on any new app build or review tasks. No code changes required — this is a knowledge sync.

## New Files

### `docs/12-app-platform/app-ux-patterns.md` — REQUIRED READING
Every app built on the platform must now implement these universal UX patterns:
- **Left sidebar** listing all screens within the app
- **Help hover menu** (lower-left sidebar) with 5 options: Request Live Help (Schedule / Ping), Share Screen, Submit App Enhancement, Submit App Issue, Submit New App Idea
- **Back to Apps** link lower-left, above user email, with divider line
- **App name** stays at the top — never replaced by nav text

These are mandatory. The agent checklist in `app-template-guide.md` has been updated to include these requirements.

### `docs/12-app-platform/apps/rfid-pipe.md` — New App Spec
RFID Pipe is a planned app (slug: `rfid-pipe`, category: Inventory/Operations). Full spec includes:
- Batch Templates: scrollable field list, Sum by Rule (up to 5 column grouping pulldowns), 3-dot menu (Edit/Archive/Delete with typed confirmation)
- Review and Apply: renamed from "Select a batch" → "Select Scans to Review", column filters, checkboxes, bulk status updates, "Ignore Forever" flag on RFID IDs
- Dashboard: Recent Scans only (User, Date, Time Synced, Total Scans, Status)
- Setup App: label changes (Company Info, Company Name), full Audit Log screen

## Updated Files

### `docs/12-app-platform/support-portal.md`
Support portal now has **7 tabs** (was 3). New tabs:
- **Tab 4: Active Users** — live logged-in users, Join Cobrowse session button
- **Tab 5: Scheduled Appointments** — live help meeting schedule, assignable to team members
- **Tab 6: New App Requests** — enhancement/issue/idea submissions; support team generates MD files via Claude plugin, then submits to agent queue
- **Tab 7: Agent Questions Queue** — agents post questions here during builds; humans answer; agents resume once resolved

New API endpoints added: `/support/active-users`, `/support/appointments`, `/support/app-requests`, `/support/agent-questions`.

### `docs/12-app-platform/app-suggestions.md`
Updated flow — new statuses added:
```
accepted → md_created → ready_to_build → queued → building → launched
```
- `ready_to_build`: human manually sets this after MD files exist for the project
- **Two-team agent model**: Bug Team (always-on for production bugs) + New App Team (works build queue). New app builds can only be interrupted by emergency bug cases.

### `docs/12-app-platform/app-template-guide.md`
New section: "App UX Standards (Required)" referencing `app-ux-patterns.md`.
Checklist now includes:
- [ ] Left sidebar implemented with all app screens
- [ ] Help hover menu present with all 5 options
- [ ] Back to Apps in lower-left sidebar above user email (with divider)
- [ ] App name at top (not replaced by nav text)

## Action Required

1. Read `docs/12-app-platform/app-ux-patterns.md` in full
2. Read `docs/12-app-platform/apps/rfid-pipe.md` in full (if you are on the New App Team)
3. On all future app builds: implement left sidebar, Help menu, and Back to Apps per spec
4. Acknowledge this notification by updating your session notes

No immediate build tasks are assigned by this notification. Await queue assignment from dispatch.
