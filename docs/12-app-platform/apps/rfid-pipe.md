---
title: "RFID Pipe — App Spec"
updated: 2026-03-06
doc_type: app-spec
category: apps
tags: [rfid, inventory, mobile, batch, scanning]
status: planned
---

# RFID Pipe App Spec

**App slug:** `rfid-pipe`
**Category:** Inventory / Operations
**Has mobile:** true (RFID Mobile Scan App)
**Status:** planned

---

## Overview

RFID Pipe is a two-part app: a web app for managing, reviewing, and applying RFID scan batches, and a companion mobile scanning app. Scans are captured on mobile devices and synced to RFID Pipe for review, grouping, and application to inventory records.

---

## Batch Templates — Create/Edit

### Layout Changes
- Remove the template list from the create batch screen
- Change format to a scrollable vertical list of field inputs (no table/grid layout)
- Field labels: "Column 1", "Column 2", … "Column N" — user fills in any column name they want

### Fields (top to bottom)
1. **Create template** — text input field inline on same row as label
2. **Sum by Rule** — pulldowns to select up to 5 column names for grouping/summing:
   ```
   Sum by Rule:
   [Column Dropdown 1]
   [Column Dropdown 2]
   [Column Dropdown 3]
   [Column Dropdown 4]  (optional)
   [Column Dropdown 5]  (optional)
   ```
   - Each pulldown lists all column names defined in the template
   - Selecting e.g. "Description" + "Size" means: when reviewing a scan, the user can view a "Sum By" grouped report that counts unique combinations of those fields
3. **Column 1 … Column N** — text inputs, scrollable

### Sum by Rule — Example
If a batch template has columns: `RFID_ID, Description, Size`, and user sets Sum By Rule = `[Description, Size]`:

Raw scan data:
```
RFID_ID       Description    Size
abc123        Abelia         2g
def456        Abelia         2g
ghi789        Abelia         2g
jkl012        Abelia         1g
```

Sum By view output:
| Qty Scanned | Description | Size |
|---|---|---|
| 3 | Abelia | 2g |
| 1 | Abelia | 1g |

Column labels in the Sum By view use the field names saved in the batch template.

---

## Batch Templates — Grid View

### 3-Dot Menu (replaces Open button)
Each row in the templates grid shows a 3-dot `⋮` overflow menu with:
- **Edit** — reopens the Create Batch screen pre-populated with existing values
- **Archive** — sets `status = 'archived'`; template is hidden from default grid load (add "Show Archived" toggle to surface them)
- **Delete** — shows confirmation dialog:
  - Dialog text: "Are you sure you want to delete this template?"
  - User must type `Delete` in a text input
  - Confirm button labeled `DELETE` (bottom right of dialog)

---

## Navigation — Back to Apps Link

Applies to RFID Pipe and all apps going forward:

- **Remove** the small "Back to Apps" text from top-left
- **Move** "Back to Apps" to **lower-left of the left sidebar**, immediately above the user's email address
- Add a **horizontal line divider** between "Back to Apps" and the email address below it
- Font size: same as other sidebar labels (not small/muted)
- Move the app name label (e.g. "RFID Pipe") back to the **top** of the screen where it belongs

> See `app-ux-patterns.md` for the universal sidebar layout standard.

---

## Review and Apply — Scan List

### Label Change
- Old: "Select a batch to Review"
- New: **"Select Scans to Review"**

*Note: what was previously labeled as "batch" in this view is actually a scan session synced from a mobile device, not a batch template.*

### Simulated Scan Data
For development/demo, seed the database with a simulated scan using the values below.

**Scan-level fields (same on all records):**
| Field | Value |
|---|---|
| RFID Tag | `x` |
| rfid_id | random 16-character alphanumeric code per record |
| Date Created | 2025-02-15 |
| Vendor | Manor View Farm |
| Device | aallison |

**Products — repeat each ProductId randomly 50–5000 times:**

