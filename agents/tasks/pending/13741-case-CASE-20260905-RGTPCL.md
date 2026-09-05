---
id: "13741"
title: "Bug: Platform — [Review-gate 2026-09-05] GAP 2 redo — supersedes CASE-20260905-4C2632, whose bra"
complexity: medium
priority: high
branch: "case-CASE-20260905-RGTPCL"
case_id: "CASE-20260905-RGTPCL"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "99604a9d-313e-4652-8e0f-eaa853420c7b"
team: "team2"
---

# Task: Bug: Platform — [Review-gate 2026-09-05] GAP 2 redo — supersedes CASE-20260905-4C2632, whose bra

## Context
No additional context provided.

## Requirements
[Review-gate 2026-09-05] GAP 2 redo — supersedes CASE-20260905-4C2632, whose branch was NOT MERGED because it invented the very equivalence the brief forbade, and got it backwards.

WHAT THE REJECTED BRANCH DID (origin/case-CASE-20260905-4C2632, commit 163b1d4f — do not merge it):
  normaliseCode() was changed to parseInt(trimmed, 10) before re-padding, so '001' -> '01', and a
  test was added asserting remedyForFaultText('printer status 001') === 'close the print head'.
  Its stated justification is its OWN source file: the \d{1,3} regex in remedyForFaultText and the
  fact that S1_FAULT_REMEDIES keys are 2 characters. That is not a source; it is the code arguing
  with itself. The brief said: "If the manual settles the digit width and zero-padding behaviour,
  cite it. If not, do NOT guess — raise the issue rather than invent equivalence."

THE MANUAL DOES NOT SETTLE IT, AND THAT WAS ALREADY ANSWERED. Clarification answer RGRMDY-q1/q2
(scripts/hi_review_gate_answers_0831_round2.py) recorded the finding: all four transcribed files in
backend/app/data/printer_manual/ are the B-EX6T SERIES *Owner's* Manual (5.1 Error Messages,
Appendix 1 Messages and LEDs, Appendix 3, Appendix 4) and contain ZERO numeric status codes. The
numeric TPCL status digits come from the *Programming/Interface* manual, which is not in the repo.
RGRMDY-q2 answered explicitly: "DO NOT normalise numerically, and do not strip a leading zero."

AND THE INVENTED MAPPING IS FACTUALLY WRONG, which is why this is a defect and not a style note.
The 3-digit string is not a zero-padded 2-digit code. Per the B-SA4T Program Manual 3rd Ed. section
9.1.1 STATUS FORMAT, transcribed in scripts/print_cloud_fix_case6_0831.py:

    SOH STX <status:2> <status type:1> <remaining count:4> ETX EOT CR LF

so the live-captured frame "0010000" is status '00' (ON LINE, ready), type '1' (reply to a status
request), remaining '0000'. It is NOT status '001', and '001' is NOT '01' (HEAD OPEN). The rejected
branch would print "close the print head" to an operator whose printer is online and idle — a
fabricated diagnosis on a healthy machine, in the one module whose own header comment records that
this feature has invented plausible printer strings three times already.

BUILD EXACTLY THIS, in frontend/src/pages/print-cloud/print-cloud-faults.ts (+ its test file):
  1. Do NOT change normaliseCode(). Leave the zero-pad-only behaviour byte-identical.
  2. Add a regression test PINNING the current behaviour for the live frame, with a comment saying
     it is a known, deliberate miss pending the vendor code table so nobody "fixes" it by guessing:
        expect(remedyForFaultText('printer status 001')).toBe('unknown fault, code 001')
  3. Add a short comment in print-cloud-faults.ts recording that the map keys are 2-digit, that the
     agent may report 2 or 3 digits, and that the relationship is UNVERIFIED — and cite 9.1.1's
     status/status-type split as the reason a 3-digit string cannot simply be re-padded.
  4. Say in your run summary that the remedy map cannot fire on a 3-digit report from the
     production B-EX6T1 until the digit width is resolved by the owner.

NOTE for whoever reads the digit question later (do NOT act on it in this case, it needs the owner):
master's agent parser already splits status = payload[0:2] (agent/print-cloud-agent/print_cloud_agent.py:312,
agent/print-cloud-windows/src/pc_worker.py:604, backend/app/static/print_cloud_agent.py:312), so a
current-version agent reports 2 digits and the 3-digit form is an OLD-agent emission. Confirming that
is a separate case, not this one.

FILES: frontend/src/pages/print-cloud/print-cloud-faults.ts, frontend/src/pages/print-cloud/print-cloud-faults.test.ts


[Review-gate 2026-09-05 addendum — CASE-20260905-47820C merged as 568e655d]
The remedy text is now RENDERED TO OPERATORS in three places, not just returned by the helper:
PrintCloudPrintersPage StatusCell ("Fix: <remedy>"), and PrintCloudLabelDesignerPage PrinterBar +
PrintModal status lines. So for the live B-EX6T1 the printers list currently shows the literal string
"Fix: unknown fault, code 001". That is the honest fallback and it stays — do NOT soften it by
suppressing the render, and do NOT make normaliseCode pad 3 digits. Point 4 of your run summary
should now say the operator SEES the unknown-fault fallback on that printer today.

## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "CASE-20260905-RGTPCL" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error
