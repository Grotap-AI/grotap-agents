# Scan M Live Position (LPOS) — cm-accurate position per RFID scan: RTK live + PPK fallback

*Plan of record. Drafted 2026-09-13 from the owner document "Centimeter Accuracy on Tablet - Post processing for
Free" and the owner's follow-up answers. Filing side: `platform/scripts/scan_m_live_position_cases.py` (dry-run by
default; `--file` POSTs). Status: DRAFT — not filed, nothing committed, no migration applied.*

## 1. Owner decisions of record (2026-09-13)

1. Run **Route A and Route B**. Route A = our own RTK base station on the property plus a rover receiver on the
   cart, giving centimetre positions in real time. Route B = the rover also logs raw GNSS observations and a nightly
   (actually every-30-minutes) post-processed kinematic (PPK) run against free NOAA CORS data fills in wherever the
   live fix was lost or never fixed. **Real time first**; PPK is the fallback, never the plan.
2. **Any tablet must work**: the Samsung SM-X930 Tab S11 Ultra 11" and the Xenarc RT71-FHD 7". The tablet's own
   GNSS is never the source of the cm position; an external receiver is.
3. **No WiFi and no hotspot in the field.** Base-to-rover corrections travel by radio (base radio -> rover radio ->
   receiver). The tablet never relays RTCM and never needs a network connection for the live fix.
   **Amended 2026-09-14 by the owner doc "RTK Devices and Services Integration"** (section 11): the tablet MAY have
   a cell link (Verizon) and MAY act as the NTRIP client for a third-party correction service (rtkdata.com) or for
   our own base published through a caster. Radio stays the offline option; it is no longer the only one.
   **Amended again 2026-09-14 by owner answer Q9** (section 11.6): the cell link is the **tablet's own Verizon
   band 13 modem** — no phone hotspot and no Jetpack in the cart. Choosing that tablet is open owner action 5.
4. **Base site = the office, on mains power** (owner 2026-09-14). Remaining owner check on site: open sky and a ~3 m radio mast with line of sight to the fields; tracked in section 9. The runbook (LPOS-5) tells the
   owner how to choose; it does not choose for them.
5. The receiver is an **optional add-on SKU** in the Scan M kit BOM: "Live Position add-on — instant live accurate
   locations of your scans". It is a separate kit entry with two variants (Budget ≈ $850, Robust ≈ $1,390 — section
   4a); the existing kit rows are owned by another session.
6. The feature is **per-tenant configurable from the Scan M Platform web app**: enable/disable, which correction
   source (own base over radio, or a public/state NTRIP caster), which post-processing source (NOAA CORS stations).
   Ohio (ODOT RTN) and Florida (FPRN) tenants have free state NTRIP casters; Maryland has none, so Manor View runs its
   own base — the config model must hold both shapes.
7. The owner wants the **TAG position at cm**. Verified physics say one UHF read localizes a tag to metres and
   multi-read phase methods reach roughly 6–15 cm outdoors. Tag-position work is therefore a **gated research spike
   (LPOS-6)** after the antenna-position work ships, and every promise in the UI is about the antenna/cart position
   until that spike reports.
8. This decision **supersedes** coverage-program owner decision 4 ("No RTK receiver now",
   `platform/scripts/scan_coverage_cases.py:104`). The coverage engine's `SNAP_RADIUS_M = 25.0` (sized for the
   ±21 m tablet GNSS, `backend/app/services/scan_coverage.py:42`) stays as the fallback radius; an RTK-fixed sample
   should snap within its reported accuracy instead. That tightening is a one-line follow-up in COV, not an LPOS case.

## 2. Verified facts (baked in; do not re-research)

- Tablet GNSS is L1-only, bench ±21 m, no raw-measurement access on either tablet — **no in-tablet PPK**. Position
  must come from an external receiver: u-blox ZED-F9P class, NMEA out over USB-OTG serial or Bluetooth SPP, and raw
  UBX `RXM-RAWX` + `RXM-SFRBX` at 1 Hz on the same stream for PPK.
- NOAA CORS free RINEX: hourly `.o.gz` (RINEX 2.11, native rate) at
  `https://noaa-cors-pds.s3.amazonaws.com/rinex/YYYY/DDD/ssss/`, kept about **2 days**, latency ≤ 60 min. Daily files
  are decimated to 30 s after 30 days (useless for 1 Hz kinematic). Nearest to Manor View: **BACO** (20 km, 5 s,
  GPS+GLO+GAL), **UMBC** (37 km, 1 s, GPS+GLO), **YORK** (46 km, 1 s). Use the `.o.gz`, never `.d.gz` (Hatanaka) or
  `.S` (summary).
- PPK engine: RTKLIB `convbin` (UBX -> RINEX) + `rnx2rtkp` kinematic; Linux CLI, Docker-able. The `.pos` output
  carries per-epoch quality Q=1 fixed, Q=2 float.
- Base coordinate: log 2–4 h static once; upload to NOAA OPUS (static only, GPS-only, antenna type NONE is
  acceptable) or NRCan CSRS-PPP; enter the result as the fixed base position. **Manual runbook, not automated.**
- RFID radio: CS463 + CS776 transmit 902–928 MHz at up to 30 dBm. A GNSS antenna and its LNA need physical
  separation from that (≥ 3 m in the runbook), and a 915 MHz ISM data radio for RTCM sits in the SAME band — see
  risk R1.

### Existing code (measured 2026-09-13; paths relative to the `grotap-platform` repo root)

The Scan M tablet app is `platform/mobile/scantap/` (the repo-root `mobile/` has no `scantap`).

| Area | Where | What it is today |
|---|---|---|
| GPS watch | `platform/mobile/scantap/app/(tabs)/scan.tsx:992-1007` | 1 Hz `Location.watchPositionAsync` (BestForNavigation, `distanceInterval: 0`, `timeInterval: 1000`) writes `lastPosStore.current` (line 175) |
| Per-read stamp | `services/CaptureEngine.ts:747-783` | `ingest(tag)` reads `this.getPos()` and stamps lat/lng/hdg/spd per read; best-geo per EPC by RSSI |
| Upload sample | `services/syncPayload.ts:62-76` | `LocationSample = {lat,lng,rssi,ant,at,hdg?,spd?}`, capped at `LOCATION_SAMPLES_CAP = 60` strongest (line 54) — "cloud contract, field names must not drift" |
| Local store | `db/database.ts:100-130` | `tag_records(geo_lat, geo_lng, signal_strength, scanned_at, …)` |
| API client | `services/api.ts` | the tablet does NOT read `/scantap/config` today; reader settings are device-local (`services/readerConfig.ts`); the only unauthenticated call is `POST /scan-m/devices/pair` (line 865+) |
| Tag event | `services/ReaderService.ts:57-72` | `TagEvent {epc, rssi, timestamp, readerTimestamp?, antenna?}` — no phase field |
| Tenant config | `backend/app/routers/scantap.py:2860-2957` | `GET /scantap/config`, `GET/PUT /scantap/config/{name}`, `POST /scantap/config` (`scantap.scantap_config`, tenant v006) |
| Scan insert | `backend/app/routers/scantap_core.py:1175-1200` | `INSERT INTO scantap.rfid_scan_records (… data JSONB, geo_lat, geo_lng, signal_strength …)`; `data.location_samples` |
| Tag position | `backend/app/services/tag_locations.py` | `method` ∈ `single_fix` / `rssi_weighted_centroid` / `rssi_weighted_offset` (lines 82-84), `accuracy_m`; tenant `tag_locations` (v031, PostGIS geography, `method TEXT NOT NULL` with **no CHECK**, so `'rtk'` / `'ppk'` are additive) |
| Coverage | `backend/app/services/scan_coverage.py:42` | `SNAP_RADIUS_M = 25.0` |
| Positioning precedent | `backend/db/migrations/control_plane/v099_skyview_kits.sql:132-185` | `skyview_positioning_configs(method none/ntrip/base_station/ppp, ntrip_*, ntrip_password_enc Fernet, base_lat/base_lon/base_height_m, base_transport radio/caster/ntrip_server)`; routes `backend/app/routers/skyview_support.py:679-870` (`GET /positioning/presets`, `GET/PUT /positioning`, `DELETE /positioning/{number}`), Fernet via `backend/app/utils/encryption.py encrypt_secret/decrypt_secret`; UI `frontend/src/pages/skyview/SkyViewPositioningPage.tsx` (537 lines) |
| Web config | `frontend/src/pages/ScanTapConfigPage.tsx`, menu `frontend/src/config/appMenuConfig.ts:94` ("Sync Setup" -> `/scantap/config`), client `frontend/src/pages/scantap-api.ts` | |
| Kit BOM | `frontend/src/pages/scan-m/scan-m-kits.ts` | one kit today (`tablet_cs463`); `RfidKitId` union at line 24 |
| Migrations | `migrations/apps/scantap/` (head v038) MIRRORED to `ingestion-worker/migrations/apps/scantap/`; each tenant file needs a control-plane manifest per `backend/db/migrations/control_plane/v172_scantap_v038_manifest.sql`; control-plane head on disk v179 | |

