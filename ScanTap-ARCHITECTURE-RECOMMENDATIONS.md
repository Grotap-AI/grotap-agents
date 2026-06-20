# ScanTap + Platform — Architecture Research & Recommendations

_Authored 2026-06-19. Owner: info@grotap.com. Scope: what we have, what's best (cited), what to do._
_Inputs: codebase audit (provisioning + rfid-pipe state) + external best-practice research (Neon multi-tenancy, PostGIS/GPS, offline sync, RFID reconciliation)._

## TL;DR

1. **Our database-per-tenant model is correct** — it's literally Neon's recommended pattern, and mostly-idle nursery tenants cost almost nothing (idle = storage only). Keep it.
2. **But the automation that makes it usable is broken in two places**, so onboarding a tenant (like Manorview Farms) is currently a *manual psql job*. Fixing those two links is the single highest-leverage work for "a system that runs well in the future."
3. **The Locations geo design I first committed (JSONB points + future Python haversine) should change to PostGIS** (polygon geofences + GiST + `ST_Contains`/`ST_DWithin`). Neon supports PostGIS natively. This is the defensible architecture for "which field is this scan in?"
4. **"Within 1 foot" GPS is not achievable** on a phone (~5 m reality). Design geofences and a confirm/override UI around ~5 m, or budget for RTK hardware.
5. **Mobile sync is the easy part** for append-only scans: SQLite outbox + per-row client UUID + `ON CONFLICT DO NOTHING`. No CRDT/sync framework needed.
6. **Reconciliation must assume imperfect reads** (RFID read rates 30–95%): three-bucket delta, dedupe by EPC, never auto-adjust the book — recount before write-back.

---

## A. What we have (codebase audit)

### Provisioning pipeline — db-per-tenant, automated except two broken links
- **Tenant creation is automated** via 3 entry points (`POST /tenants/provision`, WorkOS `organization.created` webhook, lazy login-callback), all calling `neon.create_tenant_project → run_tenant_migration → control_plane.create_tenant`. Base schema = `backend/migrations/tenant_template.sql`.
- **Control plane** (`green-rice-76766370`) holds `tenants` (incl. `neon_database_url` **in plaintext**), `apps`, `tenant_app_subscriptions`, `app_schema_migrations`, `approved_users`.
- **🔴 Broken link #1 — subscribe never provisions app schema.** `app_registry.subscribe_app` does the subscription row + Stripe + WorkOS feature grant but **never fires the `app/subscribed` Inngest event**. The `appSchemaProvision.ts` worker that would run `migrations/apps/<slug>/*.sql` into the tenant DB is therefore **dead code**. App schemas (incl. `rfid_pipe.*`) only exist where someone ran SQL **by hand** — which is exactly why our ScanTap scripts apply migrations manually to `proud-union-74070434`.
- **🔴 Broken link #2 — RLS is decorative.** Every app table has `USING (tenant_id = current_setting('app.current_tenant_id')::uuid)`, but **nothing in the backend ever sets that GUC**. Isolation today rests entirely on (a) the db-per-tenant boundary and (b) explicit `WHERE tenant_id = $1` in queries. The RLS policies enforce nothing.
- Other flagged gaps: WorkOS webhook signature **unverified**; connection strings **unencrypted**; in-process pool cache (no Redis coordination, no eviction); two competing app catalogs (`apps.py` legacy hardcoded vs `app_registry.py` DB-backed); user approval is a manual admin action; WorkOS Directory Sync not implemented.

