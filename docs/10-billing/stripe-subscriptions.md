---
title: "Implementing Stripe subscriptions_"
source: google-drive-docx
converted: 2026-03-01
component: "Stripe"
category: billing
doc_type: how-to
related:
  - "Neon"
  - "WorkOS"
  - "FastAPI"
  - "INNGEST"
tags:
  - stripe
  - billing
  - subscriptions
  - invoices
  - metering
status: active
---


# Implementing Stripe subscriptions_

Implementing Stripe subscriptions within a multi-tenant ERP requires a robust architecture to handle tenant isolation, asynchronous billing events, and seamless context switching. Using your stack (WorkOS, FastAPI, Inngest, Neon), the implementation follows a high-reliability event-driven pattern.
1. Multi-Tenant Identity & Billing (WorkOS + Stripe)
For an ERP, WorkOS acts as the bridge between your multi-tenant authentication and Stripe's billing objects.
- Organization Linking: Map each WorkOS Organization to a unique Stripe Customer ID. This ensures that when a user switches context (tenants), the platform knows which billing profile to access.
- Stripe Entitlements: Use WorkOS Stripe Entitlements  to automatically include subscription status in the user's access token. This eliminates the need to query Stripe or your database on every request to check if a tenant has an active "Pro" plan.
   Seat Sync: Enable Stripe Seat Sync in WorkOS to automatically update Stripe billing meters based on the number of active members in a WorkOS organization.

   WorkOS  --  Your app, Enterprise

2. Event-Driven Billing Architecture (Inngest)
Instead of handling Stripe webhooks directly in your FastAPI backend, use Inngest as your Central Event Bus to ensure reliability and scalability.

- Webhook Ingestion: Create an Inngest Webhook Source  and provide its URL to Stripe. Inngest will receive and transform these into internal events like stripe/checkout.session.completed.
- Fan-out Processing: Use Inngest functions to "fan-out" work. One event can trigger multiple isolated tasks:
     1. --------------------------------------------------------------------------------
     Provisioning: Update the tenant's status in your Neon database.
     2. --------------------------------------------------------------------------------
     Notification: Send a welcome or confirmation email.
     3. --------------------------------------------------------------------------------
     Analytics: Push data to your tracking tools.
   Reliability: Inngest provides automatic retries and concurrency management, preventing your database from being overwhelmed during peak billing cycles.

3. Backend & Database Isolation (FastAPI + Neon)
- Context Switching: Use FastAPI Dependencies  to extract the tenant_id (from WorkOS tokens) and set it in a thread-safe ContextVar.
- Data Isolation: In Neon, enforce Row-Level Security (RLS) by including a tenant_id column in all billing and subscription tables. This ensures that one tenant cannot accidentally see or modify another's subscription data.
   Stripe SDK Integration: Your FastAPI routes should use the Stripe SDK to create Checkout Sessions . Always pass the tenant_id or workos_org_id in the Stripe metadata to link events back to the correct account.

   WorkOS  --  Your app, Enterprise

## Summary of Component Roles
Component
Primary Function in Billing
WorkOS
Syncs user seats to Stripe and injects billing status into JWTs.
Stripe
Manages the product catalog, handles recurring payments, and issues webhooks.
Inngest
Acts as the central bus to reliably process billing webhooks and trigger workflows.
Neon (Postgres)
Stores the "source of truth" for tenant subscription states with RLS isolation.
FastAPI
Provides the API layer for initiating checkouts and managing tenant-specific logic.

---

## Agent Instructions

- **Use this when:** Implementing Stripe subscription billing per tenant
- **Before this:** WorkOS auth, Neon consumption API, and FastAPI all configured
- **After this:** Per-tenant billing data flows from Neon into Stripe automatically
