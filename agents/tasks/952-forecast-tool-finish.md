---
title: "feat: finish forecast tool — replace placeholder with full UI (#952)"
branch: task/952-forecast-finish
complexity: medium
---

# Task 952 — Finish Forecast Tool

## Context
The forecast tool backend and sub-views are fully built but the entry page is a placeholder ("Forecast coming soon"). The grid editing view, CSV import view, and all 11 backend endpoints are production-ready. This task replaces the placeholder with a real forecast dashboard that ties everything together.

## What Already Exists (DO NOT REWRITE)
- `backend/app/routers/forecast.py` — 11 endpoints, fully working:
  - `GET /forecast/forecasts` — list forecasts for tenant
  - `POST /forecast/forecasts` — create forecast (name, granularity, start_date, end_date)
  - `GET /forecast/forecasts/{id}` — get forecast detail
  - `PATCH /forecast/forecasts/{id}` — update forecast
  - `DELETE /forecast/forecasts/{id}` — delete forecast
  - `POST /forecast/forecasts/{id}/skus` — add SKU
  - `POST /forecast/forecasts/{id}/skus/import` — bulk CSV import SKUs
  - `POST /forecast/forecasts/{id}/sub-skus/import` — bulk CSV import sub-SKUs
  - `PUT /forecast/entries` — upsert entries (batch)
  - `GET /forecast/forecasts/{id}/entries` — get entries
- `frontend/src/pages/forecast/ForecastGridView.tsx` — full editable grid (17KB, working)
- `frontend/src/pages/forecast/ForecastImportView.tsx` — CSV import with preview (9KB, working)
- `backend/migrations/forecast_tables.sql` — 4 tables, all migrated
- Route `/forecast` wired in App.tsx
- Backend registered in main.py with `/forecast` prefix
- WorkspaceContext maps `'forecast-tool'` → `/forecast`

## Requirements

### 1. Replace ForecastPage.tsx placeholder
Rewrite `frontend/src/pages/forecast/ForecastPage.tsx` to be a real forecast dashboard:

**Default view — Forecast List:**
- Fetch forecasts from `GET /forecast/forecasts`
- Card or table layout showing: name, granularity, date range, SKU count, created_at
- Status indicator per forecast
- "Create Forecast" button → modal with: name, granularity (weekly/monthly/annual dropdown), start_date, end_date → `POST /forecast/forecasts`
- Click forecast → opens forecast detail view (in-page, not new route)
- Delete button per forecast → confirm dialog → `DELETE /forecast/forecasts/{id}`

**Forecast Detail view (when a forecast is selected):**
- Back button to return to list
- Forecast name + metadata header
- Tab navigation:
  - **Grid** tab → renders `<ForecastGridView />` passing the forecast_id
  - **Import** tab → renders `<ForecastImportView />` passing the forecast_id
- Edit forecast name/dates button → inline edit or modal → `PATCH /forecast/forecasts/{id}`

### 2. Wire ForecastGridView and ForecastImportView
These components already exist and are functional. They need to receive the selected `forecast_id` as a prop. Check how they currently get their forecast context — they may already accept props or use URL params. Adapt ForecastPage to pass the correct props.

### 3. Add tile to AppLibraryPage.tsx
Add to the MODULES array in `frontend/src/pages/AppLibraryPage.tsx`:
```
{ icon: '📊', title: 'Forecast Tool', desc: 'SKU-level demand forecasting with grid editing and CSV import', path: '/forecast', badge: 'Beta' }
```

### 4. Add to CATEGORIES if needed
If 'Operations' is not already in CATEGORIES array, add it.

## Verification
- Navigate to `/forecast` → should see forecast list (or empty state with create button)
- Create a forecast → should appear in list
- Click forecast → should show Grid and Import tabs
- Grid tab renders ForecastGridView with editable cells
- Import tab renders ForecastImportView with CSV upload
- Forecast tile visible in app library
- TypeScript check passes (`tsc --noEmit`)

## Important Rules
- Use `request.state.organization_id` NOT `request.state.tenant_id` in any backend code
- No unused imports (tsconfig has `noUnusedLocals: true`)
- Follow `<PrivateRoute><><TopNav />...</>` pattern for routes (already wired)
- DO NOT rewrite ForecastGridView.tsx or ForecastImportView.tsx — they work, just integrate them
