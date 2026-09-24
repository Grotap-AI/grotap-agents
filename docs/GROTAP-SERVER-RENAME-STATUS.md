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
| claudecode-01 | prompt-01-claude | running. Aaron override: jumpbox rename is ON (was `claude-code-01`). DNS `claudecode.grotap.com` unchanged. `178.156.209.112` |
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


## 2026-09-24 — locked live map (Shadow metal PASS)

Aaron override: jumpbox rename is ON. `prompt-01-claude` at `178.156.209.112` is the current Cloud name (from `claudecode-01` / `claude-code-01`). `prompt-01-astra` at `5.161.243.18` is a separate host. Short alias `agent-0N` is the same IPv4 as `agent-0N-claude`. `agent-04-claude` is running. `agent-05-claude` is OFF in Hillsboro. `agent-team-01-astra` is `5.161.80.75`.

| Cloud name | IPv4 | Status |
|---|---|---|
| prompt-01-claude | 178.156.209.112 | running (was claude-code-01; DNS claudecode.grotap.com unchanged) |
| prompt-01-astra | 5.161.243.18 | running (cpx31 Ashburn, Hetzner id 167204705) |
| agent-team-01-astra | 5.161.80.75 | running (cpx31 Ashburn, Hetzner id 167204706) |
| agent-01-claude | 5.161.74.39 | running |
| agent-02-claude | 5.161.81.193 | running |
| agent-03-claude | 178.156.222.220 | running |
| agent-04-claude | 5.161.73.195 | running |
| agent-05-claude | 5.78.178.81 | OFF Hillsboro |
| agent-06-claude | 5.161.53.103 | running |
| agent-10-codex | 87.99.148.22 | Cloud OK |
| monitor-01-deepseek | 178.156.219.232 | Cloud OK |

Footnotes: Linux hostname on `agent-06-claude` is `agent-06-claude`. Live ops (`grotap-status`, `cloudflared`, `review-gate.timer`, deploy-ops crons) is on `agent-06-claude` at `5.161.53.103`, not on OFF `agent-05-claude`. `agent-10-codex` Linux hostname may still be `agent-20`. `monitor-01-deepseek` Linux hostname may still be `agent-40`. The 2026-09-21 row "`05-Agent` → `agent-05-claude` off" is `5.78.178.81`. `5.161.73.195` is running `agent-04-claude`.

