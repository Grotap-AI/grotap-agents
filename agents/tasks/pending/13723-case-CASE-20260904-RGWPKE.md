---
id: "13723"
title: "Bug: Platform — [Review-gate fix case 2026-09-04 — follow-up to CASE-20260904-6CE470, which WAS"
complexity: medium
priority: high
branch: "case-CASE-20260904-RGWPKE"
case_id: "CASE-20260904-RGWPKE"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "e31b396e-657d-4d5a-8335-beb3f050ede2"
team: "team2"
---

# Task: Bug: Platform — [Review-gate fix case 2026-09-04 — follow-up to CASE-20260904-6CE470, which WAS

## Context
No additional context provided.

## Requirements
[Review-gate fix case 2026-09-04 — follow-up to CASE-20260904-6CE470, which WAS MERGED as 3c7f1ef3. Do NOT re-do the merged work; guards (a)(b)(c)(d) are proven effective and must be CARRIED FORWARD unchanged.]

DEFECT (verified by mutation on the merged code): in frontend/src/pages/scan-m/ScanMWeatherKit.test.tsx, the two guard-(e) tests
  - "(e) magnetic charging path (key 8 = gland) appears in rendered output"
  - "(e) USB-C charging path (key 8 = second USB-C coupler) appears in rendered output"
scan the ENTIRE rendered page (document.body.textContent) for /magnetic charging/i and /second.*USB-C coupler/i. Both phrases occur in six-plus incidental places in ScanMWeatherKitPage.tsx (prose at lines ~175-178, the gland parts-row note ~line 96, SVG <text> labels ~line 543, plate captions). So the tests pass on prose alone and never touch the authoritative source of the fact they claim to guard: the key '8' entry in the PENETRATIONS array (ScanMWeatherKitPage.tsx line ~52).

PROOF: replacing that key-8 PENETRATIONS row with a gland-only version —
  { key: '8', face: 'Lid', hole: '1/2 in NPT', carries: 'Tablet POWER', part: 'Gland, 1/2 in NPT or split' }
— deletes the USB-C charging path from the page's spec table, and BOTH (e) tests still pass (7/7 green). The regression the guard exists to catch is invisible to it. Guards (a)(b)(c)(d) were mutation-tested in the same run and DO fail correctly.

FIX SCOPE (test file only — do not change ScanMWeatherKitPage.tsx behaviour):
1. In ScanMWeatherKit.test.tsx, add `export const PENETRATIONS` to the page module ONLY IF needed (a one-word `export` on line ~44 of ScanMWeatherKitPage.tsx is acceptable and mirrors how PART_GROUPS was already exported by CASE-20260904-6CE470). Prefer asserting on the exported PENETRATIONS array directly.
2. Rewrite the two (e) tests to anchor on the key-8 record specifically:
   - locate the row with key === '8' and assert it exists;
   - assert its `part` field matches BOTH /gland/i AND /magnetic charging/i (the magnetic path), AND /second\b.*(IP68 )?USB-C coupler/i (the USB-C path);
   - assert `carries` still names tablet power (/tablet power/i).
3. Keep a rendered-output assertion too, but scope it to the penetration-schedule table rather than document.body — e.g. render, find the row whose cells contain the key '8', and run the two path regexes against THAT row's textContent only. Do not widen it back to the whole body.
4. Replace the greedy /second.*USB-C coupler/i with a non-greedy, newline-safe pattern ([\s\S]*? or a tighter literal) so it cannot bridge an unrelated "second" earlier in the page to a "USB-C coupler" later.
5. Verify with mutation before you call it done: apply the gland-only key-8 row above and confirm the (e) tests FAIL; restore and confirm 7/7 (or however many) pass. Say so explicitly in the run summary.

FILES: frontend/src/pages/scan-m/ScanMWeatherKit.test.tsx (primary); frontend/src/pages/scan-m/ScanMWeatherKitPage.tsx (at most an `export` keyword on PENETRATIONS).
RUN: from frontend/ — npx vitest run src/pages/scan-m/ScanMWeatherKit.test.tsx ; then npx tsc --noEmit.
No new test libraries. Follow the conventions already in the file (vitest + @testing-library/react, the existing vi.mock block).

## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "CASE-20260904-RGWPKE" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error