**Reserved by peers**: tenant scantap v039–v043 (SIV v039, CAD v040/v041, SZC v042/v043), control-plane v179–v184.
**LPOS takes tenant v044, v045, v046 and control-plane v185, v186, v187, v188.** Re-check `ls … | tail` before writing.

## 3. Architecture

```
  ┌──────────── BASE (fixed, on the property) ────────────┐
  │ ZED-F9P base  ──RTCM3──▶ 900 MHz / 400 MHz data radio │   OPUS / CSRS-PPP once
  │ (fixed coord from OPUS/CSRS-PPP, entered in platform) │   (manual runbook, LPOS-5)
  └───────────────────────────────┬───────────────────────┘
                                  │ radio link (no WiFi, no tablet relay)
  ┌──────────── CART ────────────▼─────────────────────────────────────────────┐
  │ rover radio ──RTCM3──▶ ZED-F9P rover ──NMEA GGA/RMC/GST + UBX RAWX/SFRBX──▶ │
  │                                       USB-OTG serial (preferred) / BT SPP   │
  │   tablet (SM-X930 or RT71):                                                 │
  │     PositionProvider  ← external RTK fix (quality 4/5/2/1) │ expo-location  │
  │     CaptureEngine.ingest(tag) reads lastPos as today  → tag_records + src   │
  │     GnssRawLogger → <session_id>.ubx (LPOS-3)                               │
  │     scan pill: FIXED / FLOAT / NO RTK / TABLET · sats · corr. age           │
  └────────────┬─────────────────────────────────────────┬──────────────────────┘
               │ POST /scantap/scans (+ fix_source, src)  │ POST /scantap/gnss-logs → R2 presigned PUT
  ┌────────────▼────── BACKEND (FastAPI, Railway) ───────▼──────────────────────┐
  │ scantap.positioning_configs (v044)  · GET/PUT /scantap/positioning          │
  │ GET /scantap/positioning/device (device token, non-secret subset)           │
  │ rfid_scan_records.fix_source + data.location_samples[].src/.acc (v045)      │
  │ scantap.gnss_raw_logs (v046)  · tag_locations.method += rtk | ppk           │
  └────────────┬────────────────────────────────────────────────────────────────┘
               │ every 30 min: queued logs with ended_at ≥ 90 min old
  ┌────────────▼────── PPK WORKER (Docker: RTKLIB convbin + rnx2rtkp) ──────────┐
  │ fetch hourly base .o.gz + nav from noaa-cors-pds for ppk_stations           │
  │ convbin UBX→RINEX · rnx2rtkp kinematic · parse .pos (Q=1 fixed, Q=2 float)  │
  │ time-match epochs to location_samples[].at (≤1 s) → samples[].ppk={…}       │
  │ recompute tag_locations where live sample was not rtk_fixed (method 'ppk')  │
  │ mark log processed {fix_ratio, baseline_km, station}; missed window → failed│
  └─────────────────────────────────────────────────────────────────────────────┘
```

Data-flow rules:
- The receiver is the only cm source. The tablet's `PositionProvider` prefers the external fix whenever the stream is
  alive (last sentence < 3 s old) and falls back to expo-location; `CaptureEngine.ingest(tag)` keeps its signature and
  keeps reading `lastPos` — the provider swaps what `lastPos` holds.
- Every uploaded sample says where it came from (`src`) and how good it was (`acc`). PPK never overwrites a live
  value; it adds `ppk` alongside and `tag_locations` is recomputed only where the live sample was not `rtk_fixed`.
- Secrets (NTRIP password) are Fernet ciphertext in the tenant table, revealed to staff only, and never sent to the
  tablet — the tablet gets radio corrections, so it never needs them; an NTRIP tenant's rover receives corrections
  from its own field modem, again not through the tablet (decision 3).

## 4. Cases

All cases: `touch_surface: scantap`, severity P2, one shared branch `feat/scantap-live-position`, sequential;
`case_data.human_breakdown=true` on every child so autopilot does not auto-split. Turn budgets per `platform/CLAUDE.md`:
simple 20 / medium 40 / complex 80.

### LPOS-0 root / leader (container, P2)
Holds the owner decisions above; children link by `metadata.root_case_id`. `human_breakdown=true`. Not dispatched.

### LPOS-1 Tenant positioning config + platform UI — medium
- **Migrations**: tenant `migrations/apps/scantap/v044_positioning_config.sql` (+ identical mirror in
  `ingestion-worker/migrations/apps/scantap/`) creates `scantap.positioning_configs` — one row per tenant:
  `enabled BOOL DEFAULT false`, `method CHECK IN ('none','own_base','ntrip','ppk_only') DEFAULT 'none'`,
  `correction_transport CHECK IN ('radio','ntrip') DEFAULT 'radio'`, `ntrip_host, ntrip_port, ntrip_mountpoint,
  ntrip_username, ntrip_password_enc` (Fernet), `base_lat, base_lng, base_hgt_m`, `base_coord_source CHECK IN
  ('opus','csrs','manual')`, `base_antenna TEXT`, `ppk_enabled BOOL DEFAULT false`, `ppk_stations TEXT[] DEFAULT
  '{UMBC,BACO}'`, `ppk_archive_url_template TEXT DEFAULT 'https://noaa-cors-pds.s3.amazonaws.com/rinex/{yyyy}/{ddd}/{ssss}/'`,
  `ppk_always_upload BOOL DEFAULT false`, `updated_by, created_at, updated_at`; FORCE RLS like every scantap table.
  Control-plane `v185_scantap_v044_manifest.sql` (v172 pattern) and `v186_gnss_caster_catalog.sql` — a seed table
  `gnss_correction_sources(id, kind caster|archive, name, region, host, port, url_template, auth_required, notes)`
  with NOAA CORS S3 archive, Ohio ODOT RTN, Florida FPRN, Emlid Caster, RTK2Go, for the dropdown.
- **Backend**: `GET/PUT /scantap/positioning` (tenant JWT; staff or tenant admin; password write-only, response says
  only `ntrip_password_set`; staff-only `GET /scantap/positioning/reveal` like SkyView), `GET /scantap/positioning/sources`
  (catalog), and tablet-facing `GET /scantap/positioning/device` (device token via `DEVICE_TOKEN_ALLOWED_ROUTES`;
  returns `{enabled, method, correction_transport, ppk_enabled, ppk_always_upload, base:{lat,lng,hgt_m} or null}` —
  never the NTRIP credentials). Missing table (tenant not yet migrated) → `enabled:false`, never a 500.
- **Frontend**: "Live Position" page `/scantap/live-position` (menu entry under ScanTap next to "Sync Setup",
  `appMenuConfig.ts:94`), form layout lifted from `SkyViewPositioningPage.tsx` (method radio → conditional sections),
  catalog dropdown, base coordinate block with source, PPK block (station multi-select, always-upload toggle).
- **Acceptance**: pytest (mocked pool): PUT round-trips every field, password never returned, reveal is staff-only
  (403 otherwise), device route returns the non-secret subset and `enabled:false` when the table is absent, RLS keeps
  tenants apart; migration applies twice on a scratch schema; vitest for the page (method switch shows/hides
  sections; save posts the body); `tsc` + `py_compile` clean. PR states the owner apply command
  (`scripts/tenant_sql.py --owner -f … --ledger scantap:v044`) and that v044 references no v036–v043 object.
- Warning to encode: `encrypt_secret()` in `backend/app/utils/encryption.py` stores PLAINTEXT when the key is unset
  (memory 2026-09-06) — the PUT must refuse to store a password when the key is missing (503), not fall through.

### LPOS-2 Tablet external GNSS input + live fix source — complex
- **Transport**: USB-OTG serial (`@serserm/react-native-turbo-serialport` or an Expo-compatible equivalent — must build
  with Expo 52 / RN 0.76.5 and a config plugin, no bare-workflow eject) and Bluetooth SPP
  (`react-native-bluetooth-classic`); a `services/gnss/GnssTransport.ts` interface with both implementations plus a
  simulated one for jest. USB-OTG is the recommended default (risk R3).
- **One app owns the USB CDC port.** Android hands the F9P's CDC device to exactly one app, so our app must do the
  mock-location-equivalent fix AND the raw logging itself on that one stream; GNSS Master / SW Maps are bench-only
  interim tools for checking the receiver and must not be running in the field alongside ScanTap.
