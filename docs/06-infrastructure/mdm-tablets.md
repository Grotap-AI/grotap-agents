# Headwind MDM — Android Tablet Fleet Management

*Live 2026-07-21. Owner doc: "#scan m App Remote Connection and Control of Tablet.md". Android ONLY — no Apple work.*

## What it is
Self-hosted Headwind MDM (Community Edition, $0 license) managing our Android tablets as
fully managed **Device Owner** devices: QR enrollment at factory reset, silent Scan M APK
install/updates, policies, and (once the $990 Remote Control plugin is installed) unattended
WiFi screen view + touch control — the tablet stays controllable while its only USB-C port
is occupied by the RFID reader.

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
`MDM_PANEL_URL`, `MDM_ADMIN_LOGIN`, `MDM_ADMIN_PASSWORD` (panel), `MDM_SQL_PASS`,
`MDM_SHARED_SECRET` (server .env), `MDM_DEVICE_ADMIN_PIN` (on-device settings/kiosk exit).
Default `admin/admin` was rotated at install — panel API login takes
`MD5(password).hexdigest().upper()`.

## MDM objects
- **Configuration "Grotap Tablets"** (id 3, `autoUpdate=true`) — auto-installs the Headwind
  launcher + **Scan M** (app id 78, pkg `com.grotap.scantap`, APK by URL from R2).
- **Enrollment QR** (public): `https://mdm.grotap.com/rest/public/qr/<qrCodeKey>?size=400`
  (config 3 key: `51cf7d160baac84f6149d219887d29fe`; JSON view under `/rest/public/qr/json/`).
- **Enroll flow**: factory reset → tap the Welcome screen 6× → native QR scanner → scan →
  device joins WiFi, installs the agent as Device Owner, Scan M lands automatically.
  No developer options / Auto Blocker changes needed.

## APK rollout (Scan M releases)
Register the new version + URL via panel or API (`PUT /rest/private/applications/android`),
config auto-update pushes it to every enrolled tablet. Phase-2 case CASE-20260722-780A08
adds a one-call backend endpoint for this plus the Server Farm "Tablets" page + automation bank.

## Panel API cheatsheet (cookie session)
`POST /rest/public/auth/login` `{login, password: MD5-upper}` → JSESSIONID;
`GET /rest/private/devices/search` · `GET /rest/private/summary/devices` ·
`PUT /rest/private/applications/android` · `PUT /rest/private/configurations`.

## Pending owner holds (human_holds)
- `MDM-PLUGIN-PURCHASE` — buy Remote Control plugin ($990 one-time) at h-mdm.com/pricing;
  next session installs it.
- `MDM-TABLET-ENROLL` — factory reset + QR-enroll the Tab S11 Ultra (steps in the hold).
