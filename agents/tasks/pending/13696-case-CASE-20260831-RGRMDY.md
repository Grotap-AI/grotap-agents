---
id: "13696"
title: "Bug: Platform — [Review-gate follow-up 2026-08-31 to CASE-20260831-AD4E81, which WAS merged (7e4"
complexity: medium
priority: high
branch: "case-CASE-20260831-RGRMDY"
case_id: "CASE-20260831-RGRMDY"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "d4df32ad-68d7-4466-98e5-d171161e0f3a"
team: "team3"
---

# Task: Bug: Platform — [Review-gate follow-up 2026-08-31 to CASE-20260831-AD4E81, which WAS merged (7e4

## Context
No additional context provided.

## Requirements
[Review-gate follow-up 2026-08-31 to CASE-20260831-AD4E81, which WAS merged (7e463a3f). Both gaps
below fail safe — nothing is fabricated and nothing is broken — so the branch shipped and these are
the leftovers. Build on top of master; do not redo the merged work.]

GAP 1 — the remedies render in only ONE of the three places the brief named.
AD4E81's brief ends: "Render remedies in the printers list and picker." The branch rendered them
only in frontend/src/pages/print-cloud/PrinterMonitorDrawer.tsx (status lamp, job error rows, and
the reported-faults list). The printers LIST (PrintCloudPrintersPage.tsx) and the PICKER (the
printer dropdowns in PrintCloudLabelDesignerPage.tsx, ~lines 677 and 1633) show nothing.
  - Use the helpers that already exist and are merged: `faultRemedy`, `isS1FaultCode` and
    `remedyForFaultText` from ./print-cloud-faults. Do not write a second copy of the map.
  - Decide and state what "in the picker" should mean before you build it: a dropdown option is one
    line of text and stuffing a remedy sentence into it is likely worse UX than a short fault tag
    with the remedy on hover/next to the selected printer. If you conclude the picker should NOT
    carry the full remedy text, say so with your reasoning and implement the lighter treatment —
    that is an acceptable outcome, silently skipping it is not.
  - The printers list is the less ambiguous half: there is already an OnlineChip column
    (PrintCloudPrintersPage.tsx:588); a faulted printer showing its remedy there is the point of
    the case.

GAP 2 — a 3-digit status code never matches the remedy map, and the only real captured frame is
3-digit.
`normaliseCode` in print-cloud-faults.ts zero-pads to TWO characters and otherwise passes the value
through, and every key in S1_FAULT_REMEDIES is 2 characters. But the agent's parser
(_parse_status_response, commit a8a22749) emits a status field that is "2 or 3 digits — length is
not fixed", and the one frame captured live from the production B-EX6T1 decodes to status "001".
Measured against the merged code:
    remedyForFaultText('printer status 001')  ->  "unknown fault, code 001"
    remedyForFaultText('printer status 13')   ->  "load media"
    remedyForFaultText('printer status 013')  ->  "unknown fault, code 013"
So on the actual printer in production every remedy lookup misses and the operator is shown
"unknown fault, code 001" instead of an instruction. It degrades honestly, which is why this did
not block the merge — but the feature does not fire on the real device.
  DO NOT "fix" this by blindly stripping a leading zero. "001" and "01" being the same fault is an
  ASSUMPTION, and assuming a mapping between printer status codes is exactly what got
  CASE-20260831-C1B6FC reverted in this same run. Establish the relationship first:
    · There is a printer manual already ingested in this app — see
      frontend/src/pages/print-cloud/PrinterManualPanels.tsx and `usePrinterManual`, whose tests
      reference manual section 5.1 (remedies) and Appendix 1 (LED patterns). START THERE: if the
      manual gives the code table, it settles both the digit width and whether the owner's 8 codes
      are 2- or 3-digit forms, and it is a citable source.
    · If the manual does not settle it, do NOT guess. Normalise by COMPARING NUMERIC VALUES only if
      you can cite a source that says the field is a zero-padded integer; otherwise leave the
      lookup strict and raise the question rather than inventing an equivalence.
  Add a test either way that pins the behaviour for the captured live frame "printer status 001",
  so whichever answer is correct is locked in with its justification in a comment.

OUT OF SCOPE: the remedy table's CONTENTS. Those 8 codes and their text came from the owner in the
AD4E81 brief and are the verified source — do not extend, reword or "complete" the table.


## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "CASE-20260831-RGRMDY" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error