- **Parser**: `services/gnss/nmea.ts` — GGA (fix quality 4 = RTK fixed, 5 = float, 2 = DGPS, 1 = GPS, 0 = none;
  sats; hdop; age of corrections), RMC (course, speed), GST (σ lat/σ lon → `accuracy_m` = RMS); checksum-validated;
  tolerant of interleaved binary UBX bytes on the same stream.
- **PositionProvider** (`services/gnss/PositionProvider.ts`): emits the fix shape `{lat,lng,accuracy_m,heading,speed}`
  plus additive `fix_source`, `sats`, `corr_age_s`; prefers the external fix while fresh (<3 s), else expo-location;
  writes `lastPosStore.current` in the same `LocationObject` shape so `CaptureEngine.ingest(tag)` and `getPos()` are
  untouched. `LocationSample` gains optional `src` ('tablet'|'rtk_fixed'|'rtk_float'|'dgps'|'ppk_fixed'|'ppk_float')
  and `acc` (metres). `tag_records` gains `fix_source TEXT`, `fix_accuracy_m REAL` (additive SQLite migration step).
- **UI**: scan screen status pill FIXED / FLOAT / NO RTK / TABLET with sats + correction age; Setup section
  "Live Position": transport picker (USB / Bluetooth / off), device picker, live sentence counter. Tablet fetches
  `GET /scantap/positioning/device` once per app open, caches it in SQLite (first time the tablet reads tenant config),
  and hides the section when `enabled:false`.
- **Backend (additive)**: tenant `v045_fix_source.sql` — `rfid_scan_records.fix_source TEXT`, `rfid_scan_sessions.fix_source_summary JSONB`
  (+ mirror + control-plane `v187_scantap_v045_manifest.sql`); `scantap_core.py` scan insert accepts and stores
  `fix_source` and passes `location_samples[].src/.acc` through untouched; `tag_locations.py` maps
  `src='rtk_fixed'` samples to `method='rtk'` with `accuracy_m` from `acc` (RTK-fixed samples dominate the estimate;
  tablet samples keep the existing RSSI-weighted path).
