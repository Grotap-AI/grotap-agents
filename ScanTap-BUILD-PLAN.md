# ScanTap — Build Plan & Pipeline Dispatch

_Source spec: `C:\1Claude\ScanTap - RFID Inventory Management.md` (converted from PDF)._
_Authored 2026-06-17. Owner: info@grotap.com._

## Decision summary (from clarifying Q&A)

| Decision | Choice |
|---|---|
| Relationship to existing app | **Evolve the existing `rfid-pipe` app in place** into the full ScanTap spec (rename display → "ScanTap"). No duplicate app. |
| Mobile stack | **Expo, USB + BLE both** — USB via a custom Expo dev-client native module (usb-serial-for-android) on Android; BLE for iOS/"any phone". |
| SBI / Customer Inventory Software | **Stubbed** — clean integration interface + seed data; wire real SBI later. |
| Tag printing | **Stubbed** — generate EPCs + on-screen/PDF label preview; wire physical RFID printer later. |
| Scope this pass | **MVP first** — core loop end-to-end. |
| Database | **Grotap tenant DB** (`proud-union-74070434`), `rfid_pipe` schema (existing). |
| Mobile repo | **New repo `Grotap-AI/grotap-scantap-mobile`**. |
| Release path | **Staging first** — agents branch off and target `staging`; validate, then promote. |
| Dispatch | **Assign + dispatch immediately** (foundations first; dependents queued behind them). |

## What already exists (the foundation we're extending)

`rfid-pipe` app — beta, on grotap brand. Files:
- Schema: `platform/migrations/apps/rfid-pipe/v001_initial.sql` — `rfid_pipe` schema with `rfid_batch_templates`, `rfid_scan_sessions`, `rfid_scan_records`, `ignored_rfid_tags`, `rfid_audit_log` (all RLS tenant-isolated).
- Backend: `platform/backend/app/routers/rfid_pipe.py` — templates CRUD, scan sessions (sync from mobile via `POST /rfid/scans`), records, **Sum By** grouping, CSV export, ignore tags, audit log, demo seed. `rfid.py` = audit endpoints.
- Frontend: `platform/frontend/src/pages/RfidPipe{Dashboard,ScanList,ScanDetail,BatchTemplates}Page.tsx` + `rfid-pipe-api.ts` + `rfid-pipe-types.ts`; sidebar `components/RfidPipeAppSidebar.tsx`.
- Registration: `seed_apps.sql`, `seed_brands_apps.sql`, nav `frontend/src/config/appMenuConfig.ts`, routes in `frontend/src/App.tsx`.

## Gap = ScanTap spec − rfid-pipe

- **Print Tags** screen (from receiving/voucher + from manual quantities) — NEW.
- **Review & Apply**: product-ID drill level with full detail columns (Product ID, Description, size, category, type, Item Class, Income/Cost/Asset Account, Catalog ID, Customer Name), batch columns (#unique products, #locations), customer on batch, **Update pallet** (delete / set new / archive), **Create Order / Create Invoice**.
- **Compare to my Inventory** (AI) — NEW (Anthropic via `providers/`).
- **Customers / Orders / Invoices** + **Inventory** (SBI stub) — NEW.
- **Locations + geo reconcile** — NEW.
- **Inventory summary views** — NEW.
- **Mobile app (Expo)** — entirely NEW: Scan screen (live counts, GPS, distance, stopwatch, tags/min), Setup, CS463 USB+BLE, SQLite, keep-awake, beep, capture→cloud sync.

## Pipeline cases

Branch convention for all platform cases: **base + target `staging`**. Mobile cases: new repo `Grotap-AI/grotap-scantap-mobile`.

| # | Case | Repo | Wave | Depends |
|---|---|---|---|---|
| A | ScanTap FOUNDATION — schema additions + rebrand rfid-pipe→ScanTap + nav (Print Tags, Inventory) + `has_mobile` tile | platform | 1 | — |
| B | Backend APIs — Print Tags (stub), AI Compare to Inventory, Customers + Orders/Invoices (SBI stub), Locations/geo, product aggregation | platform | 2 | A |
| C | Frontend — Review & Apply enhancements, Print Tags page, Inventory views | platform | 2 | A, B |
| D | Mobile FOUNDATION — Expo app scaffold (new repo) + Scan screen + counts/GPS/stopwatch + SQLite + keep-awake + beep + Send-to-Cloud sync (reader simulated) | mobile | 1 | — |
| E | Mobile — CS463 reader integration (USB dev-client + BLE) + Setup screen + geo-per-tag strongest-read | mobile | 2 | D |
| F | Human Intervention — app won't open; diagnose & fix grid/approve/answer | platform | 1 | — |
| G | **Locations screen + Manorview Farms tenant** — `rfid_pipe.locations` migration (`v002_locations.sql`), Locations page (grid: Location Name, Zone, Site, GeoLocation Point 1–25 + detail cols, add/edit/delete, Excel/CSV export), backend Locations CRUD router, nav entry. Provision new Manorview Farms Neon tenant, run migrations, load 514 locations (`seed_manorview_locations.sql`), create user `info+Manorviewuser1@grotap.com` (password set at first login). | platform | 2 | A, B |

### Case G — Locations: confirmed mapping & artifacts (2026-06-19)
- **Field mapping** (SBI `tblICWarehouse` → ScanTap): Location Name←`strWarehouseID`, Zone←`strDivision`, Site←`strSite`, plus Type/Department/Address-block/COGS+Sales accounts/Directions/Notes/Sort/Active/source `cntID`. GeoLocation Point 1–25 are **not** in the source — stored as a `geo_points` JSONB array (≤25), seeded empty, filled by the mobile geo-mapping/scan flow. Full table in the spec doc.
- **Records:** all **514** from `rewholesale - tblICWarehouse.xls` (the superset of the 497-row file).
- **Manorview Farms** = its own **Neon tenant project** (database-per-tenant). Provision project → run `v001_initial.sql` + `v002_locations.sql` → load seed → register tenant in control plane → create the user.
- **Artifacts committed:**
  - `platform/migrations/apps/rfid-pipe/v002_locations.sql` — locations table (RLS, 25-geo-point CHECK).
  - `platform/scripts/scantap_load_locations.py` — regenerates the seed from the xls.
  - `platform/migrations/apps/rfid-pipe/seed_manorview_locations.sql` — 514-row idempotent seed; run with `psql "$MANORVIEW_DB_URL" -v tenant_id="<uuid>" -f …`.
- **Routing:** new tenant + control-plane registration is platform-level → **staging first** per CLAUDE.md, then promote. App-scoped Locations page/router can ship the app fast-path once the tenant exists.

**Wave 1 dispatched immediately:** A, D, F (no cross-dependencies; F is independent of ScanTap).
**Wave 2 (B, C, E, G):** created in the pipeline and released once their foundation merges to staging. G's schema + seed artifacts are pre-built (see above) so it reduces to: provision tenant → migrate+seed → build page/router → create user.

## Open items to wire later (post-MVP)
- Real SBI connection (vouchers, production work orders, customer sync, live inventory, count write-back).
- Physical RFID label printer (EPC encode).
- Field flows: planting (WO / no-WO), dumping, golf-cart drive-scan, dud-tag AI review.
- Mobile cobrowse; platform "mobile icon → open native app / store" deep-link.
- WiFi-assisted geolocation for ~1ft accuracy + location geo-mapping.