### ScanTap / rfid-pipe — working scan pipeline, geo is greenfield
- Backend: templates/sessions/records/sum-by/CSV/ignore/audit. Mobile sync via `POST /rfid/scans`; every per-tag attribute lives untyped in `rfid_scan_records.data` (JSONB). **No geo logic anywhere.**
- Schema: `v001` + my new `v002_locations.sql` (`rfid_pipe.locations`, `geo_points` JSONB ≤25, currently empty). `rfid_scan_records` has **no `location_id`, no per-tag geo**.
- Frontend: 4 hand-rolled `<table>` pages (not Mantine React Table as the spec assumes). **No Locations screen, no map, no locations API client.**
- **Two copies of the frontend**: `frontend/src/pages/RfidPipe*` and `platform/apps/rfid-pipe/src/` — consolidate before building more.
- Mobile: `grotap-scantap-mobile` does **not exist yet**; the existing `mobile/` is the platform app. The whole GPS-capture leg is unbuilt.
- Naming mismatch: build-plan/spec say `scantap_locations`; I built `rfid_pipe.locations`. Align before backend case B.

---

## B. What's best (researched, cited)

### Neon multi-tenancy — keep project-per-tenant
- Neon **explicitly recommends one project per tenant** (full isolation, no noisy neighbor, per-tenant PITR, scale-to-zero). Schema-per-tenant is discouraged; shared+RLS only for the simplest early cases. (neon.com/docs/guides/multitenancy)
- **Economics:** idle suspended projects cost **$0 compute**, storage only ($0.35/GB-mo). Mostly-idle nursery tenants are near-free. (neon.com/pricing)
- **Ceiling:** Scale plan soft cap **1,000 projects** (raise via support); first real scaling conversation. Autosuspend default 5 min; cold start "a few hundred ms" (no published tail).
- **The work at scale is the control plane** (automated API provisioning + connection routing/pooling), not the data model — which is exactly our two broken links.

### Geo modeling — PostGIS, not JSONB+haversine
- The real question is **point-in-polygon** ("which field?") = `ST_Contains`/`ST_Intersects`; nearest-fallback = `ST_DWithin`. Haversine only does point-to-point distance and **doesn't solve containment**. (postgis.net)
- **Neon supports PostGIS** (`CREATE EXTENSION postgis;`). Use `geography(Polygon,4326)` (GPS-native, meters), GiST index. At ~500 polygons it's instant and future-proof.
- **GPS accuracy reality:** phone GPS ~**5 m** open-sky (gps.gov: 4.9 m), 10–20 m under canopy. **"Within 1 foot" needs RTK (1–3 cm) hardware** — not a phone. Fields <~10 m apart can't be disambiguated by GPS alone → need confirm/override UI or padded geofences.

### Offline-first mobile sync — append-only, simple
- `expo-sqlite` outbox table; flush on `netinfo` reconnect.
- **Per-scan `client_uuid` (UUIDv4)** + server `UNIQUE(client_uuid)` + `INSERT … ON CONFLICT DO NOTHING` = exactly-once over an at-least-once network. No CRDT/LWW needed (scans are immutable).

### RFID reconciliation — assume imperfect reads
- Reconcile on **unique EPC/SGTIN** (GS1), not SKU quantity.
- **Three buckets:** found / missing (in book, unread) / unexpected (read, not in book) → exception report.
- Dedupe duplicate reads per EPC; filter strays by RSSI floor + read-count; **read rates 30–95%** (metal/liquid/stacked worst) → **recount before adjusting the book**. Never auto-write counts.

---

## C. What we should do (prioritized roadmap)

### P0 — Make the platform actually run itself (highest leverage)
These turn every future customer onboarding (Manorview included) from a manual psql job into one automated flow.
1. **Fix subscribe → provision.** Make `app_registry.subscribe_app` fire `inngest.send_event("app/subscribed", {tenant_id, app_slug, neon_project_id})` so `appSchemaProvision.ts` runs the app's `migrations/apps/<slug>/*.sql` into the tenant DB and records `app_schema_migrations`. Add an admin "re-provision app schema" button for backfills.
2. **Make RLS real, or drop it.** Either set `app.current_tenant_id` on every acquired tenant connection (asyncpg pool `setup` callback / `SET LOCAL` per txn) so policies enforce, **or** delete the RLS policies and document that isolation = db-per-tenant + `WHERE tenant_id`. Pick one; don't ship decorative security.
3. **Encrypt `tenants.neon_database_url` at rest** and **verify the WorkOS webhook signature**.

