# Headwind MDM — Android Tablet Fleet Management

*Live 2026-07-21. **Promoted to the PRODUCTION panel 2026-08-30** (cutover off Headwind's hosted free
tier). Owner doc: "#scan m App Remote Connection and Control of Tablet.md". Android ONLY — no Apple work.*

## What it is
Self-hosted Headwind MDM (**Community Edition, $0 licence, NO DEVICE CAP**) managing our Android
tablets as fully managed **Device Owner** devices: QR enrollment at factory reset, silent Scan M APK
install/updates, and policies. This is now the panel customer tablets enrol onto.

> **Unlimited devices is the point of this box.** `GET /rest/private/settings` reports
> `deviceLimit=0`, and Headwind enforces the cap only when `deviceLimit != 0` — 0 means *no cap*, not
> *no seats*. The panel we came from, Headwind's **hosted free tier** at `srv.h-mdm.com`, reports
> `deviceLimit=3` and that cap is a hard one: at 3 device records it silently refuses to create
> another and tells the tablet nothing, which showed up as a customer being told *"Device management
> is at its licensed tablet limit (3 of 3)"* on `/scan-m/new-tablet`. Anything that reads
> `deviceLimit` must treat 0/absent as unlimited (`backend/app/routers/mdm.py::_panel_seats`).

> **This box is not a demo.** It was labelled `DEMO_PANEL` in code and "do not edit, never cite it as
> evidence" in `platform/docs/11-devops/headwind-mdm-config.md` until 2026-08-30 — a name inherited
> from the vendor demo instance it replaced. Because it read as a demo nobody cut over to it, and the
> fleet stayed on the 3-seat rental for weeks.

## Server
| | |
|---|---|
| Host | **mdm-01** — Hetzner cpx21 Ashburn, id 153766531, `87.99.140.189` |
| Panel | https://mdm.grotap.com (Cloudflare DNS-only A record, Let's Encrypt on-box) |
| Stack | Docker `/opt/hmdm-docker` — `headwindmdm/hmdm:0.1.8` (war 5.39.2-os, Tomcat 9) + `postgres:12-alpine` (bound 127.0.0.1) |
| Push | MQTT on `:31000` (devices keep an outbound channel; port open in UFW) |
| Firewall | UFW: 22/80/443/31000 only |
| TLS renew | `/etc/cron.d/certbot-renew-hmdm` — 1st + 15th monthly, certbot one-shot container then `docker compose restart hmdm` (entrypoint rebuilds the JKS keystore from `/etc/letsencrypt` on every start) |
| Restart | compose `restart: unless-stopped` + `systemctl enable docker` |
| SSH | fleet key (`~/.ssh/grotap_agents`), root |

## Secrets (Doppler grotap/prd — NEVER inline)
Panel API: **`MDM_SELF_URL` / `MDM_SELF_LOGIN` / `MDM_SELF_PASSWORD`** are the names the code prefers;
the **legacy** `MDM_PANEL_URL` / `MDM_ADMIN_LOGIN` / `MDM_ADMIN_PASSWORD` are the fallback and, as of
2026-08-30, are the only ones actually present in prd — the provider's fallback chain is what makes
this panel reachable today, so do not remove it.
Also `MDM_SQL_PASS`, `MDM_SHARED_SECRET` (server .env), `MDM_DEVICE_ADMIN_PIN` (on-device
settings/kiosk exit). Default `admin/admin` was rotated at install — panel API login takes
`MD5(password).hexdigest().upper()`.

Which panel the backend uses is **`MDM_PRIMARY_PANEL`** (`self` | `hosted`, unset ⇒ `self`). Rolling
back the cutover is that one variable; no code change. `grotap-backend` carries it set to `self`.