| ProductId | Description | Size |
|---|---|---|
| 3499 | Apple Coffee | #15 |
| 3489 | Apple Duncan | #15 |
| 3493 | Apple Duncan #2 | #15 |
| 3487 | Apple Geneva 41 | #15 |
| 3502 | Acer Bloodgood | #3 |
| 3503 | Acer Bloodgood | #5 |
| 3504 | Acer Bloodgood | #5 |
| 3448 | Ajuga Bronze Beauty | 2.5 Quart |
| 3498 | Ajuga Bronze Beauty | 2.5 Quart |
| 3444 | Begonia Cracklin' Rose | 3 Gallon |
| 3445 | Begonia Cracklin' Rose | 3 Gallon |
| 2630 | Begonia Reiger Red | 1204 |
| 2619 | Begonia Reiger Sky Blue | 1204 |
| 3456 | Begonia Reiger True Pink | #1 |
| 2616 | Begonia Reiger Yellow | 1204 |
| 3441 | Cordyline Red Pepper | 3 Gallon |
| 3495 | English Daisy Bellisima Mix | F10PPP-NF |
| 3496 | English Daisy Bellisima Mix | F10PPP-NF |
| 3455 | Geranium Zonal Allure Bright Lavender | 8inch |
| 3496 | Gerbera Daisy Elephant RED | F10PPP-NF |
| 3495 | Gerbera Daisy Elephant Scarlet | F10PPP-NF |
| 3495 | Gerbera Daisy Royal Orange Scarlet Dark Eye | F10PPP-NF |
| 3496 | Gerbera Daisy Royal Orange Scarlet Dark Eye | F10PPP-NF |
| 3504 | Picture Tag | #5 |
| 3467 | Allium, Lavender Bubbles | #3 |
| 3471 | Allium, Lavender Bubbles | #3 |
| 3460 | Begonia Reiger 'Dark Green' | #1 |
| 3461 | Begonia Reiger 'Deep Green' | #1 |
| 2742 | Begonia Reiger Dark Pink | 12inch HB |
| 2732 | Begonia Reiger Red | 12inch HB |
| 2749 | Begonia Reiger Red | #1 |
| 3501 | Begonia Reiger Red | 1204 |
| 2719 | Begonia Reiger Sky Blue | #1 |
| 2734 | Begonia Reiger Sky Blue | 12inch HB |
| 2740 | Begonia Reiger Sky Blue | 12inch HB |
| 2720 | Begonia Reiger Yellow | #1 |
| 2736 | Begonia Reiger Yellow | 12inch HB |
| 2738 | Begonia Reiger Yellow | 12inch HB |
| 3470 | Viburnum, Chicago Lustre® CG | 8in |

### Grid Columns
- Scanned by
- Date
- Time Synced
- Total Scans
- Status (New, Reviewed, Applied, Archived, Delete)
- Per-column filter boxes above the grid

### Bulk Actions
- Checkboxes on left of each row
- Check All / Uncheck All controls
- Select some rows → **Update Status** button → pick new status → hit Apply

---

## Review and Apply — Scan Detail (Double-click)

When user double-clicks a scan row to view individual RFID records:

### Grid Controls
- Filter boxes above each column
- Checkboxes on left of each row
- Check All / Uncheck All

### Bulk Update Button
Select records → **Update** button with options:
- **Export** — download selected records as CSV/Excel
- **Ignore These Tags Forever** — marks selected RFID IDs as permanently ignored; they are hidden in current view and in all future scans that contain the same RFID ID unique identifier
- **Delete** — removes selected records

> Ignored tags: stored in an `ignored_rfid_tags` table (or equivalent) keyed by `rfid_id`. During sync from mobile, any incoming record whose `rfid_id` is in this table is automatically filtered out.

---

## Dashboard

Remove the Batches section entirely.

**Recent Scans** section replaces it with these columns:

| Column | Description |
|---|---|
| User | Who initiated the scan / synced the device |
| Date | Scan date |
| Time Synced | When data arrived from mobile |
| Total Scans | Count of RFID records in the scan |
| Status | Current status of the scan |

---

## Setup App Changes

### Organization Info screen
- Rename section label: **"Company Info"** (was "Organization Info")
- Rename field label: **"Company Name"** (was "Organization Name")

### Apps screen
- Rename: **"RFID Pipe App and RFID Mobile Scan App"** (was "RFID SaaS")
- Rename toggle description: **"Toggle which apps are available for your company."** (was "Toggle which apps are available for your organization.")

### Audit Log (new screen)
Build a full audit log screen in the Setup app. Every user action in the app system records:

| Field | Description |
|---|---|
| Time | Timestamp of action |
| Date | Date of action |
| Screen Name | Which page/screen the action occurred on |
| User Email | Who performed the action |
| Original Data | Value(s) before the change |
| Changed Data | Value(s) after the change |

The audit log is read-only; display as a filterable, paginated grid. Support filtering by date range, user, and screen name.

---

## Agent Instructions

- **Use this when:** Building or modifying the RFID Pipe app
- **Template:** Clone from `platform/app-template/`; slug = `rfid-pipe`
- **Before this:** `app-template-guide.md` for standard build steps, `app-ux-patterns.md` for sidebar/nav layout
- **Related:** `app-store-model.md` for DB/API registration
