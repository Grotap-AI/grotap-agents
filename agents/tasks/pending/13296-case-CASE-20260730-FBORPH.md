---
id: "13296"
title: "Bug: Platform — DEFECT The feedback toolkit files a pipeline_case under the SUBMITTING tenant or"
complexity: medium
priority: high
branch: "case-CASE-20260730-FBORPH"
case_id: "CASE-20260730-FBORPH"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "bf8a87f2-bc56-4053-8a94-3aa7b3eeb3bb"
---

# Task: Bug: Platform — DEFECT The feedback toolkit files a pipeline_case under the SUBMITTING tenant or

## Context
Source: hi-sweep-20260730

## Requirements
DEFECT
The feedback toolkit files a pipeline_case under the SUBMITTING tenant org_id. Every automation loop selects per configured org (WHERE org_id = $1, driven by rows in pipeline_automation). Only GroTap has such a row. So feedback from any customer tenant is written to the database and then never triaged, never dispatched, and never surfaced to anyone — no hold, no alert, no queue it appears in.

EVIDENCE (2026-07-30)
Manor View Farm (org_01KWPXDXZZSYBJSPDBSB5VH4WQ) had 5 cases sitting at status=submitted from 2026-07-28 and 07-29, including a real ScanTap Label-Printing feature request and a real print-cloud freeze report. They were found only by grouping pipeline_cases by org_id during a hold sweep. Nothing in the product would ever have shown them.

This scales with customers: every tenant we onboard silently adds another black hole. The customer sees their feedback accepted and hears nothing back, forever.

WANTED
1. At intake, route customer-submitted feedback to the GroTap triage org (owner decision 2026-07-30) while recording the submitting org/tenant on the case, so provenance and any reply path survive. Keep both org_id and tenant_id consistent with each other — the HI company-scope check pairs them.
2. A backstop sweep for cases in an org with NO pipeline_automation row, raising one hold that names them, so this can never again be invisible.
3. Consider whether the submitter should get any acknowledgement, and whether a triaged customer case should be visible on the submitting company HI board.
4. Regression test: a case inserted under an org with no automation row must be picked up by the backstop within one sweep.

NOTE: the 5 MVF rows were already handled by hand in this sweep (3 rehomed to GroTap, 2 closed as test submissions) — see scripts/hi_mvf_reorg_0730.sql. This case is about the intake path, not those rows. Do not just re-close them.

## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "CASE-20260730-FBORPH" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error