### P1 — ScanTap geo done right
4. **Switch Locations geo to PostGIS.** Enable `postgis` in tenant DBs; add `boundary geography(Polygon,4326)` + GiST index to `rfid_pipe.locations`, derived from the editable boundary points (keep `geo_points` JSONB as the human-editable vertex list, ≤25; build the polygon from it). Update `v002` accordingly.
5. **Add the reconcile leg to the data model:** `rfid_scan_records.location_id` FK + per-tag `geo_lat/geo_lng/signal_strength`; session `unique_locations`/`unique_products` counts. New endpoint `POST /rfid/scans/{id}/reconcile-locations` → `ST_Contains` then `ST_DWithin` fallback, with a **confidence/needs-confirmation flag** when GPS is ambiguous (~5 m).
6. **Set realistic accuracy expectations in the UI** (no "1 foot"); add confirm/override for boundary-ambiguous scans. Decide if RTK hardware is ever in scope.
7. **Consolidate the two rfid-pipe frontends** and standardize on Mantine React Table before building the Locations/map screen. Resolve the `scantap_locations` vs `rfid_pipe.locations` naming.

### P2 — Mobile + reconciliation quality
8. Build `grotap-scantap-mobile` (Expo) with the SQLite outbox + `client_uuid` + `ON CONFLICT DO NOTHING` sync contract; capture strongest-signal GPS per EPC.
9. Implement three-bucket reconciliation + EPC dedupe + RSSI/read-count stray filtering; **exception report, recount-before-adjust**, never auto-write to the system of record.

### Manorview Farms — recommended sequencing
Onboard Manorview **through the P0-fixed flow**, not by hand: provision its Neon project → subscribe to ScanTap fires schema provisioning (`v001`+`v002`) → run `seed_manorview_locations.sql` (514 rows) → approve/create `info+Manorviewuser1@grotap.com`. Because tenant + control-plane changes are platform-level, do P0 + the Manorview cutover on **staging first**, then promote (per CLAUDE.md routing).

---

## Status — landed 2026-06-19 (branch `feature/provisioning-p0-postgis`)
- ✅ **D1** — `subscribe_app` now fires `app/subscribed`; `seed_app_schemas.sql` registers `db_schema`+`migrations[]`; worker rfid-pipe migrations synced/canonical. App schemas now auto-provision on subscribe.
- ✅ **D2** — `v002_locations.sql` reworked to PostGIS (`boundary geography(Polygon,4326)` from `geo_points` via trigger, GiST index). Validated on a Neon branch (polygon build + point-in-polygon correct).
- 🟡 **D3** — GUC `app.current_tenant_id` now set per tenant connection (the missing half). **Full enforcement still needs `FORCE ROW LEVEL SECURITY` or a non-owner app role** (Neon's default owner role bypasses RLS) — staging follow-up.
- ⏳ Not started: connection-string encryption, WorkOS webhook signature, reconcile endpoint + `location_id` on records (P1 #5), frontend Locations page, mobile.

Pushed to a feature branch only — **prod (master) untouched**. Promote via staging per CLAUDE.md.

## Decisions needed from you
- **D1:** Do P0 (provisioning fixes) **before** onboarding Manorview, so Manorview is the first clean automated onboarding? (Recommended.) Or hand-provision Manorview now and fix automation later?
- **D2:** Adopt **PostGIS** for Locations geo (update `v002`)? (Recommended.)
- **D3:** RLS — **make it enforce** (set the GUC) or **remove the policies** and rely on db-per-tenant + `WHERE tenant_id`?
- **D4:** Is RTK/sub-meter ever in scope, or do we design entirely around ~5 m GPS + confirm/override?
