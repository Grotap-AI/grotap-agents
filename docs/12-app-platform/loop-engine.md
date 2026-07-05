---
title: "Loop Engine — App Spec & Build Logic"
updated: 2026-06-18
doc_type: spec
category: app-platform
tags: [loop-engine, automation, inngest, gmail, multi-tenant]
status: building
project: Loop Engine
app: Loop Engine
---

# Loop Engine — App Spec (hand-off to platform build agent)

> **Project name = App name = `Loop Engine`.** Build this as a registered platform app
> following `12-app-platform/app-store-model.md` + `app-template-guide.md`. Obey all 9
> ABSOLUTE RULES in `CLAUDE.md` (Doppler secrets, vendor wrapper, Neon DB-per-tenant,
> tenant scoping, AppShell+Cobrowse, 4-reviewer sign-off).
>
> **Release path:** owner directive **skip staging** — Loop Engine is a new app scoped to its
> own pages + dedicated router (app-only fast path). Branch off `master`, target `master`.

---

## 1. What Loop Engine is

A per-tenant **automation console**. Every business/user that subscribes gets *their own*
Loop Engine instance. Inside it they manage **loops** — named, scheduled "bundles of logic"
they can run on demand or on a schedule.

The app screen lists each loop as a row with:

| Column | Source |
|---|---|
| **Name** | `loops.name` |
| **Description** | `loops.description` |
| **Last run** | `loops.last_run_at` (+ status badge from latest `loop_runs` row) |
| **Run next** (scheduled) | `loops.next_run_at` (derived from `loops.cron`) |
| **Run now** (button) | `POST /loop-engine/loops/{id}/run` |
| **Run next** (button) | edit/advance schedule → `PATCH /loop-engine/loops/{id}` |

First loop shipped with the app: **`Info@sauvieislandstable.com gmail`** (see §7), exposed
to the Sauvie Island Stables tenant as the automation **`Sauvie Island Stables Gmail Clean up`**.

> **Owner directive: many jobs.** The console is built to hold many loops — many Gmail cleanups
> against different accounts, and later other bundle types entirely. The Gmail logic is ONE
> reusable bundle; each cleanup against a different mailbox is a new `loops` row + its own
> connected account + `config` (see §13).

---

## 2. Answers to the three framing questions

**"How do we store it?"**
- The **app** is one row in the control-plane `apps` table (slug `loop-engine`) — same
  registry every other app uses.
- Each **loop** is one row in the tenant's **own Neon database** (`loops` table — Rule 5,
  DB-per-tenant). The loop's logic is stored as ordered **steps** (`loop_steps` JSONB or
  child table). No loop is shared across tenants (Rule 4).
- Run history lives in `loop_runs` (per tenant).

**"How do I later know it exists / find it?"**
- After subscribe, Loop Engine appears in the **app launcher** (it's in the `apps` registry,
  gated by a WorkOS Feature `loop-engine`).
- Inside it, `GET /loop-engine/loops` returns the tenant's loops for the list screen.
- Platform support can see who uses it via the existing `app_tenant_summary` view.

**"How do I call it?"**
- Manually: **Run now** button → `POST /loop-engine/loops/{id}/run` → emits Inngest event
  `loop/run.requested` → the loop executor runs the steps.
- On schedule: each loop has a `cron`; an Inngest cron function wakes hourly, finds loops
  whose `next_run_at <= now()`, and emits `loop/run.requested` for each. (This replaces the
  ad-hoc RemoteTrigger "Daily Gmail Cleanup" routine with a first-class platform object.)

---

## 3. Data model (tenant Neon DB — scoped by `tenant_id` via RLS)

