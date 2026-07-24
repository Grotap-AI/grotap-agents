---
id: "13029"
title: "Bug: llrp — Fix C1G2SingulationControl Session bit placement in services/llrp/src/rospec.ts"
complexity: medium
priority: normal
branch: "case-CASE-20260722-LLRPFX"
case_id: "CASE-20260722-LLRPFX"
callback_url: "https://api.grotap.com/pipeline/webhook/agent-progress"
dispatch_id: "876d8cb3-ad17-4317-ac95-5a970ab5750e"
team: "team2"
team_fallback: true
---

# Task: Bug: llrp — Fix C1G2SingulationControl Session bit placement in services/llrp/src/rospec.ts

## Context
Component: llrp

## Requirements
Fix C1G2SingulationControl Session bit placement in services/llrp/src/rospec.ts (~line 38).

Session is currently written as `(2 << 1)`, placing it in bits [2:1]. Per EPCglobal LLRP / C1G2SingulationControl (and sllurp), the Session field occupies the TOP 2 bits of that byte and must be `(session << 6)`. As-is, a real reader decodes Session=0 (wrong inventory session), misconfiguring physical hardware. The module's codec framing/encode/decode round-trips are UNAFFECTED (SingulationControl is extra scaffolding not in the task spec and not covered by tests).

SCOPE: correct the shift to `<< 6`; add a bit-layout / round-trip unit assertion for SingulationControl so it is covered. Low priority - no data corruption, only affects live CS463 reader configuration.
FILE: services/llrp/src/rospec.ts (+ services/llrp/src/__tests__/llrp.test.ts).
GATE: `cd services/llrp && npm test` must pass.

## Acceptance Criteria
- [ ] Changes address the reported issue
- [ ] All existing tests pass (tsc --noEmit, py_compile)
- [ ] Branch pushed and ready for review

## Progress Reporting
When available, report progress by running:
```bash
bash ~/grotap-agents/agents/scripts/report-progress.sh "CASE-20260722-LLRPFX" "<status>" "<message>"
```
Call this at each stage:
- "executing" — when you start building
- "change_review" — after pushing code, before review
- "done" — when task is fully complete
- "failed" — if you encounter an unrecoverable error
