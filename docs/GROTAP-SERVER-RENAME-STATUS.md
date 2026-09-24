# Execution status — rename + OpenReplay AI Support
Updated: 2026-09-21 evening PT (box clock ~ Sep 22 02:18 UTC)

## Hetzner Cloud renames — DONE

| Old | New | Status |
|-----|-----|--------|
| 01-Agent | agent-01-claude | running |
| 02-Agent | agent-02-claude | running |
| 03-Agent | agent-03-claude | running |
| 04-Agent | agent-04-claude | running |
| 05-Agent | agent-05-claude | off |
| agent-06-ash | agent-06-claude | running |
| agent-20 | agent-10-codex | running |
| agent-40 | monitor-01-deepseek | running |
| grotap-cobrowse-01 | openreplay-01 | running |
| grotap-runner-01 | openreplay-ai-support | running |
| claudecode-01 | claude-code-01 | running |
| mdm-01 / forge-01 / maps-01 / scan-01 | unchanged (already correct) | running |

Linux hostname set on: openreplay-ai-support, openreplay-01, agent-01..04-claude.
Other boxes: Cloud name done; Linux hostname may still be old where SSH key missing from Desktop1.

## OpenReplay AI Support — DONE / LIVE wire

- Claim API with X-Node-Secret: runner-status 200 enabled=true; claim 204 (empty queue) — FIXED/healthy
- Duplicate cobrowse-runner on openreplay-01: DISABLED
- support-runner on openreplay-ai-support: ACTIVE, RUNNER_ID=openreplay-ai-support, rebuilt
- Offline fixture tests: 4/4 passed (attach → screenshot → point → close)
- OpenReplay dashboard login smoke: PASSED (agent JWT login works on supportagents.grotap.com)
- OpenReplay platform: Assist/frontend/api pods Running; public site HTTP 200

## Still needs a live customer session to prove end-to-end

Queue depth is 0 — no Help → AI Support session is waiting. When a user starts AI Support in the app, this runner should claim it and join Assist. That live path is the remaining proof.

## Product features this stack unlocks when a session is claimed

1. Live Assist view (OpenReplay Assist)
2. Vision LLM chat replies
3. Point / draw / clear annotations (guide-only, no remote control)
4. Session heartbeat / end / escalate
5. Screen-context docs when backend attaches them
6. Optional data-bridge (subscription / recent support history) when enabled

## Do not retire

openreplay-ai-support is the Strong Feature host — keep it.


## 2026-09-23 — Astra provision + jumpbox rename (GO)

| Item | Status |
|------|--------|
| `prompt-01-astra` | GO provision Ashburn — Agent Infrastructure |
| `agent-team-01-astra` | GO provision Ashburn — Agent Infrastructure |
| `claude-code-01` → `prompt-01-claude` | GO rename — Agent Infrastructure |
| Plan/STATUS on GitHub for bootstrap | In flight |