```sql
CREATE TABLE loops (
    loop_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID NOT NULL,                       -- RLS scope (Rule 4)
    name          TEXT NOT NULL,                        -- "Sauvie Island Stables Gmail Clean up"
    bundle_slug   TEXT NOT NULL,                        -- "gmail-cleanup" (which logic to run) — see §13
    description   TEXT,
    cron          TEXT,                                 -- "0 14 * * *" (7am PT) — null = manual only
    timezone      TEXT DEFAULT 'America/Los_Angeles',
    enabled       BOOLEAN DEFAULT true,
    next_run_at   TIMESTAMPTZ,                          -- derived from cron; null if manual/disabled
    last_run_at   TIMESTAMPTZ,
    last_status   TEXT,                                 -- success | partial | failed | running
    config        JSONB DEFAULT '{}',                   -- per-tenant params (e.g. gmail account, label IDs)
    created_at    TIMESTAMPTZ DEFAULT now(),
    updated_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE loop_runs (
    run_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID NOT NULL,
    loop_id       UUID NOT NULL REFERENCES loops(loop_id),
    trigger       TEXT NOT NULL,                        -- 'manual' | 'schedule'
    status        TEXT NOT NULL DEFAULT 'running',      -- running | success | partial | failed
    started_at    TIMESTAMPTZ DEFAULT now(),
    finished_at   TIMESTAMPTZ,
    summary       JSONB,                                -- per-step counts (e.g. {"trashed":24,"archived":117})
    error         TEXT
);
CREATE INDEX ON loop_runs(tenant_id, loop_id, started_at DESC);

-- Steps are stored as the bundle definition (see §6). A "bundle" is the reusable LOGIC;
-- a "loop" is a tenant's scheduled INSTANCE of a bundle + their config.
```

**Bundle vs loop:** a *bundle* is reusable logic (code, versioned, shipped with the app — e.g.
`gmail-cleanup`). A *loop* is a tenant's configured, scheduled instance of a
bundle. This keeps logic DRY while honoring DB-per-tenant for the instances/runs.

> **NOTE (§13):** add a `connected_accounts` table + an `account_id` column on `loops` for
> per-account Google OAuth. This is additive to the schema above.

---

## 4. App registration (`app.manifest.json` → `POST /app-registry/register`)

```json
{
  "slug": "loop-engine",
  "name": "Loop Engine",
  "description": "Per-tenant automation console — schedule and run your business loops.",
  "icon": "🔁",
  "category": "Operations",
  "status": "building",
  "is_free": false,
  "is_internal": false,
  "creator_tenant_id": null,
  "creator_revenue_pct": 0,
  "workos_feature_id": "loop-engine",
  "version": "1.0.0",
  "tags": ["automation", "scheduling", "inngest"]
}
```

---

## 5. API endpoints (FastAPI, tenant-scoped middleware → RLS)

| Method | Path | Purpose |
|---|---|---|
| GET | `/loop-engine/loops` | List tenant's loops for the console (name, description, last_run, next_run, status). |
| POST | `/loop-engine/loops` | Create a loop (pick `bundle_slug`, set `cron`, `config`). |
| PATCH | `/loop-engine/loops/{id}` | Edit name/description/cron/enabled → recompute `next_run_at` ("Run next"). |
| POST | `/loop-engine/loops/{id}/run` | **Run now** → emit Inngest `loop/run.requested` `{tenant_id, loop_id, trigger:'manual'}`. |
| GET | `/loop-engine/loops/{id}/runs` | Run history (`loop_runs`). |
| DELETE | `/loop-engine/loops/{id}` | Soft-disable/remove. |

---

## 6. Inngest functions

**`loop-scheduler`** (cron `0 * * * *`): query all enabled loops with `next_run_at <= now()`
across tenants; for each emit `loop/run.requested` `{tenant_id, loop_id, trigger:'schedule'}`;
recompute `next_run_at` from `cron`.

**`loop-executor`** (on `loop/run.requested`):
1. Load loop + bundle by `bundle_slug`. Set `loop_runs.status='running'`, `loops.last_status='running'`.
2. Execute the bundle's steps (TypeScript — Rule 2) with the loop's `config`.
3. Write per-step `summary` counts; set `status` success/partial/failed; stamp `last_run_at`.
- Per-tenant throttling + cost tracking via the existing INNGEST patterns (`07-jobs/`).

---

## 7. Bundle: `gmail-cleanup` (Sauvie reference config: `info@sauvieislandstable.com`)

Reusable logic that runs the **complete Gmail cleanup we built** for
`info@sauvieislandstable.com`. All Gmail access goes through a **vendor wrapper**
`app/providers/gmail_provider.ts` (Rule 3) — never the Gmail SDK directly. The provider needs
`label`, `unlabel` (incl. add `TRASH`), `search_threads`, `list_labels`. Secrets (Gmail OAuth)
in **Doppler** (Rule 1).

