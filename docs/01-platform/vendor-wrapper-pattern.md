---
title: "Vendor Wrapper Pattern & Provider Pattern"
source: google-drive-docx
converted: 2026-03-01
component: "Architecture"
category: architecture
doc_type: architecture
related:
  - "FastAPI"
  - "React"
tags:
  - vendor-wrapper
  - provider-pattern
  - architecture
  - 3rd-party
  - abstraction
status: active
---


# Vendor Wrapper Pattern & Provider Pattern

CoBrowse.io  - Use Vendor Wrapper PatternVendor Wrapper Pattern & Provider PatternHow 3rd party resources will be incorporated into the app.
3rd party apps will have kill switches to hide them if service is not live
Vendor Wrapper Pattern (also known as a Facade or Service Wrapper) combined with a Provider Pattern.
This approach decouples your business logic from the specific third-party API, making it easy to maintain, test, and swap out if needed.

To implement a solution like Cobrowse.io  in an enterprise-grade, robust way that avoids code duplication, use the Vendor Wrapper Pattern (also known as a Facade or Service Wrapper) combined with a Provider Pattern.
This approach decouples your business logic from the specific third-party API, making it easy to maintain, test, and swap out if needed.

1. Create a Dedicated Service (The Wrapper)
Instead of calling the SDK directly in your UI, create a single singleton service or module. This acts as the "brain" for your integration.
- Abstraction: Define your own internal methods like startSession() or endSession().
- Encapsulation: All Cobrowse-specific configuration (License Keys, API endpoints) stays inside this file.
   Error Handling: Centralize how you handle connection drops or SDK loading failures here.

2. Use the Provider Pattern (For React/Vue)
Wrap your application (or a specific branch) in a Context Provider or Plugin. This allows you to initialize the SDK once at the root level.

## Stack
- Snippet in App: You only need to add <CobrowseProvider> at your top-level App file.
   Lazy Loading: Use dynamic imports to only load the Cobrowse SDK when a user actually needs support, keeping your initial bundle size small.

   Crest

3. Implement a Custom Hook or Directive
For individual components that need to trigger co-browsing (like a "Help" button), provide a simple hook.
- Code in Components: const { startSession } = useCobrowse();
   Cleanliness: This ensures your components don't care how the session starts, only that they can call a function to do it.

4. Enterprise-Specific Considerations
- Security (JWT): Use your backend to generate short-lived JWTs for Cobrowse authentication , and pass these through your wrapper to ensure users are identified securely without exposing secret keys in the frontend.
- Version Control: If you have multiple apps, publish this wrapper as a private NPM package. This ensures all your enterprise applications use the exact same, approved version of the integration.
   Data Redaction: Centralize your PII (Personally Identifiable Information) masking rules in the wrapper so that sensitive fields are never visible to agents across the entire app.

---

## Agent Instructions

- **Use this when:** Implementing vendor wrappers for all 3rd party integrations
- **Before this:** None — implement this pattern BEFORE any 3rd party integration
- **After this:** All 3rd party calls now go through wrappers — easy to swap vendors
