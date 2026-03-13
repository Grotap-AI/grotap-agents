---
title: "App Revenue Model — 80/20 Creator Split, WorkOS Features, Stripe per-App"
updated: 2026-03-05
doc_type: reference
category: billing
tags: [revenue, stripe, workos, creator, billing]
status: active
---

# App Revenue Model

## Overview

grotap operates as a two-sided app marketplace:

| Party | Cut | Scenario |
|---|---|---|
| grotap (platform) | 100% | Grotap-built apps |
| grotap (commission) | 20% | Customer-published apps |
| App creator (tenant) | 80% | Customer-published apps |

---

## Per-App Billing Architecture

### App Access Gate: WorkOS Features

Each app has a corresponding **WorkOS Feature** with slug = `apps.slug`.

```
User subscribes to "invoice-processor" app
    → POST /app-registry/apps/{id}/subscribe
    → workos_provider.enable_feature(org_id, "invoice-processor")
    → Feature appears in JWT claims for all users in that org
    → Frontend reads JWT features → shows app in My Apps
```

```
User cancels "invoice-processor" app
    → DELETE /app-registry/apps/{id}/subscribe
    → workos_provider.disable_feature(org_id, "invoice-processor")
    → Feature removed from JWT → app disappears from My Apps
```

**grotap.com users**: bypass feature check entirely — see all apps.

### Per-App Stripe Pricing

Each paid app has a `stripe_price_id` in the `apps` table.

**Subscribe flow:**
1. `POST /app-registry/apps/{id}/subscribe`
2. Backend looks up `apps.stripe_price_id`
3. Adds subscription item to tenant's existing Stripe subscription:
   ```python
   stripe.SubscriptionItem.create(
       subscription=tenant.stripe_subscription_id,
       price=app.stripe_price_id
   )
   ```
4. Stores `stripe_subscription_item_id` in `tenant_app_subscriptions`

**Cancel flow:**
1. `DELETE /app-registry/apps/{id}/subscribe`
2. Backend cancels subscription item: `stripe.SubscriptionItem.delete(item_id)`
3. Updates `tenant_app_subscriptions.status = 'cancelled'`

**Webhook handling** (existing `billing.py` webhook route):
- `invoice.payment_succeeded` → calculate creator split, insert `app_earnings` row
- `customer.subscription.updated` → sync `tenant_app_subscriptions` status

---

## Creator Revenue Tracking

### `app_earnings` Table
Inserted on each successful invoice payment for a creator-built app:

```python
async def record_app_earning(app_id, paying_tenant_id, amount_cents, stripe_invoice_id):
    app = await db.get_app(app_id)
    creator_pct = app['creator_revenue_pct']  # default 80
    creator_amount = int(amount_cents * creator_pct / 100)

    await db.insert_app_earning({
        'app_id': app_id,
        'paying_tenant_id': paying_tenant_id,
        'amount_cents': amount_cents,
        'creator_amount_cents': creator_amount,
        'stripe_invoice_id': stripe_invoice_id,
        'period_start': invoice.period_start,
        'period_end': invoice.period_end
    })
```

### Creator Payout
- MVP: manual payout (Grotap reviews `app_earnings` and pays via bank transfer)
- Future: Stripe Connect — `stripe.Transfer.create(amount=creator_amount, destination=creator_stripe_account_id)`

### Creator Dashboard (future app)
- `GET /app-registry/my-apps` — creator sees their published apps
- `GET /app-registry/my-apps/{id}/earnings` — earnings by month
- Monthly summary: subscriptions active, revenue, grotap commission, creator payout

---

## Free vs Paid Apps

| Type | `is_free` | `stripe_price_id` | Access |
|---|---|---|---|
| Platform utilities (billing, audit, etc.) | true | null | Auto-subscribed for all tenants |
| Internal apps (support, admin) | true | null | grotap.com users only, no Stripe |
| Paid apps | false | set | Requires subscribe → Stripe item |
| Beta apps | varies | null (free during beta) | Subscribe for free → `status=trial` |

---

## Doppler Secrets (existing + additions)

Existing:
- `STRIPE_SECRET_KEY` — Stripe server-side key
- `STRIPE_WEBHOOK_SECRET` — webhook signature
- `STRIPE_PRO_PRICE_ID` — platform-level plan

New per-app price IDs are stored in `apps.stripe_price_id` in DB — NOT in Doppler (too many apps).

---

## Agent Instructions

- **Use this when:** Implementing app subscribe/cancel flows, webhook revenue tracking, or creator earnings
- **Before this:** `app-store-model.md` for DB schema
- **Related:** `docs/10-billing/stripe-subscriptions.md` for platform-level Stripe context