**Per-tenant `config` for this loop:**
```json
{
  "gmail_account": "info@sauvieislandstable.com",
  "labels": {
    "marketing": "Label_5842031461765221996",
    "signwell": "Label_648432540040543608",
    "sis_invoices": "Label_7419572204981402365",
    "sis_operation_invoices": "Label_8332356094731787449",
    "vendor": "Label_5614284237788852939",
    "venmo": "Label_5683836990847843510",
    "pdx_parent": "Label_8132358652632992994",
    "form_submission": "Label_6938648571126656976",
    "staffing": "Label_3848031524101861348",
    "kids_lessons": "Label_6605354511096118338",
    "horse_camp": "Label_10",
    "notices": "Label_4210923521004771159",
    "ninety_days_old": "Label_9"
  }
}
```

**Steps (run in order; each step = search inbox + apply action). Canonical rule source of
truth is `gmail-filters.xml` (importable Gmail filters) — keep them in sync.** Shipped at
`platform/migrations/apps/loop-engine/seeds/gmail-filters.xml`.

1. **Home Depot** `from:homedepot.com` → **TRASH**.
2. **Promotional / cold-sales / review-bait / newsletters** (sender allowlist in
   gmail-filters.xml filter #2: fairhillsaddlery, 45thparallelwines, eliterefined, yotpo,
   junipmail, toast-restaurants, mintmobile, triedequestrian, doversaddlery(shop@),
   reliablegrowthsolutions, schoolsoutapp, hvrx(marketing@), supabase(newsletters),
   indeed(employers/no-reply marketing), lululemon, nuwatt, voltaire-design, sstack/Schneiders,
   wordzen, etc.) → **TRASH**. NOTE: `Marketing and Sales` label is **outbound business
   marketing only** — never file inbound promos there.
3. **UPS** `from:ups.com` → **TRASH**.
4. **SEO/lender/laundry/sponsorship cold-sales** (rangeoriginus, layerusafinova,
   grouphealth\*, govafunding\*, schoolsponsoring\*, dropacoinlaundries, spincrewservices,
   tolaundrypro, barnlinking, theleatherlady, CIEE, nudgetext, daniel.cook SEO, etc.) → **TRASH**.
5. **SignWell** `from:signwell.com` → `5 - Signwell Notices` + archive.
6. **QuickBooks customer invoices** `from:quickbooks@notification.intuit.com -Huntsinger -"Double J"`
   → `4 -SIS Invoices` + archive. **QB vendor invoices** (Huntsinger / Double J) → `3 - Vendor`
   + archive. **Intuit payroll/tax/setup** (noreply@intuit.com, intuit@notices.intuit.com, etc.)
   → `SIS Operation Invoices` + archive.
7. **Vendor invoices / receipts / utility bills / order confirmations / insurance / DocuSign**
   (PayPal, Shopify, Zoro, Horseware, Mutual Screw, Wilbur-Ellis, US Bank, Global Industrial,
   WM/wasteconnections, Apple receipts, Stripe, Bitwarden, Hetzner billing, Abler, hvrx orders,
   Square, EWSI, **subject:insurance**, **from:docusign.net OR subject:docusign**) → `3 - Vendor
   Invoices & Receipts` + archive.
8. **Venmo** `from:venmo@email.venmo.com` → `Venmo` label + archive.
9. **PDX Parent** `from:pdxparent.com` (lauren.wylie@, Publisher@) → `PDX Parent` label + archive.
10. **Squarespace form submissions** `from:form-submission@squarespace.info` → `2 - Squarespace
    Form Submission`, **KEEP in inbox**. Obvious SEO-spam form subs (jmailservice, slowarc,
    "targeted traffic"/"search ranking"/"new clients") → **TRASH**.
11. **Horse Camp** — `subject:camp` (covers "kids camp"), subject "Sauvie Island Stables Kids
    Horse Camp", and `subject:"Thanks for Subscribing to Reolink"` → `7 - Horse Camp Emails` + archive.
12. **Kids Lessons** — inquiries about riding lessons FOR A CHILD (child named / kid's lesson
    scheduling) → `8 - Kids Lessons` + archive. EXCLUDE adult-lesson requests. *(Content-based —
    cannot be a native Gmail filter; runs as a classify step in the executor.)*
