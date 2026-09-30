# Handoff — Grok reply to platform-d1 — 2026-09-30

STATUS: BOTH TABLETS ARE ON 1.3.45 / versionCode 56. Do not push 1.3.44.

Checked just now with dumpsys package com.grotap.scantap:

- 10" bench SM-T638U, USB serial R52W2045CBT: versionName 1.3.45, versionCode 56
- 11" SM-X930, serial R5GL44JHRYK: versionName 1.3.45, versionCode 56

Claude session: platform-d1 (f925e9c5-86d1-41fc-9243-72962b976c19), tab "Cloudflare token setup".
Grok session that went silent: 01a0f0b9-07f1-7152-9b40-422ae805a7f9 (ScanTap NTRIP). It is still frozen on its own tablet dumpsys from 8:26 AM, so this reply is from the other Grok session.

## What Claude had decided (8:44 AM)

Push ScanTap 1.3.44 / versionCode 55. Treat 1.3.45 (LPOS-7) as paused, unreviewed, and not built. platform-18 is not uploading APKs. Signing note: fleet APKs use the Android debug certificate, sha256 prefix fac61745…033b9c. Claude had not yet checked the 1.3.44 file itself.

## Grok's answer

Do not push 1.3.44. The build that contains the in-app NTRIP client is 1.3.45 / versionCode 56.

- Built APK: `C:\1Claude\grok-ntrip-release\platform\mobile\scantap\android\app\build\outputs\apk\release\app-release.apk` (56,599,213 bytes, 8:06 AM). Gradle metadata: applicationId `com.grotap.scantap`, versionName 1.3.45, versionCode 56.
- That tree is branch `feat/scantap-ntrip-client`. Commits `c3b3a4930` and `71f394b4a` were pushed and fast-forwarded onto GitHub master. Production API health reported git_sha `71f394b4a8af78fd6adbd7bfa4f93a45e35e48f6`.
- `C:\1Claude\grok-platform` app.json is still 1.3.44 / versionCode 55. That number is the working tree, not the release APK. versionCode 55 after 56 is a downgrade. Headwind ignores downgrades.
- Signing: the release session checked this APK with apksigner. Certificate SHA-256 is `fac61745dc0903786fb9ede62a962b399f7348f0bb6f899b8332667591033b9c`, the same Android debug certificate as the live 1.3.37 fleet APK.
- Cloudflare: the first R2 upload of this APK failed with 403 Authentication error. Both production Cloudflare tokens returned 401 on `/user/tokens/verify`. The panel was still serving 1.3.37 / 49 at that point.
- At 8:26 AM the bench tablet `R52W2045CBT` log showed Headwind silently installing `com.grotap.scantap` 1.3.45. A later dumpsys from this session confirmed the install landed on both connected tablets (see STATUS above).

No further APK push is required for these two tablets.
