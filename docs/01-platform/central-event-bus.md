---
title: "Central Event Bus - Architecture"
source: google-drive-docx
converted: 2026-03-01
component: "Central-Event-Bus"
category: architecture
doc_type: architecture
related:
  - "INNGEST"
  - "FastAPI"
  - "Neon"
tags:
  - event-bus
  - erp
  - routing
  - architecture
  - modules
  - post-office
status: active
---


# Central Event Bus - Architecture

A Central Event Bus is an architectural "post office" or router that handles all communication between the different modules of your ERP system.

## Amazon AWS
In a traditional system, if the Sales module needs to tell the Inventory module to reduce stock, it has to call it directly. With an event bus, the Sales module simply "shouts" an event (e.g., OrderPlaced) into the bus, and any other module -- Inventory, Finance, or Shipping -- that is "listening" can react independently.

## Key Advantages for ERPs
- Asynchronous Workflows: The Sales module doesn't have to wait for the Finance module to finish processing a complex ledger entry before confirming the order to the customer.
- Auditability: Because every major business action is an event, you can easily log these to an Audit Trail table for compliance.
- Modular Growth: You can add a "Shipping" or "Loyalty Points" module later. You just create a new listener for sales.order.created without changing a single line of code in the Sales module.
   Fault Tolerance: If the Finance listener fails, the Sales order still goes through, and the event can be retried later.

For larger, distributed ERPs, you replace the internal EventEmitter with a durable external job system. This platform uses Inngest as the event and job system for all async workflows.

## IBM
How It Works in an ERP
The bus operates on a Publish-Subscribe (Pub/Sub) model:

## Akamai
- Publishers: A module (like Sales) detects a change and sends a JSON "event" message to the bus.
- The Bus: The central hub evaluates the message against predefined rules to see where it should go.
   Subscribers: Modules (like Finance or Inventory) receive the message and perform their own specific tasks, such as creating a ledger entry or updating stock levels.

   Amazon AWS

## Why Your ERP Needs It
  1. --------------------------------------------------------------------------------
- Loose Coupling: Modules don't need to know each other exist. You can add a "Loyalty Points" module later just by having it listen for OrderPlaced events without touching the Sales code.
  2. --------------------------------------------------------------------------------
- Scalability: If your Finance module is slow because it's processing heavy reports, it won't crash the Sales checkout process because the communication is asynchronous (the Sales module doesn't wait for a "done" response).
  3. --------------------------------------------------------------------------------
- Audit Trail: The central bus acts as a single source of truth where every major business action is logged as an immutable fact, which is critical for financial compliance and debugging.
  4. --------------------------------------------------------------------------------
   Resilience: If the Inventory service is temporarily down, the event stays in the bus (or a queue) until the service comes back online and "catches up".
  5. --------------------------------------------------------------------------------

  6. --------------------------------------------------------------------------------
   IBM
  7. --------------------------------------------------------------------------------

## Common Tools
For a cloud-scale ERP, you might use services like Amazon EventBridge or a durable job system. This platform uses Inngest exclusively for event-driven background workflows and async ERP module communication.
See the Inngest docs in `07-jobs/` for implementation patterns including tier-based prioritization and per-tenant throttling.

---

## Agent Instructions

- **Use this when:** Designing the Central Event Bus for ERP module communication
- **Before this:** INNGEST and FastAPI configured
- **After this:** All ERP modules route messages through this event bus
