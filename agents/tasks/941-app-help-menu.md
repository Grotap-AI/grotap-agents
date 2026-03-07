You are working on the grotap platform codebase at /home/agent/grotap-platform.

## Task #941 — App Help Menu (required in every app)

Every app must have a Help hover menu in the lower-left of the app sidebar.
This is a platform requirement — implement it for the RFID Pipe app.

### Read first

Read these files before writing any code:
- docs/12-app-platform/app-ux-patterns.md — full spec for sidebar layout
- frontend/src/pages/RfidPipeDashboardPage.tsx — understand current sidebar structure
- frontend/src/pages/RfidPipeScanListPage.tsx — see how sidebar is currently done

### What to build

**Step 1 — Create shared HelpMenu component**

Create frontend/src/components/HelpMenu.tsx

This is a hover-reveal menu anchored to the lower-left of the app sidebar.
It appears when the user hovers over a "? Help" trigger button.

The menu has 5 options:
1. Request Live Help — links to /support/appointments (opens in same tab)
2. Share Screen — calls Cobrowse start session (import from lib/cobrowse.ts)
3. Submit an App Enhancement — opens a small inline form → POST /support/enhancements { app_slug, type: 'enhancement', description }
4. Submit an App Issue — opens inline form → POST /support/enhancements { app_slug, type: 'issue', description }
5. Submit a New App Idea — links to /apps/suggest

For the inline forms (options 3 and 4): show a small textarea + Submit button that appears in-place. On submit, POST to /support/enhancements, show a "Submitted!" confirmation, then close.

Use api from ../lib/api for all API calls.

Styling: dark theme matching the rest of the app. The trigger is a small "? Help" text link at the bottom of the sidebar. On hover, the menu expands upward with the 5 options listed.

**Step 2 — Add HelpMenu to all 4 RFID Pipe pages**

The RFID Pipe app has these pages:
- frontend/src/pages/RfidPipeDashboardPage.tsx
- frontend/src/pages/RfidPipeBatchTemplatesPage.tsx
- frontend/src/pages/RfidPipeScanListPage.tsx
- frontend/src/pages/RfidPipeScanDetailPage.tsx

In each page, find the sidebar section and add:
1. A divider above the help area
2. <HelpMenu appSlug="rfid-pipe" /> at the bottom of the sidebar, above the user email display

**Step 3 — Add backend endpoint if missing**

Check if POST /support/enhancements exists in platform/backend/app/routers/support.py (or support_live.py).

If it doesn't exist, add it:
```python
@router.post("/enhancements")
async def submit_enhancement(
    payload: dict,
    request: Request,
    db = Depends(get_control_plane_db)
):
    # payload: { app_slug, type, description }
    # Insert into support_enhancements table
    # Return { id, status: 'submitted' }
```

Check the support_enhancements table schema first to match column names.

**Step 4 — Commit**

```
git add -A
git commit -m "feat: add Help hover menu to RFID Pipe app sidebar (#941)"
git push origin master
```