13. **Staffing** — work/hiring/volunteering: Craigslist stable-hand applicants
    (`from:*reply.craigslist.org / robot@craigslist.org`, subjects "Ayudante de establo"/"Trabajo"),
    job applications, interviews, offers, apprenticeship → `6 - Staffing` + archive.
14. **Service/account notification noise** (Apple iCloud, Hetzner outage/price, Supabase security,
    Google Workspace, Meta, DispatchTrack, Squarespace account, Oregon DOR, Portland Revenue,
    ID.me, Google Drive shares) → `Z Email Notices All` + archive (non-destructive declutter).
15. **90-day sweep** — any thread whose **newest** message is older than 90 days → `90 days old`
    + archive. MUST verify newest-message date per thread (Gmail's `-newer_than:90d` is fuzzy at
    thread level; a thread with any recent reply must be skipped).

**Hard limitation to encode:** the Gmail provider cannot click "unsubscribe" links or send mail,
so promos are **trashed, not unsubscribed**. The durable substitute is importing
`gmail-filters.xml` (auto-trash on arrival). Surface this in the run summary, don't claim
"unsubscribed".

**Run summary shape** (written to `loop_runs.summary`):
```json
{ "trashed": 0, "vendor": 0, "staffing": 0, "kids_lessons": 0, "horse_camp": 0,
  "notices": 0, "archived_90d": 0, "pdx_parent": 0, "venmo": 0, "skipped_active": 0 }
```

---

## 8. The automation instance — `Sauvie Island Stables Gmail Clean up`

Seed row in the Sauvie Island Stables tenant DB:
```json
{
  "name": "Sauvie Island Stables Gmail Clean up",
  "bundle_slug": "gmail-cleanup",
  "description": "Daily inbox maintenance for info@sauvieislandstable.com — routes invoices/insurance/receipts, staffing, kids lessons, horse-camp, trashes promos & UPS, sweeps 90-day-old mail.",
  "cron": "0 14 * * *",            // 7:00 AM America/Los_Angeles
  "timezone": "America/Los_Angeles",
  "enabled": true,
  "config": { "...": "see §7" }
}
```
On migration, **disable the legacy RemoteTrigger routine** `trig_01DJppNaLDUzG5Bx5uMNgHtp`
("Daily Gmail Cleanup") so the schedule isn't double-fired.

---

## 9. Multi-tenancy

- Loop Engine is generic: any tenant subscribes and gets an empty loop console.
- Bundles are the shared, versioned logic library (shipped with the app). New tenants pick a
  bundle + provide `config`. The Gmail bundle is reusable by any tenant who connects a Gmail
  account — they just supply their own `gmail_account` + label IDs in `config`.
- All loop rows, runs, and config are per-tenant in their Neon DB (Rules 4 & 5).

---

## 10. Frontend

`src/features/loop-engine/` rendered inside **`AppShell`** (Rule 8 — Cobrowse mandatory).
`LoopList` table (columns per §1) with **Run now** and **Run next** actions, a run-history
drawer (`loop_runs`), and a status badge. Use the Inngest realtime pattern (`07-jobs/
inngest-realtime`) to live-update a loop's status while a run is in progress.

---

## 11. Build Pipeline — **Project: Loop Engine** (final steps to assign)

1. **DB migrations** — `loops`, `loop_runs` (+ RLS policies) in tenant template schema.
2. **App registry** — register `loop-engine` manifest; create WorkOS Feature; Stripe price if paid.
3. **Gmail vendor wrapper** — `app/providers/gmail_provider.ts` (label/unlabel/TRASH/search/
   list_labels); OAuth secrets into Doppler (`dev` + `prd`).
4. **Bundle executor** — implement `gmail-cleanup` steps §7 (TS, Rule 2);
   keep in sync with `gmail-filters.xml`.
5. **Inngest functions** — `loop-scheduler` (hourly cron) + `loop-executor` (on `loop/run.requested`);
   wire per-tenant throttling + cost tracking.
6. **API** — endpoints §5 behind tenant middleware/RLS.
7. **Frontend** — `LoopList` in AppShell with Run now / Run next + run history (§10).
8. **Seed** — create `Sauvie Island Stables Gmail Clean up` loop (§8); **disable legacy
   RemoteTrigger** `trig_01DJppNaLDUzG5Bx5uMNgHtp`.
