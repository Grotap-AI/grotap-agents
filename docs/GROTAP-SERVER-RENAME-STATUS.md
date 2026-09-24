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
| claudecode-01 | prompt-01-claude | running (intermediate name `claude-code-01`; Cloud+Linux rename is live) |
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
| `claude-code-01` → `prompt-01-claude` | GO rename — live at `178.156.209.112` |
| Plan/STATUS on GitHub for bootstrap | In flight |

## 2026-09-24 — Shadow Harness IP map (supersedes any off-by-one in the roster)

Cloud name and Linux hostname match, except `agent-06-claude`. Jumpbox Cloud+Linux name is `prompt-01-claude` at `178.156.209.112`. SSH alias `agent-0N` is the same IP as `agent-0N-claude`.

| IP | Cloud name | Linux hostname | Notes |
|---|---|---|---|
| 5.161.74.39 | agent-01-claude | agent-01-claude | SSH alias `agent-01`. Running. Not "no IP". |
| 5.161.81.193 | agent-02-claude | agent-02-claude | SSH alias `agent-02` |
| 178.156.222.220 | agent-03-claude | agent-03-claude | SSH alias `agent-03`. Not agent-04-claude |
| 5.161.73.195 | agent-04-claude | agent-04-claude | Running. SSH alias `agent-04` |
| 5.78.178.81 | agent-05-claude | (off, Hillsboro) | OFF / unreachable. SSH alias `agent-05` |
| 5.161.53.103 | agent-06-claude | still `grotap-agent-06-ash` | SSH alias `agent-06`. Set Linux hostname to `agent-06-claude` when SSH works |
| 178.156.209.112 | prompt-01-claude | prompt-01-claude | Jumpbox. Former `claudecode-01` / `claude-code-01`. DNS `claudecode.grotap.com` may still point here |
| 5.161.243.18 | prompt-01-astra | — | Live cpx31 Ashburn, id 167204705. Address was released `agent-21`. Outside Team Claude pool |
| 5.161.80.75 | agent-team-01-astra | — | Live cpx31 Ashburn, id 167204706. Outside Team Claude pool |

The 2026-09-21 row "`05-Agent` → `agent-05-claude` off" is the Hillsboro box above, not `5.161.73.195`.

