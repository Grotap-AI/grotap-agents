---
id: "13465"
title: "Bug: Platform — Found by the screenshot-verifier while verifying CASE-20260730-B5C204 (which is"
complexity: medium
priority: high
branch: "case-CASE-20260730-ACTVCL"
case_id: "CASE-20260730-ACTVCL"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "50470213-ae43-42c5-9bb1-329f4a44a41e"
team: "team4"
---

# Task: Bug: Platform — Found by the screenshot-verifier while verifying CASE-20260730-B5C204 (which is

## Context
Found by the screenshot-verifier while verifying CASE-20260730-B5C204 (which is
MERGED, commit 99c16a4c - this is a separate latent gap, not a regression from it).

On the ScanTap Locations grid the is_active ("Active") column is ABSENT even though
STANDARD_VISIBLE[SCREEN.locations] in frontend/src/lib/gridTemplates.ts lists it. Confirmed
absent identically on production, so it predates B5C204 and is not caused by it.

SUSPECTED CAUSE - same class as B5C204: a late `columns` memo recompute in
frontend/src/pages/ScanTapLocationsPage.tsx re-applies the colDef's own hide value over the
state the template applied, so the template's hide:false loses. B5C204 fixed exactly this
shape for external_code by re-asserting through gridApi.applyColumnState instead of relying on
the colDef diff; the same reasoning likely applies here but the COLUMN AND THE DIRECTION ARE
REVERSED (here the template wants it SHOWN and something hides it), so do not assume the fix
is symmetric - diagnose before patching.

SCOPE. Frontend only. Establish first whether is_active is meant to be visible by default on
this screen; if it is, make the template's intent win the same way B5C204 did. Do not change
external_code behaviour, the geo-point columns, or the Export column list.

VERIFY with a browser check on a tenant with a mix of active and inactive locations, including
clicking Standard after load. Screenshot verification must go through the screenshot-verifier
agent - never Read image files in the main session.

## Requirements
Found by the screenshot-verifier while verifying CASE-20260730-B5C204 (which is
MERGED, commit 99c16a4c - this is a separate latent gap, not a regression from it).

On the ScanTap Locations grid the is_active ("Active") column is ABSENT even though
STANDARD_VISIBLE[SCREEN.locations] in frontend/src/lib/gridTemplates.ts lists it. Confirmed
absent identically on production, so it predates B5C204 and is not caused by it.

SUSPECTED CAUSE - same class as B5C204: a late `columns` memo recompute in
frontend/src/pages/ScanTapLocationsPage.tsx re-applies the colDef's own hide value over the
state the template applied, so the template's hide:false loses. B5C204 fixed exactly this
shape for external_code by re-asserting through gridApi.applyColumnState instead of relying on
the colDef diff; the same reasoning likely applies here but the COLUMN AND THE DIRECTION ARE
REVERSED (here the template wants it SHOWN and something hides it), so do not assume the fix
is symmetric - diagnose before patching.

SCOPE. Frontend only. Establish first whether is_active is meant to be visible by default on
this screen; if it is, make the template's intent win the same way B5C204 did. Do not change
external_code behaviour, the geo-point columns, or the Export column list.

VERIFY with a browser check on a tenant with a mix of active and inactive locations, including
clicking Standard after load. Screenshot verification must go through the screenshot-verifier
agent - never Read image files in the main session.

## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "CASE-20260730-ACTVCL" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error