9. **Compliance + review** — GitGuardian scan; pass all 4 reviewers (Rule 7) before merge to master.

---

## 12. Reference files (already produced for the Gmail bundle)

- `platform/migrations/apps/loop-engine/seeds/gmail-filters.xml` — 17 importable Gmail filters =
  canonical rule source for steps 1–11, 14 (native, auto-apply on arrival). **Import once per
  Gmail account** as the durable "unsubscribe" substitute. (Originated at `C:\3Claude\gmail-filters.xml`.)
- `~/.claude/.../memory/gmail-cleanup-routine.md` — sender→label mapping + limitations (the
  human-readable runbook the bundle implements).

---

## 13. Platform-build improvements (added on review by the platform-build Claude)

These reconcile the spec with three owner directives: **per-account Google OAuth**,
**"we will add many jobs / many Gmail cleanups against different accounts"**, and **skip staging**.
They are additive — they do not change §3's `loops`/`loop_runs` shape, only extend it.

**13.1 Generic bundle slug.** The bundle is named **`gmail-cleanup`** (not the account-specific
`info-sauvieislandstable-gmail`). One reusable bundle; each cleanup against a different mailbox
is a new `loops` row whose `config` carries that account's `gmail_account` + label IDs. This is
exactly §9's stated intent. Adding a NEW Gmail cleanup = create a loop, not a code change.

**13.2 Per-account Google OAuth + `connected_accounts`.** §7 assumes the mailbox is already
connected but never says how. Each mailbox a loop acts on is connected via Google OAuth
(scope `https://www.googleapis.com/auth/gmail.modify` — label + trash; never `mail.google.com/`
full delete). Add to the tenant DB (RLS, additive):
```sql
CREATE TABLE connected_accounts (
    account_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID NOT NULL,                 -- RLS scope
    provider          TEXT NOT NULL,                 -- 'google'
    email             TEXT NOT NULL,                 -- the connected mailbox
    scopes            TEXT[] NOT NULL DEFAULT '{}',
    enc_refresh_token BYTEA,                          -- encrypted at rest (LOOP_ENGINE_ENC_KEY, Doppler)
    enc_access_token  BYTEA,
    token_expires_at  TIMESTAMPTZ,
    status            TEXT NOT NULL DEFAULT 'connected',
    created_at        TIMESTAMPTZ DEFAULT now(),
    UNIQUE (tenant_id, provider, email)
);
ALTER TABLE loops ADD COLUMN account_id UUID REFERENCES connected_accounts(account_id);
```
- One platform-owned Google OAuth client; creds in Doppler: `GOOGLE_OAUTH_CLIENT_ID`,
  `GOOGLE_OAUTH_CLIENT_SECRET`, `LOOP_ENGINE_ENC_KEY`.
- Connect flow: console **Connect Gmail** → `GET /loop-engine/oauth/google/start` (consent URL,
  signed `state`) → `GET /loop-engine/oauth/google/callback` → store **encrypted** refresh token.
- `gmail_provider.ts` refreshes the access token from the stored refresh token; **never** log/store
  plaintext tokens.
- Honest limit: Google verification is required before the consent screen serves arbitrary external
  users; internal/Workspace accounts you administer work immediately. Verification is an ops task.

**13.3 Extra API endpoints** (additive to §5):
| Method | Path | Purpose |
|---|---|---|
| GET | `/loop-engine/accounts` | list connected mailboxes (email, status — never tokens). |
| GET | `/loop-engine/oauth/google/start` | begin OAuth connect. |
| GET | `/loop-engine/oauth/google/callback` | finish connect, store encrypted token. |
| GET | `/loop-engine/bundles` | list bundles + config schema (drives the create wizard). |

**13.4 Console create-wizard.** §10's `LoopList` gains a create/edit modal: pick bundle → pick or
**Connect** a Gmail account → name + cron (plain-English helper) → config form. This is what makes
"add many jobs" self-serve.

**13.5 Runtime note.** The bundle executor + `gmail_provider.ts` run in the **TypeScript Inngest
worker** (Rule 2; Inngest functions live in the TS worker — Python only fires events via
`providers/inngest_provider.py`). Confirmed correct; no cross-language hop.