- **Acceptance**: jest — parser fixtures for GGA q=4/5/2/1/0, GST σ → acc, checksum failure dropped, UBX bytes
  interleaved; provider prefers fresh external fix and falls back after 3 s; `CaptureEngine.test.ts` still green
  unchanged; `syncPayload.test.ts` proves `src`/`acc` ride along and the 60-sample cap still holds; pytest — insert
  with and without `fix_source` (old tablets), `tag_locations` picks `method='rtk'` for fixed samples; existing
  tests green (CI-1's 11 red tests listed as pre-existing). `app.json` bump per convention after re-checking
  origin/master. No release from the agent.

### LPOS-3 Raw GNSS logging + upload — medium
- On connect, when the tenant config has `ppk_enabled`, send UBX `CFG-VALSET` (RAM layer) enabling `RXM-RAWX` and
  `RXM-SFRBX` at 1 Hz on the connected port alongside NMEA; verify by the first RAWX frame within 5 s, else show
  "raw logging unavailable" and continue live-only.
- `services/gnss/GnssRawLogger.ts` writes `<session_id>.ubx` under app storage during an open scan session (append,
  fsync every 5 s, size cap 200 MB/session, retention 7 days or until `processed`).
- On session close the sync queue enqueues kind `gnss_log`: `POST /scantap/gnss-logs` (device token) with
  `{scan_session_id, started_at, ended_at, bytes, sha256, fix_summary}` → backend issues an R2 presigned PUT
  (`backend/app/providers/r2_provider.py`, new bucket prefix `scantap/gnss/<tenant>/<session>.ubx`) and inserts tenant
  `scantap.gnss_raw_logs(log_id, scan_session_id, r2_key, started_at, ended_at, bytes, sha256, status CHECK IN
  ('queued','processing','processed','failed','skipped') DEFAULT 'queued', result JSONB, created_at, updated_at)`
  (tenant `v046_gnss_raw_logs.sql` + mirror + control-plane `v188_scantap_v046_manifest.sql`); tablet PUTs the file,
  then `POST /scantap/gnss-logs/{log_id}/complete`. Skip the upload (status `skipped`, reason) when every sample in
  the session was `rtk_fixed` unless `ppk_always_upload`.
- **Acceptance**: jest — logger opens/appends/closes per session, cap enforced, skip rule; pytest — presign + row,
  complete flips bytes/sha, RLS; the `.ubx` fixture (a few hundred RAWX frames) is checked into `test/__fixtures__/gnss/`
  for LPOS-4.

### LPOS-4 PPK post-processing worker — complex
- **Where it runs (decision)**: a Dockerised job (`platform/workers/ppk/Dockerfile`: RTKLIB `convbin` + `rnx2rtkp`
  built from source, Python runner `ppk_worker.py`) scheduled every 30 min by cron on **agent-06** (the ops box whose
  crons already must always run; it has Doppler and reaches Neon) — NOT in `ingestion-worker`, which is a Node/Inngest
  service with no RTKLIB and would have to carry a 100 MB binary image for one job. Fallback if agent-06 is retired: a
  Railway cron service from the same image. State in the PR.
- **Loop**: for each tenant with `ppk_enabled`, for each `queued` log with `ended_at` ≥ 90 min old: for the covering
  UTC hours fetch `ssss DDD h.YYo.gz` + broadcast nav from `ppk_archive_url_template` for the first station in
  `ppk_stations` that has ALL hours (else next station); `convbin` the UBX; `rnx2rtkp -p 2 (kinematic) -f 2 (L1+L2)
  -m 15 -c` with the base station's published coordinate from the RINEX header; parse `.pos`; time-match epochs to
  `location_samples[].at` (nearest ≤ 1 s); write `location_samples[].ppk = {lat,lng,acc,q}`; where the live sample
  was not `rtk_fixed`, recompute `tag_locations` with `method='ppk'` and `fix_source='ppk_fixed'|'ppk_float'`; mark
  the log `processed` with `result = {fix_ratio, float_ratio, baseline_km, station, epochs, hours}`.
- **Missed window**: hourly files expire ~2 days after the hour; a log whose hours are gone on every station goes
  `failed` with `result.reason='cors_window_missed'` and one WARN log line. **No HI hold** (PRODUCT FREEZE: a run summary
  is a log, not a hold). BACO is 5 s — with a 1 Hz rover the engine interpolates; prefer UMBC (1 s) when both exist,
  which the default `{BACO,UMBC}` ordering must reflect — set the default to `{UMBC,BACO}` in LPOS-1 and say so.
- **Acceptance**: pytest with fixture `.ubx` (from LPOS-3) + fixture RINEX obs/nav hours (checked in, gzip): convert
  runs, `.pos` parses, matching assigns ≤ 1 s, samples gain `ppk`, only non-fixed samples trigger recompute, station
  fallback when hour missing, window-missed → failed with reason, idempotent re-run leaves processed logs alone;
  `docker build` succeeds in CI (or is documented as a manual step if CI has no Docker).

### LPOS-5 Base station kit, BOM SKU, install runbook — medium
- `frontend/src/pages/scan-m/scan-m-kits.ts`: new kit id `live_position_addon` ("Live Position add-on — instant live
  accurate locations of your scans") with TWO variants, Budget and Robust, carrying the concrete BOM of section 4a
  (part, role, vendor, price, URL, Amazon Y/N) and the radio decision (XBee 3 PRO 2.4 GHz pair); no edit to existing
  rows (another session owns print-related BOM rows).
- `docs/scantap/live-position-base-runbook.md`: siting (open sky, away from metal roofs); **GNSS antenna placement on
  the cart** — ≥ 1.5–2 m from the CS776, above and behind it (outside its 70° beam), and verify C/N0 in u-center with
  the reader ON vs OFF before fixing the mount; **base TMODE3**: survey-in only on day one to get a first coordinate,
  then FIXED coordinate from OPUS/CSRS-PPP (survey-in re-derives an origin 1–2 m different at every power-up and
  would shift every tag between days); **RTCM3 output** 1005/1074/1084/1094/1124/1230 at 1 Hz on UART2; **radio**:
  XBee 3 PRO 802.15.4 transparent AT mode, channel 25 or 26 (clear of tablet Wi-Fi), 115200 baud, paired DH/DL,
  base radio antenna at ~3 m elevation; power options; 2–4 h static log; OPUS / CSRS-PPP upload; entering the fixed
  coordinate in `/scantap/live-position` and in the base receiver; daily start checklist (FIXED pill before scanning;
  correction age < 5 s).
- **Acceptance**: `tsc` clean, kit page renders both variants with the listed prices and totals, runbook reviewed by
  the owner.

### 4a. Hardware — Live Position add-on kit (buy-list researched 2026-09-13)

Prices as captured 2026-09-13. ArduSimple prices are EUR; USD shown at ≈ €1 = $1.25 — confirm at checkout; ships DHL
from Spain in 2–5 days. Amazon column: Y = buyable on amazon.com today, N = vendor direct.

**Budget kit — two simpleRTK2B (ZED-F9P), patch antennas, XBee 3 PRO 2.4 GHz link**

| Part | Role | Vendor | Price | URL | Amazon |
|---|---|---|---|---|---|
| 2× simpleRTK2B Budget (ZED-F9P, XBee socket) | base + rover receivers | ArduSimple | €172 ea → ≈ $430 | https://www.ardusimple.com/product/simplertk2b/ | N |
| 2× u-blox ANN-MB-00 IP67, 5 m SMA | GNSS antennas (L1/L2) | ArduSimple | €53.80 ea → ≈ $134.50 | https://www.ardusimple.com/product/ann-mb-00-ip67/ | N (B0GG6C7V48 unavailable) |
| 2× ground plate | mandatory under ANN-MB-00 | ArduSimple | €8.20 ea → ≈ $20.50 | https://www.ardusimple.com/product/ground-plate/ | N |
| XBee 3 PRO, PCB antenna (WRL-15127) | rover radio (in the simpleRTK2B socket) | SparkFun | $30.95 | https://www.sparkfun.com/xbee-3-pro-module-pcb-antenna.html | N |
| XBee 3 PRO, RP-SMA (WRL-15131) | base radio (external antenna) | SparkFun | $28.95 | https://www.sparkfun.com/xbee-3-pro-module-rp-sma-antenna.html | N |
| 2.4 GHz 8 dBi omni, RP-SMA, 10 ft cable | base radio antenna at ~3 m | Amazon | $35.99 | https://www.amazon.com/dp/B09WR8DT2J | Y |
| ExpertPower 12 V 20 Ah LiFePO4 | base battery (days of runtime for ~2 W) | Amazon | $129.99 | https://www.amazon.com/dp/B07X523S96 | Y |
| 2× 12→5 V 3 A USB-C buck | base + rover power | Amazon | $11.99 ea → $23.98 | https://www.amazon.com/dp/B0BTVW8GMF | Y |
| Ogrmar IP65 enclosure | base box | Amazon | $14.99 | https://www.amazon.com/dp/B081RTRR2H | Y |
| **Kit hardware subtotal** | | | **≈ $850** | | |
| USB-C OTG cable (tablet → rover USB) | rover → tablet data | any | ~$10 | | Y |
| SMA jumpers, zip ties, 5/8-11 adapter | mounting | any | ~$25 | | Y |
| **With cables + mounting** | | | **≈ $885** | | |
| MOETER survey tripod 5/8-11 (optional) | base antenna mount | Amazon | $119.99 | https://www.amazon.com/dp/B0FFN1Q6NJ | Y |
| **With tripod** | | | **≈ $970 (≈ $1,005 incl. cables)** | | |

**Robust kit — simpleRTK4 Optimum (ZED-X20P) rover, calibrated survey antennas, solar top-up, PD hub**

| Part | Role | Vendor | Price | URL | Amazon |
|---|---|---|---|---|---|
| simpleRTK4 Optimum ZED-X20P (HAS, UBX raw, XBee socket) | rover receiver | ArduSimple | €225 → ≈ $281.25 | https://www.ardusimple.com/product/simplertk4-optimum-zed-x20p/ | N |
| simpleRTK2B Budget (ZED-F9P) | base receiver | ArduSimple | €172 → ≈ $215 | https://www.ardusimple.com/product/simplertk2b/ | N |
| 2× Calibrated Survey Multiband antenna, NGS-calibrated, 5/8-11, IP67 (ground plane built in) | base + rover antennas | ArduSimple | €149 ea → ≈ $372.50 | https://www.ardusimple.com/product/calibrated-survey-gnss-multiband-antenna-ip67/ | N |
| XBee 3 PRO pair (WRL-15127 + WRL-15131) + 2.4 GHz 8 dBi omni | radio link | SparkFun + Amazon | $95.89 | as above | mixed |
| ExpertPower 12 V 20 Ah LiFePO4 + 12→5 V buck + Ogrmar IP65 box | base power + enclosure | Amazon | $156.97 | B07X523S96 · B0BTVW8GMF · B081RTRR2H | Y |
| SUNER POWER 30 W panel + 10 A controller | trickle top-up only (not primary power) | Amazon | $89.95 | https://www.amazon.com/dp/B082X5M3BB | Y |
| MOETER survey tripod 5/8-11 | base antenna mount | Amazon | $119.99 | https://www.amazon.com/dp/B0FFN1Q6NJ | Y |
| 6-in-1 USB-C PD hub for Galaxy Tab | tablet charge + rover USB on the SM-X930 | Amazon | $60.47 | https://www.amazon.com/dp/B0CZF9XNM4 | Y |
| **Kit total as listed** | | | **≈ $1,390** | | |
| USB-C OTG cable, SMA jumpers, mounting | | any | ~$35 | | Y |
| **With cables + mounting** | | | **≈ $1,427** | | |

Note: Galileo HAS on the ZED-X20P needs a **tripleband antenna for E6** — the calibrated survey antenna above is
multiband L1/L2/L5; the E6-capable antenna's price was not captured. HAS is a decimetre fallback, not the plan
(decision 1), so the Robust kit ships without it and the note stands.

**Rejected alternatives** (one line each): SparkFun GPS-RTK-SMA F9P (Amazon B087T7BV6K, $259.95) — no XBee socket ·
Beitian BT-F9PK2 ($201.88) — ships from China in October · SparkFun RTK Postcard LG290P ($219.95) — RTCM-only raw, no
UBX, no socket · SparkFun UM980 ($414.95) — no HAS, Unicore raw format · SparkFun ZED-X20P breakout ($299.95) — no
socket · Emlid Reach RS3 ($2,999) — LoRa 915 MHz and Reach-to-Reach only.

#### Radio link decision (RESOLVED 2026-09-13)

- **Rejected: ArduSimple LR/XLR radios** (Digi XBee SX, 900 MHz, NA band 902–907 + 915–927 MHz) — and any LoRa 915.
  The CS463 hops 50 channels across 902–928 MHz at +30 dBm (+36 dBm EIRP through the CS776); at 1 m that is ≈ +4 dBm
  at the radio's antenna, against an XBee SX maximum RF input of +6 dBm and a sensitivity of −113 dBm. FHSS cannot
  help: FCC 15.247's 0.4 s dwell makes the reader effectively continuous across the whole band.
- Other bands: 868 MHz is illegal in the US; 433 MHz is Part 15.231 periodic-only (no continuous RTCM); 450 MHz
  licensed radios cost $1.5k+ each.
- **Recommended: Digi XBee 3 PRO 2.4 GHz pair** — 802.15.4 transparent AT mode, +19 dBm, 3,200 m line of sight,
  250 kbps; fits the same XBee socket on the simpleRTK2B / simpleRTK4 (UART2), so RTCM3 base → rover passes with no
  computer in the loop. The RFID second harmonic is 1.83 GHz — no overlap with 2.4 GHz. Configure channel 25 or 26
  (clear of the tablet's Wi-Fi channels), 115200 baud, DH/DL paired, base antenna at ~3 m.
- **Rover → tablet**: the F9P USB port is independent of UART1/UART2; NMEA GGA/RMC + RXM-RAWX + RXM-SFRBX on USB at
  1 Hz is ≈ 4–6 kB/s. That fits Bluetooth SPP at 115200 at 1 Hz but not at 5 Hz. Both ArduSimple BT modules use the
  single XBee socket the radio already occupies, so a Bluetooth rover would need a UART1 breakout (~$12, unverified).
  **Default is USB-OTG**: Tab S11 Ultra through the PD hub, RT71 through a plain OTG cable.

### LPOS-6 Tag-position estimation spike — medium, research, `no_commit_ok: true`, suggest-only
- Can the CS463 LLRP stream expose RF phase (CSL custom parameters / reader-vendor custom `RFPhaseAngle` parameter)? Inspect
  `services/CS463TcpReaderService.ts` and the CSL LLRP extension docs; capture one session with phase if available.
- Prototype offline (notebook or script under `scripts/research/`) a multi-read RSSI(+phase) trajectory estimate over
  recorded sessions with `rtk_fixed` samples; report achievable tag-position error against the owner's cm target with
  the honest ceiling from the literature (Tagoram 1.4 cm controlled / 12 cm uncontrolled; robot SAR 6–15 cm).
- Output: a report (docs/scantap/tag-position-spike.md) with a go/no-go recommendation and, if go, the follow-up
  cases. No production code. Gated on LPOS-2 + LPOS-3 merged and at least 3 recorded RTK-fixed sessions.

## 5. Interface contract with peer programs

- `CaptureEngine.ingest(tag: TagEvent): void` signature is frozen. The fix shape `{lat,lng,accuracy_m,heading,speed}`
  stays everywhere it exists (coverage, geofence, cornerMapping, roadRecorder). Everything LPOS adds is ADDITIVE:
  `fix_source`, `src`, `acc`, `ppk`, `fix_accuracy_m`. `LocationSample` field names never drift; new keys are optional.
- **Mobile tree order**: LPOS-2 and LPOS-3 change `platform/mobile/scantap/` and sequence BEHIND SZC-2 (scan-zone,
  `feat/scantap-scan-zone-counts`, root `CASE-20260913-SZC000`) and CAD-2 (Tag Caddy tablet, `feat/tag-caddy`, root
  `CASE-20260913-CAD000`) — mobile files change on one branch at a time. The antenna-optimization program (root
  `CASE-20260913-ANT000`) also queues on the tablet tree; whichever of ANT/SZC/CAD lands last, LPOS-2 rebases onto it.
  The blocker rows are written at filing time against the LEAF ids (roots 422 as blockers) — placeholders in the
  script's `EXTERNAL_DEPS`.
- Coverage (COV-1..6): LPOS does not touch `scan_coverage.py`'s contract; a later one-line COV follow-up may use
  `acc` to tighten snapping. Antenna-side mapping (`antenna_sides`, COV-2) is unchanged.
- SZC (scan zones) and ANT (antenna optimization) own reader power / antenna / zone config; LPOS never edits
  `readerConfig.ts` or reader settings.
- Print Cloud / BOM: LPOS-5 adds a separate kit; it does not edit existing kit rows or print-related BOM entries.
- CI-1 `CASE-20260914-02E342`: 11 scantap tests red on master — list, do not fix.

## 6. Migration numbers

| File | Case | Notes |
|---|---|---|
| tenant `v044_positioning_config.sql` | LPOS-1 | + mirror in `ingestion-worker/migrations/apps/scantap/` |
| control-plane `v185_scantap_v044_manifest.sql` | LPOS-1 | v172 pattern |
| control-plane `v186_gnss_caster_catalog.sql` | LPOS-1 | seed catalog, `ON CONFLICT DO NOTHING` |
| tenant `v045_fix_source.sql` | LPOS-2 | + mirror |
| control-plane `v187_scantap_v045_manifest.sql` | LPOS-2 | |
| tenant `v046_gnss_raw_logs.sql` | LPOS-3 | + mirror |
| control-plane `v188_scantap_v046_manifest.sql` | LPOS-3 | |

Every file idempotent, applied twice on a scratch schema, never applied by an agent (owner op via
`scripts/tenant_sql.py --owner … --ledger scantap:vNNN`). Note that tenant v036–v038 are still NOT applied on either
tenant (ledger at v035) — LPOS files must reference no v036–v043 object.

## 7. Open owner actions

1. **Base at the office on mains power (decided 2026-09-14)** — verify the spot (open sky, ≥ 3 m from RFID antennas, base radio antenna at ~3 m elevation;
   mains, or the LiFePO4 battery with the optional 30 W solar trickle) — blocks the first live test.
2. **Buy Budget (≈ $850–970) or Robust (≈ $1,390)** — section 4a; the radio decision is made (XBee 3 PRO 2.4 GHz),
   so this is a purchase, not a design question. ArduSimple ships DHL from Spain in 2–5 days.
3. **OPUS / CSRS-PPP upload of the 2–4 h base log** — after the base is installed; the coordinate is typed into the
   platform (LPOS-1 form) and into the base receiver's TMODE3 FIXED mode by the owner. No automation.
4. **PPK station order** — confirm `{UMBC,BACO}` (1 s station first) as the default — see LPOS-4.
5. **Pick and buy the cell tablet (opened 2026-09-14 by owner answer Q9)** — an Android tablet with its own
   Verizon **band 13** modem that Verizon will actually activate (certified/BYOD-approved IMEI, not just a spec
   sheet listing the band), ideally with an external cellular antenna connector for the weatherproof box. Neither
   deployed tablet qualifies (SM-X930 is US WiFi-only; RT71-PRO lacks band 13). Blocks the live NTRIP path in
   LPOS-7; does **not** block LPOS-7 from being built, because the bridge-app and no-data-link states are in scope.
   Candidates researched 2026-09-14 in section 11.7 — recommended buy is the Samsung Galaxy Tab Active5 Pro
   `SM-X358U`, the only shortlisted device that is both Verizon-sold and has an external cellular antenna port.
6. **Buy the rover half now (owner answer Q12)** — ArduSimple simpleRTK2B + BT/BLE bridge + ANN-MB antenna ≈ $300,
   already in the cart. Base half waits for the trial result. Item 2 above is therefore split, not executed whole.
7. **Start the rtkdata.com 30-day trial (owner answer Q8)** — no card required; the clock is better spent now than
   after the receiver lands.

## 8. Risks

- **R1 — RFID 915 MHz vs data-radio band. RESOLVED 2026-09-13.** The CS463/CS776 radiate 902–928 MHz at +30 dBm
  (+36 dBm EIRP) on the cart, hopping 50 channels with a 0.4 s dwell — effectively continuous across the band. Any
  900 MHz ISM RTCM radio (ArduSimple LR/XLR XBee SX, LoRa 915) on the same cart sees ≈ +4 dBm at 1 m against a +6 dBm
  maximum input and −113 dBm sensitivity, and FHSS cannot avoid it. 868 MHz is illegal in the US, 433 MHz is
  periodic-only, 450 MHz licensed radios cost $1.5k+. **Decision: Digi XBee 3 PRO 2.4 GHz pair** (802.15.4, +19 dBm,
  3.2 km LOS, RFID second harmonic 1.83 GHz does not overlap) — section 4a "Radio link decision".
- **R1b — GNSS antenna vs RFID desense.** The mechanism is compression of the active GNSS antenna's LNA: +36 dBm EIRP
  at 0.5 m is ≈ +10 dBm at the GNSS puck, far above what an L1/L2 LNA is built for, and shows up as a C/N0 collapse
  and loss of FIX while the reader inventories. Mitigation is physical: mount the GNSS antenna ≥ 1.5–2 m from the
  CS776, above and behind it (outside its 70° beam), use the ground plate (ANN-MB-00) or a survey antenna with a
  built-in ground plane, and verify C/N0 in u-center with the reader ON vs OFF before fixing the mount (runbook
  step in LPOS-5).
- **R2 — Hourly CORS retention (~2 days).** A log not processed within ~48 h of the scan loses its base data. The
  30-min cron plus `failed:cors_window_missed` accounting covers it; a multi-day agent-06 outage is a data loss for
  PPK only (live positions are unaffected).
- **R3 — Bluetooth SPP bandwidth for RAWX.** NMEA GGA/RMC + RXM-RAWX + RXM-SFRBX at 1 Hz is ≈ 4–6 kB/s: it fits SPP at
  115200 at 1 Hz, not at 5 Hz, and is subject to drops when the CS463 BLE link is active. On the simpleRTK boards the
  Bluetooth modules occupy the same XBee socket as the RTCM radio, so a BT rover needs a UART1 breakout (~$12,
  unverified). **Default is USB-OTG on both tablets** (Tab S11 Ultra via the PD hub, RT71 plain OTG); Bluetooth is a
  fallback for live NMEA only (raw logging disabled on BT).
- **R4 — Tag position expectation.** The owner wants cm for the TAG; physics gives cm for the antenna. LPOS-6 is
  the gate; the UI must say "cart position" until it reports.
- **R5 — Expo native modules.** Serial and Bluetooth Classic libraries need config plugins and a fresh EAS build;
  a peer bumping `app.json` mid-CI has bitten before — re-check origin/master before every bump.
- **R6 — `encrypt_secret()` plaintext fallback** (memory 2026-09-06): refuse to store an NTRIP password without the
  key.

## 9. Rollout

1. Manor View Farm first (`9a1f6820-ed3d-4595-8f92-b973d8dbb09a`): `enabled=false` by default (feature flag off) until
   the base is installed and OPUS returns; then `method='own_base'`, `correction_transport='radio'`, `ppk_enabled=true`.
2. GroTap tenant: test-only, `ppk_only` with the fixture station list to exercise the worker without a base.
3. Ohio / Florida tenants later: `method='ntrip'` with the catalog entry; no code change.
4. Mobile releases through the existing release convention; no APK published from an agent.

## 10. Not in scope

- Tag-level cm positioning in production (LPOS-6 is a spike only).
- Cellular modem hardware inside the reader box (a phone hotspot / Jetpack / cell tablet is an owner purchase, not a case).
  (Tablet NTRIP relaying was excluded here until 2026-09-14; it is now LPOS-7 — section 11.)
- Automating OPUS/CSRS-PPP submission or survey-in.
- A new map library on the tablet; changes to the coverage engine contract or colour model.
- Changes to reader power / antenna / zone config (SZC, ANT), print BOM rows (another session), SBI / inventory views (SIV).
- iOS builds, PPP (Galileo HAS) receivers, multi-base networks, moving-base heading.
- HI holds for worker run summaries (PRODUCT FREEZE — logs and status columns only).

## 11. RTK devices and services integration (owner doc 2026-09-14)

Source: owner document `#RTK Devices and Services Integration.md` (Downloads, 2026-09-14). It asks for three things:
(a) use RTK equipment with a **third-party correction service (rtkdata.com)** over a **Verizon cell link on the
tablet**; (b) the tablet connected to an **external GNSS receiver over Bluetooth or USB**, the ScanTap mobile app
choosing between the built-in GPS "like we do now" and the external RTK fix; (c) **server-side PPK with RTKLIB
`rnx2rtkp`** and automatic NOAA CORS base download, fed from an uploaded `.rinex` file, results mapped in the UI.
The document is chatbot output (Node/Express sample, a NOAA URL that does not resolve, a CORS station that does not
exist); the facts below replace it. Nothing from its code sample is ported — our stack is FastAPI + the agent-06
Docker worker (LPOS-4).

### 11.1 What the existing cases already cover

| Owner ask | Already in | Gap |
|---|---|---|
| Tablet ↔ external receiver over USB / Bluetooth, app prefers RTK fix, falls back to built-in GPS | **LPOS-2** (`PositionProvider`, USB-OTG + BT SPP, fix pill) | none for the receiver link; the **NTRIP client** on the tablet did not exist (decision 3 forbade it) |
| Per-tenant choice of correction source incl. a public/commercial NTRIP caster | **LPOS-1** (`method='ntrip'`, `correction_transport='ntrip'`, `ntrip_*` columns, caster catalog) | catalog has no commercial US services; credentials never reach the tablet; no field says WHO runs the NTRIP client |
| RTKLIB PPK against NOAA CORS, automatic base fetch, `.pos` parsed to positions | **LPOS-4** (Docker `convbin` + `rnx2rtkp`, S3 archive, 30-min cron) | input is only our own `.ubx` from LPOS-3; no manual RINEX upload; three factual fixes (11.2) |
| Raw logging on the tablet | **LPOS-3** | none |
| "Ready in 15 minutes" processing status in the UI, track on a map | — | **new** (LPOS-8) |
| Verizon cell on the tablet | — | owner purchase + config; no hardware case |

### 11.2 Verified facts (research 2026-09-14; supersede the owner doc where they differ)

**rtkdata.com** — Kansi Solutions GmbH (Germany). Aggregates third-party reference networks and resells them through
its own NTRIP caster ("20,000+ stations in 140+ countries"); it does not disclose whose stations serve Maryland
(page lists "active stations near Baltimore, Annapolis, Frederick, Rockville …", no distances, no mount-point
list). Nearest-single-base, chosen from the rover's GGA via mountpoint **`AUTO`** (also `AUTO_WGS84`,
`AUTO_ITRF2020`); not VRS. RTCM 3.2 MSM4, GPS+GLO+GAL+BDS, works with a ZED-F9P. **Requires a constant internet
link on the rover.** Claims 1–2 cm H / 2–3 cm V. **Pricing: $40/month, $400/year, $1,920/5 years, ONE concurrent
stream per licence (a second login kicks the first); 30-day free trial, no card.** Host/port and credentials are
issued at signup — the catalog entry therefore ships with `host=NULL, verified=false` until the trial account exists.
Baseline from the unnamed "Baltimore" station is unknown; at 20–30 km a single-base RTK fix is realistic but slower
to fix and closer to 3–4 cm than 1–2 cm. Sources: rtkdata.com/pricing, docs.rtkdata.com/faq, rtkdata.com/us/maryland.

**Alternatives** (all take a plain ZED-F9P unless noted): Alpha RTK (DE/MD/NJ/PA/DC network, $195/mo, $995/yr,
1-week trial); Point One Polaris (True RTK $125/mo or $1,500/yr, RTCM 3.2 MSM4, 14-day trial); Onocoy ($20/30 days +
$0.15 per streamed hour); Skylark Nx RTK ($699/yr); GEODNET RTK ($40/mo, $400/yr via resellers); KeyNetGPS (Trimble
VRS, $375/30 days, $3,135/yr); Leica SmartNet NA (~$2,400/yr state level). **No free RTN in MD, PA or DE.**

**NOAA CORS** — **there is no station "MD02"** (absent from the NGS coordinate list and the S3 archive; checked
2026-09-14). Real stations within 50 km of Monkton, INTERVAL read from the RINEX headers of DOY 256: **BACO**
(Towson) 20.1 km at **5 s**; **UMBC** 37.2 km at **1 s**; **YORK** (PA) 46.8 km at **1 s**. GODE/LOYF/DENE are
65–74 km at 30 s. Archive: `https://noaa-cors-pds.s3.amazonaws.com/rinex/YYYY/DDD/ssss/ssssDDDh.YYo.gz` (`h`=a–x
hourly, `0`=daily, `.d.gz` Hatanaka). **Hourly files are kept 2 days** (verified: DOY 254 gone on DOY 257); daily
files are decimated to 30 s after ~30 days. Consequence: the 30-min cron with a 90-min delay (LPOS-4) is right; a
file uploaded manually more than 2 days after the drive must use the daily file, and after 30 days only 30 s data
remains (PPK still works, fix ratio drops). GEODNET PPK API exists (account by e-mail, JWT, RINEX 3.04 orders) but
publishes no price — not seeded.

**RTKLIB** (corrected 2026-09-14 after independent verification by the program's previous owner; their wording
wins where it differs from the first research pass) — the maintained line is **the same repository**,
`rtklibexplorer/RTKLIB`, renamed to RTKLIB-EX and now developed on `main`. There is no separate RTKLIB-EX
repository to clone, and `demo5` is no longer the branch to build. Latest tag **`v2.5.1`, lowercase, published
2026-06-22**; `main` has moved past it (last commit 2026-08-31), so build from the tag, not from the branch:
`git clone --branch v2.5.1 --depth 1 https://github.com/rtklibexplorer/RTKLIB.git`. BSD-2-Clause. Linux: CMake or
`app/consapp/rnx2rtkp/gcc && make`; no official Docker image. `.pos` Q flags: 1 fix, 2 float, 3 SBAS, 4 DGPS,
5 single, 6 PPP. *Not asserted:* no announcement post retiring `demo5` could be found — the branch readme and the
commit history are the evidence, and rtkexplorer.com/downloads is stale.

**`rnx2rtkp` does not use the RINEX header base position on a bare invocation** — `rnx2rtkp.c` explicitly assigns
`prcopt.refpos = POSOPT_SINGLE`, overriding `prcopt_default`, so the base coordinate becomes an average of
single-point solutions: roughly **2.5 m off** (Emlid), and that error propagates 1:1 into every rover epoch while
the ratio test still reports Q=1. A fixed-ambiguity solution that is metres wrong passes every quality check we
would otherwise apply, which is the same class of false pass as the placeholder-EPC one. Three overrides exist:
`-r X Y Z` (ECEF, from the NGS coordinate file), `-l lat lon hgt`, and `ant2-postype=rinexhead` in a `-k` config —
the `-k` load runs *after* the hardcoded assignment, so a config file does win. **Never hardcode the integer**:
`POSOPT_SINGLE` is 2 in RTKLIB-EX (1 upstream), and the `refpos` comment in the EX `rtklib.h` still carries the
stale 0-4 numbering. Test by asserting on the argv the worker builds, not on the output. Run time for 1 h at 1 Hz: seconds to ~2 min (forward+backward doubles it) — the doc's "under 2 seconds"
is unverified.

**Cell on the tablet** — Samsung sells the Tab S11 Ultra in the US as **Wi-Fi only** (SM-X930); the 5G SM-X936 is
not a US/Verizon SKU. The Xenarc RT71-PRO has an LTE modem without Verizon band 13 and no carrier certification.
RTCM at 1–2 kB/s is ≈ 5–7 MB per hour of scanning; a month of daily drives is well under 1 GB. Verizon: Tablet/
Hotspot Unlimited $20/mo added to a voice line ($75 standalone), prepaid tablet $50; a phone hotspot costs nothing
extra. Third-party FCC-derived coverage for 21111 is 99 % 4G/5G (Verizon's own map is address-interactive; verify on
site). **Answer to "we may have to have cell-enabled tablets": no — a phone hotspot or a Jetpack in the cart box
serves the Wi-Fi tablet; a cell tablet is optional.**

**Android integration paths for an external receiver** —
- *Bridge app (zero app change)*: **GNSS Master** (EPS Works, free) does USB-OTG, BT Classic, BLE, NTRIP v1/v2 with
  "Send NMEA GGA to Base Station" (needed for `AUTO`/VRS), Android **mock location**, and can switch on UBX
  RXM-RAWX/SFRBX for PPK. Lefebure NTRIP Client (free) is the BT-only equivalent. Emlid Flow as a mock-location
  provider is UNVERIFIED (conflicting docs). Once "Select mock location app" points at the bridge, **expo-location
  in the current app already receives the RTK position and its accuracy** (`coords.accuracy`, `mocked=true`) —
  `tag_records.accuracy_m` records it today with no code change. What is missing is attribution (fixed vs float)
  and raw logging into our pipeline.
- *In-app (LPOS-2 + LPOS-7)*: NMEA over `@serserm/react-native-turbo-serialport` (USB, New-Arch) or
  `react-native-bluetooth-classic` 1.73.0-rc (BT SPP; New-Arch interop risk, issue #334) plus an NTRIP client
  written on `react-native-tcp-socket` (~100 lines: HTTP GET with Basic auth, `Ntrip-Version: Ntrip/2.0`, GGA
  upstream every ~10 s; `react-native-ntrip-client` 1.0.6 is unmaintained, use it as a reference only).
- *Receivers*: ArduSimple simpleRTK2B $221 + BT module €34 (SPP) or BT+BLE bridge €71 — already carted; Emlid Reach
  RX ~$1,599 (**no raw logging**, NTRIP client lives in Emlid Flow); SparkFun RTK Torch $2,149.95 today (**no
  logging**, own NTRIP client only over Wi-Fi). Tab S11 Ultra GNSS is L1-only single band — never PPK material.

### 11.3 Design — one correction path on the tablet, three sources behind it

```
  correction source (tenant config)          delivery                 rover on the cart
  ─────────────────────────────────          ───────────────          ─────────────────────────────
  own base at the office ──RTCM3──▶ XBee 2.4 GHz radio ─────────────▶ ZED-F9P ──USB/BT──▶ tablet   (Route A, today)
  own base at the office ──RTCM3──▶ Emlid Caster / RTK2Go (office WiFi)┐
  rtkdata.com  mountpoint AUTO  (or any caster in the catalog)         ├─ NTRIP over cell ─▶ tablet NTRIP client ──▶ ZED-F9P  (LPOS-7)
  state RTN (ODOT / FPRN)                                              ┘        ▲ GGA upstream every 10 s
```

- **Tablet NTRIP client (LPOS-7)** is the only new runtime piece. It runs when `correction_transport='ntrip'` and
  `rover_ntrip_client='tablet_app'`: connects to the tenant's caster, forwards RTCM bytes to the receiver over the
  LPOS-2 transport, sends GGA upstream, shows correction age in the scan pill, and drops to the radio/none path when
  the link dies (the receiver keeps a float/single solution; `fix_source` reflects it). Credentials reach the tablet
  through a **new device-token route that returns them decrypted once per session, audit-logged**, only when
  `rover_ntrip_client='tablet_app'` — the frozen `GET /scantap/positioning/device` shape stays credential-free.
- **Bridge-app path (LPOS-7, runbook + server rule)**: for tenants who run GNSS Master / Lefebure as the mock-location
  provider, the app stays as it is. LPOS-2's `PositionProvider` marks an expo-location fix with `mocked=true` as
  `fix_source='ext_mock'` (additive value; the vocabulary list in LPOS-2 gains one entry, nothing existing changes)
  and carries `coords.accuracy` as `acc`; `tag_locations` treats `ext_mock` with `acc ≤ 0.05 m` like `rtk_fixed`
  (`method='rtk'`). This is the path the owner can test **this month** with only the rover half of the kit and the
  rtkdata.com trial, while LPOS-2 waits behind the SZC/CAD/ANT tablet leaves.
- **Own base through a caster** (LPOS-5 amendment): the office base gets a "caster" variant — ArduSimple **WiFi NTRIP
  Master** (ESP32, XBee socket, ~€60) pushes RTCM3 to Emlid Caster (free, private mount point) or RTK2Go over the
  office Wi-Fi; the rover pulls it over cell. The XBee 3 PRO pair becomes the offline option, not the default, IF
  the owner confirms Q10. Saves ~$120 and removes the line-of-sight constraint.
- **Manual RINEX/UBX upload + PPK status (LPOS-8)**: the Live Position page gets an "Upload GNSS log" block
  (`.obs/.rnx/.yyO/.ubx`, ≤ 200 MB, presigned PUT to the LPOS-3 R2 prefix), a job list from `gnss_raw_logs`
  (queued / processing / processed / failed with reason and the "base data becomes available ~N min after the hour"
  note derived from the log's end time), and a result view: fix ratio, station, baseline, and the track drawn on the
  map program's `GeoMap` (default export of `frontend/src/components/map/GeoMap.tsx`, built by MAP-2a
  `CASE-20260914-C9FB5C`; renders children as react-map-gl `Source`/`Layer`/`Marker`, optional `panels` slot,
  `onFeatureClick(layerId, feature)`, `useGeoMap().registerLayer(id, label, defaultOn)`; layer ids namespaced
  `lpos.*` — `scantap.*`, `cad.*`, `vae.*` are taken). Contract confirmed by that program's owner 2026-09-14.
  MAP-2a is not merged, so the import is guarded and a plain table is the fallback. The worker
  (LPOS-4) accepts RINEX directly (skip `convbin`), matches a manual log to a scan session by tenant + time overlap
  (owner picks when ambiguous), and never overwrites live values.
- **Catalog** (LPOS-1 amendment): seed rtkdata.com (`mountpoint='AUTO'`, `host=NULL`, `verified=false`, `price_note`
  "$40/mo per concurrent rover, 30-day trial"), Alpha RTK, Point One Polaris, Onocoy, Skylark Nx, GEODNET RTK,
  KeyNetGPS — each with `source_url`, `price_note`, `verified=false` except the ones whose host/port are published.
  `positioning_configs` gains `rover_ntrip_client CHECK IN ('none','tablet_app','bridge_app','receiver') DEFAULT
  'none'` and `ntrip_send_gga BOOL DEFAULT true` (both in v044 — LPOS-1 is not dispatched yet, so no new migration).
- **LPOS-4 corrections**: replace `MD02` nowhere (it was never in the plan) but pin the base coordinate: pass
  `-r X Y Z` from the NGS coordinate file for the station (catalog `published_xyz`), fall back to `ant2-postype=
  rinexhead` — never the default single-point average; build from tag `v2.5.1` of `rtklibexplorer/RTKLIB` (same repo, renamed; not `demo5`, not `main`);
  accept RINEX 2/3 obs as input and only run `convbin` for `.ubx`; write `result.input_format`.

### 11.4 Cases added / amended

| Case | Change | Status |
|---|---|---|
| LPOS-1 `CASE-20260914-94B579` | + catalog rows, `rover_ntrip_client`, `ntrip_send_gga`, `price_note`/`published_xyz` columns on the catalog | amended before dispatch |
| LPOS-2 `CASE-20260914-F02FCF` | + `fix_source='ext_mock'` from `mocked=true`, `acc` from `coords.accuracy`; expose a `writeToReceiver(bytes)` hook on the transport for LPOS-7 | amended, parked |
| LPOS-3 `CASE-20260914-F0F196` | + `gnss_raw_logs.source CHECK IN ('tablet','manual') DEFAULT 'tablet'`, `format CHECK IN ('ubx','rinex')`, `uploaded_by` (v046) | amended, parked |
| LPOS-4 `CASE-20260914-915E58` | base coordinate `-r` rule, RTKLIB-EX v2.5.1 pin, RINEX-direct input, manual-log ↔ session matching | amended, parked |
| LPOS-5 `CASE-20260914-E7C338` | + "caster" base variant (WiFi NTRIP Master → Emlid Caster) in kit + runbook, radio pair marked optional | amended, parked |
| **LPOS-7** `CASE-20260914-83DF98` Tablet NTRIP client + bridge-app path — complex, 80 turns | blocked by LPOS-2 (mobile tree); parked `awaiting_deps` | filed 2026-09-14 |
| **LPOS-8** `CASE-20260914-5898B3` Manual GNSS log upload + PPK job status/track UI — medium, 40 turns | blocked by LPOS-3 + LPOS-4 (+ MAP-2 for the map, soft, fail-open); parked `awaiting_deps` | filed 2026-09-14 |

Build order becomes `LPOS-1 → LPOS-2 → LPOS-3 → LPOS-4 → LPOS-8`, `LPOS-7` after LPOS-2 on the tablet tree, LPOS-5 in
parallel after LPOS-1, LPOS-6 unchanged. Migration numbers unchanged (v044–v046 / cp v185–v188 absorb the additive
columns because none of LPOS-1..3 has been claimed).

### 11.5 Owner questions (Q8–Q13) — recommendations in bold; filed as one clarification hold on LPOS-7

- **Q8 Recurring fee.** rtkdata.com is $40/month per concurrent rover ($400/yr). The decision of record was "zero
  recurring fees, own base". **Recommend: start the 30-day free trial now (no card) to validate cm positions on the
  cart before any base install; keep the own base as the long-term default for Manor View; keep rtkdata.com /
  Alpha RTK as the per-tenant option for tenants without a base.** Yes / no / trial only?
- **Q9 Cell link.** Phone hotspot ($0), Verizon Jetpack or hotspot line in the cart box (~$20/mo on the existing
  account), or a cell tablet (no US Tab S11 Ultra 5G SKU; RT71-PRO lacks Verizon band 13). **Recommend hotspot for
  the trial, a Jetpack mounted in the reader box for production.** This reverses decision 3 ("no WiFi/hotspot in the
  field") — confirm.
- **Q10 Own base over the internet instead of radio.** With cell on the cart the office base can publish to Emlid
  Caster (free) and the rover pulls it like any NTRIP source: no XBee pair (−$120), no line of sight, one code path.
  **Recommend yes; keep radio as the offline fallback variant in the kit.**
- **Q11 Bridge app first.** GNSS Master as the Android mock-location provider makes today's app record cm positions
  with zero code (attribution and raw logging follow in LPOS-2/7). **Recommend yes for the trial month.** It means
  the field procedure has an extra app on the tablet until LPOS-7 ships.
- **Q12 Receiver purchase.** The carted ArduSimple rover half (simpleRTK2B + BT/BLE bridge + ANN-MB antenna, ~$300)
  is enough for the trial; Emlid Reach RX ($1,599) cannot log raw data; RTK Torch ($2,149) cannot either.
  **Recommend: buy the rover half now, the base half after the trial (Q8/Q10).**
- **Q13 Manual upload UI.** Only needed when logs come from receivers/apps other than ours (Emlid RS3, GNSS Master
  export). **Recommend yes (LPOS-8), sequenced after LPOS-4 — it is the UI the owner doc describes.**

Assumptions until answered: Q8 trial-only, Q9 hotspot, Q10 yes, Q11 yes, Q12 rover half, Q13 yes. LPOS-7 (`CASE-20260914-83DF98`) and LPOS-8 (`CASE-20260914-5898B3`) are filed
under these assumptions and parked at `awaiting_deps` (the assign loop ignores `pipeline_case_deps` and only skips
that status — platform-75, 2026-09-14); nothing is dispatched that a "no" would waste except the LPOS-1 catalog rows,
which are harmless.

### 11.6 Owner answers of record (2026-09-14) — these supersede the 11.5 assumptions

- **Q8 — Trial only.** Start the rtkdata.com 30-day trial (no card, $40/mo · $400/yr afterwards, one concurrent
  rover per licence). Own base stays the long-term default for Manor View; the paid caster stays a per-tenant
  option for tenants with no base of their own. Do not put a subscription in the kit price.
- **Q9 — CHANGED from the recommendation. No hotspot and no Jetpack: buy an Android tablet that carries its own
  Verizon band 13 modem.** The tablet is the cell link. This keeps decision 3's "no WiFi/hotspot in the field"
  intact in spirit — there is no separate radio brick in the cart box to charge, mount or lose — and it removes the
  hotspot from the field procedure entirely. Consequences:
  - The tablet SKU is now part of the Live Position kit, not a given. Model selection is a hardware research task,
    tracked as owner action A5 in section 9; a candidate must be **Verizon-certified/activatable**, not merely
    band-13 capable on a spec sheet, or the IMEI will not activate.
  - Decision 2 ("any tablet must work") is unchanged **as a software requirement** — the app still must run on the
    SM-X930 11" and the Xenarc RT71-FHD 7" with no cell link, degrading to radio or to PPK-only. What changes is
    that the *cell* correction path (LPOS-7) is only available on a cell-equipped tablet, so the tenant config and
    the UI must treat "this device has no data link" as a first-class state rather than an error.
  - Both currently deployed tablets fail this test: SM-X930 is WiFi-only in the US (SM-X936 is not sold here) and
    the Xenarc RT71-PRO modem lacks band 13. Neither can be made to work by adding a plan.
  - A weatherproof enclosure attenuates cellular; prefer a candidate with an external cellular antenna connector.
- **Q10 — Yes.** The office base publishes to Emlid Caster (free) and the rover pulls it over NTRIP like any other
  source: one code path, no line-of-sight requirement, and the XBee 3 PRO pair (−$120) leaves the default kit.
  Radio stays as the documented offline fallback variant in the LPOS-5 runbook and BOM, not the default.
- **Q11 — Yes, for the trial month.** GNSS Master as the Android mock-location provider gives cm positions with no
  app change; expo-location reports them and LPOS-7's `fix_source='ext_mock'` path attributes them. The extra app
  on the tablet is accepted until LPOS-7 ships.
- **Q12 — Buy the rover half now** (ArduSimple simpleRTK2B + BT/BLE bridge + ANN-MB antenna ≈ $300). The base half
  is bought after the trial, once Q8/Q10 have been proven on the cart. Emlid Reach RX and SparkFun RTK Torch stay
  rejected: neither can log raw observations, so neither can feed PPK (Route B).
- **Q13 — Yes.** LPOS-8 ships as specified, sequenced after LPOS-4.

**What this changes in the filed cases** (amendments, not re-files): LPOS-1 caster catalog carries the rtkdata trial
row and an Emlid Caster row for our own base; LPOS-5's default kit drops the XBee pair, gains the cell tablet line
and splits the BOM into "buy now" (rover half) and "buy after trial" (base half); LPOS-7's cell link is the tablet's
own modem, with the no-data-link state made explicit. LPOS-4 is **platform-30's case body** — none of these answers
change it, and this session does not edit it.

### 11.7 Cell tablet candidates (research 2026-09-14, for owner action 5)

The requirement from Q9: an Android tablet with its **own Verizon band 13 modem that Verizon will activate**.
Certification is the gate, not the spec sheet — a device that lists band 13 but is not on Verizon's approved
list will not activate. Ranked shortlist; prices are US street as of 2026-09-14.

1. **Samsung Galaxy Tab Active5 Pro `SM-X358U` (5G) — recommended.** 10.1" WUXGA, Snapdragon 7s Gen 3, 6 GB /
   128 GB, 10,100 mAh, MIL-STD-810H + IP68, Android 15, USB-C OTG + BT 5.3. **Sold directly by Verizon Business**
   (certification confirmed) and it has a **dedicated SMA external-antenna connector** — the one candidate that
   directly answers the weatherproof-enclosure attenuation problem. ~$625–770.
   `https://www.verizon.com/business/shop/products/devices/tablets/galaxy-tab-active5-pro`
2. **Getac ZX70 G2 — the only 7" rugged option found.** 7" sunlight-readable, IP67, 1.82 m drop. Verizon's Open
   Development showcase lists a Getac ZX70 with band 13, **but the listed spec (2 GB RAM / Android 6) matches an
   older hardware revision than the G2 being sold, so which revision is certified is UNCONFIRMED**. The G2 ships
   Android 10 — a short security runway for a 2026 purchase. External antenna UNCONFIRMED. ~$1,200–2,500,
   enterprise channel. Verify the exact SKU with Getac sales before buying.
3. **Samsung Galaxy Tab S10 FE 5G `SM-X528U`** — 10.9", **7 years of OS + security updates** (best longevity here),
   IP68 but not drop-rated, no external antenna port. Verizon sells it directly; the US SKU's exact band list is
   UNCONFIRMED (band 13 is confirmed on the international X526B). ~$499–650. Needs our own enclosure.
4. **Zebra ET45 (8" / 10.1")** — MIL-STD-810H / IP65, Wi-Fi 6, hot-swap battery option. Verizon Business publicly
   certified the ET40/ET45 in Dec 2023. External antenna UNCONFIRMED (Zebra documents one for the ET6x, not ET4x).
   Price is quote-only everywhere — expect a sales call.
5. **Samsung Galaxy Tab A9+ 5G `SM-X218U`** — 11", band 13, Verizon-sold, ~$219–269, but **Android updates end
   ~Oct 2026 and security patches in 2027**. Spare only, never the fleet standard.

Rejected: Panasonic Toughbook A3 (discontinued, Android 9) · Getac ZX10 (Verizon listing behind a login,
UNCONFIRMED) · Honeywell RT10A (no Verizon confirmation) · Durabook R11 (only the sibling U11 is listed) ·
Kyocera and Sonim (no current Android tablet) · Lenovo (no current Verizon-sold cellular tablet).

Open before buying: confirm with Verizon that the exact IMEI/SKU activates on a data plan, and confirm the
enclosure fit and mount for whichever size is chosen (the fleet runs 11" and 7" today; the Active5 Pro is 10.1").