**The backend fails closed if these are missing.** `scan_m._provider()` does NOT fall back to the
other panel when the primary has no credentials — it raises, and the surfaces render "device
management is not configured on this service" or return 503. That is deliberate: both Headwinds
answer 200 for everything, so a substitution would look like success and would silently send tablets
back to the 3-seat hosted tier. `scripts/railway_secret_audit.py` has `MDM_SELF_URL` / `_LOGIN` /
`_PASSWORD` in `REQUIRED_VARS` for `grotap-backend` so their absence fails the audit.

## MDM objects *(read live 2026-08-30)*
- **Configuration 3 "Managed Launcher"** (10-inch; renamed from "Grotap Tablets" so the name matches
  the hosted panel's 20651) — `autoUpdate=true`, auto-installs the Headwind launcher + **Scan M**
  (app **78**, pkg `com.grotap.scantap`, 1.1.4 / code 10, APK by URL from R2).
  qrCodeKey `51cf7d160baac84f6149d219887d29fe`.
- **Configuration 4 "Managed Launcher 7in"** (7-inch Xenarc RT71; mirrors hosted 22003) — app **81**,
  pkg `com.grotap.scantap7`, 2.0.0 / code 1. qrCodeKey `9658def3630912f0e40b9b925b7d77e2`.
- **Ids differ per panel** (3/4 here vs 20651/22003 on the hosted tier) — resolve configurations by
  NAME, never by id, and fail loudly on a miss rather than taking whatever the panel listed first.
- Panel settings: `deviceLimit=0` (unlimited), `deviceCount=0`, `createNewDevices=true`,
  `newDeviceConfigurationId=3`.
- **Enrollment QR** (public): `https://mdm.grotap.com/rest/public/qr/<qrCodeKey>?size=400`
  — the path segment is the 32-char `qrCodeKey`, NOT the numeric id (an id returns 200 with a
  zero-length body). `?deviceId=<number>` bakes `com.hmdm.DEVICE_ID` in so nothing is typed on the
  tablet; `?create=1` lets the panel create the device record on contact.
- **Enroll flow**: factory reset → tap the Welcome screen 6× → native QR scanner → scan →
  device joins WiFi, installs the agent as Device Owner, Scan M lands automatically.
  No developer options / Auto Blocker changes needed.

## Not available on this box
**Remote screen control cannot work here.** `com.hmdm.control` is a **paid** Headwind plugin and is
not part of the open-source Community Edition build this server runs, so it can never appear in a
device's installed-app list on this panel however the tablet is set up. `/scan-m/devices/{n}/remote`
says so explicitly rather than reporting "the plugin is not installed on this tablet", which would
send someone looking on the tablet for something that was never shippable. The `MDM-PLUGIN-PURCHASE`
hold below is what would change that.

## APK rollout (Scan M releases)
Register the new version + URL via panel or API (`PUT /rest/private/applications/android`); the
configuration's auto-update pushes it to every enrolled tablet. Use
`platform/scripts/mdm_sync_scanm_version.py` rather than hand-typing a version — it reads
versionName/versionCode out of the APK binary, because filenames lie. **While both panels still hold
tablets, sync each panel separately**: a version record only reaches devices that sync the panel it
was written to.

## Panel API cheatsheet (cookie session)
`POST /rest/public/auth/login` `{login, password: MD5-upper}` → JSESSIONID;
`GET /rest/private/devices/search` · `GET /rest/private/summary/devices` ·
`GET /rest/private/settings` · `PUT /rest/private/applications/android` ·
`PUT /rest/private/configurations`.
All of it goes through `backend/app/providers/headwind.py` (vendor-wrapper rule) — never call the
REST API directly from a router, script, or test. Full trap list:
`platform/docs/11-devops/headwind-mdm-config.md`.

## Pending owner holds (human_holds)
- `MDM-PLUGIN-PURCHASE` — buy Remote Control plugin ($990 one-time) at h-mdm.com/pricing;
  next session installs it. Until then remote control is unavailable on this panel by construction.
- `MDM-TABLET-ENROLL` — factory reset + QR-enroll the Tab S11 Ultra (steps in the hold).
