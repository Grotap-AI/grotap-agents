---
id: "13913"
title: "Bug: Platform — [Review-gate 2026-09-05] Frontend/backend still disagree on the PITCH rule — the"
complexity: medium
priority: high
branch: "case-CASE-20260905-RGPTCH"
case_id: "CASE-20260905-RGPTCH"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "bbceb3b6-07c2-4a8d-b75a-987c21274fa2"
team: "team2"
---

# Task: Bug: Platform — [Review-gate 2026-09-05] Frontend/backend still disagree on the PITCH rule — the

## Context
No additional context provided.

## Requirements
[Review-gate 2026-09-05] Frontend/backend still disagree on the PITCH rule — the half CASE-20260905-B158A6 left behind.

CASE-20260905-B158A6 merged at 3d409cdb and correctly made the WIDTH test overflow-only in
frontend/src/pages/print-cloud/PrintCloudLabelDesignerPage.tsx :: mediaFitWarning(). Its sibling
CASE-20260905-38258E merged the matching backend change in
backend/app/services/label_compiler.py :: validate_geometry(). Width now agrees on both sides.

PITCH DOES NOT AGREE, and the two sub-briefs are why: the decomposed brief for B158A6 said "Keep the
pitch test symmetric as-is", but the parent case CASE-20260831-RG0003 explicitly SUPERSEDES that
line — "width = overflow only ...; pitch/height = overflow only ... NOTE this supersedes the 'leave
the PITCH test symmetric' line earlier in this case — the backend already implements pitch as
overflow-only and that is the behaviour to keep; do not make the two sides disagree on pitch in the
course of aligning them on width." The agent followed the stale sub-brief, so master now has:

    frontend  pitchOk = Math.abs(pitchMm - label_pitch_mm) <= GEOMETRY_TOLERANCE_MM   (symmetric)
    backend   tmpl_h <= lp + _GEO_TOL_MM                                              (overflow-only)

THIS IS A BLOCK, NOT A BANNER. PrintCloudLabelDesignerPage.tsx computes
`const canPrint = !!printerId && !busy && !geometryWarning && ...`, so a template whose pitch is more
than 2 mm SHORTER than the printer's recorded pitch disables the Print button while POST
/print-cloud/.../print would accept it. That is exactly the UI-refuses-what-the-API-allows
disagreement the RG0003 family exists to remove, just on the other axis.

REQUIRED:
  * mediaFitWarning(): change the pitch test to overflow-only —
    `const pitchOk = label_pitch_mm == null || pitchMm <= label_pitch_mm + GEOMETRY_TOLERANCE_MM`.
  * Fix the comment B158A6 added directly above it. It currently reads "pitch/height: symmetric",
    which contradicts both the backend and its own next clause ("a taller label blocks"). Both sides
    must state the SAME rule in the same words: width and pitch/height allow overflow only — a
    narrower or shorter template passes, a wider template or a taller label blocks.
  * The mismatch MESSAGE text stays as it is; only the predicate changes.

DO NOT also change the width test (already correct) and do not touch validate_geometry (already
correct). Sibling CASE-20260905-8A4FA9 adds the mediaFitWarning unit tests — if it has already run
when you pick this up, update its pitch case rather than duplicating the file; if it has not, add
the shorter-pitch-passes / taller-pitch-blocks cases here so the rule is pinned either way.

Still latent in production: every print_cloud.printers row has NULL media geometry, so
mediaFitWarning() returns null and neither half fires until an operator records geometry.

FILES: frontend/src/pages/print-cloud/PrintCloudLabelDesignerPage.tsx (+ mediaFitWarning tests)


## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "CASE-20260905-RGPTCH" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error
