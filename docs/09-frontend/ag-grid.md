---
title: "AG Grid — Platform Grid Component"
component: "Frontend"
category: frontend
doc_type: how-to
related:
  - "vendor-wrapper-pattern"
  - "cobrowse-sdk"
tags:
  - ag-grid
  - data-grid
  - vendor-wrapper
  - enterprise-license
status: active
---

# AG Grid — Platform Grid Component

**Owner directive (2026-07-06): ALL platform app grids use AG Grid Enterprise** via the
shared `DataGrid` vendor wrapper. New grids must not use `mantine-react-table`,
`@tanstack/react-table`, or raw `<table>`; existing grids migrate app-by-app
(ScanTap first, then the remaining MRT pages via pipeline cases).

## Usage (the only supported way)

```tsx
import { DataGrid, type ColDef } from '../components/DataGrid'

const columnDefs: ColDef<Row>[] = [
  { field: 'name', filter: true },
  { field: 'qty', aggFunc: 'sum' },
]

// The grid needs a sized container.
<div style={{ height: 600 }}>
  <DataGrid rowData={rows} columnDefs={columnDefs} />
</div>
```

`DataGrid` accepts every `AgGridReactProps` prop and applies the grotap Quartz
theme by default. Common types (`ColDef`, `GridApi`, `GridReadyEvent`, …) are
re-exported from `components/DataGrid` — type-only, zero bundle cost.

## Rules

1. **NEVER import `ag-grid-community` / `ag-grid-enterprise` / `ag-grid-react`
   directly in app code.** Runtime imports live only in
   `frontend/src/lib/agGrid.ts` and `frontend/src/components/DataGridInner.tsx`
   (vendor wrapper pattern — same contract as `lib/cobrowse.ts`).
2. **Do not register modules or touch `LicenseManager` yourself** — the wrapper
   registers `AllEnterpriseModule` and sets the license exactly once when the
   lazy chunk loads.
3. **Do not add a root-level `AgGridProvider`** and do not import the wrapper
   from `main.tsx`/`App.tsx` — AG Grid must stay in its lazy chunk (~2.4 MB).
   A root import drags it into the main bundle and can break the PWA workbox
   6 MB precache ceiling.
4. **Theme via `grotapGridTheme`** (in `lib/agGrid.ts`), not CSS imports — the
   v33+ Theming API injects styles itself. Extend the theme with `withParams`;
   don't import `ag-grid.css`/`ag-theme-*.css` (legacy path, double-styling).

## License

- Key lives in Doppler (`grotap` project): `AG_GRID_LICENSE`, aliased as
  `VITE_AG_GRID_LICENSE` (Doppler reference) in `prd` and `dev` so Vite embeds
  it at build time. Doppler prd auto-syncs to the Vercel frontend project —
  no Vercel-side config.
- If the env var is missing the wrapper logs one warning and grids run with the
  evaluation watermark — never a crash (kill-switch degrade).
- **Canary:** `/grid-smoke` (hidden, PrivateRoute, not in nav) renders an
  enterprise row-grouping grid. Verify licensed operation any time with:

  ```sh
  cd frontend
  doppler run -p grotap -c prd -- npx playwright test e2e/ag-grid-license-smoke.spec.ts --reporter=line
  ```

  It asserts: rows render, group rows render, `.ag-watermark` is hidden, and no
  license complaints on the console. Note: AG Grid ALWAYS renders the
  `.ag-watermark` DOM node and hides it (`ag-hidden`, `display:none`) when the
  license is valid — assert hidden-ness, not absence.
- Run the canary after every AG Grid version bump. A license covers versions
  released during its term — if a bump shows the watermark with an
  "incompatible version" console error, pin back to the newest covered version
  and file an HI hold for license renewal.

## Versions

`ag-grid-community` / `ag-grid-enterprise` / `ag-grid-react` are pinned
together at `^36.0.0` — the three packages MUST stay on the same version.

## Migration notes (MRT → DataGrid)

- MRT `columns` (`accessorKey`/`accessorFn`/`Cell`) map to AG Grid `columnDefs`
  (`field`/`valueGetter`/`cellRenderer`).
- Server-side pagination/filter/sort: use AG Grid's Server-Side Row Model
  (enterprise, already registered) or keep client fetch + `rowData` for small
  sets.
- Keep the existing contract mappers (`scantap-api.ts` etc.) — only the
  presentation layer changes.
- Excel/CSV export is built into enterprise (`api.exportDataAsExcel()`), which
  can replace bespoke `ExportModal`/`lib/excel` flows where the owner agrees.
