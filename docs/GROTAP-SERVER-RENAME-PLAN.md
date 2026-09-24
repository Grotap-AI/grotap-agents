# Grotap server rename plan

**Status:** DRAFT - naming convention locked; not live until you say go.
**Date:** 2026-09-21 (PT)
**Convention:** type-first · hyphen · zero-padded number (example: `mdm-01`, `agent-01-claude`)

## Naming rules

1. No `Hetz` prefix.
2. Lowercase + hyphens everywhere (Hetzner Cloud name and Linux hostname match).
3. Type first so the console sorts by role: `agent-*`, `monitor-*`, then platform jobs.
4. Numbers are zero-padded two digits: `-01`, `-02`, `-10`.
5. Name reflects model or job on that metal.

Number bands for agents:
- **01-09** = Claude workers (Team Claude)
- **10-19** = Codex / OpenRouter builders (Team Builder)
- **monitor-NN-*** = monitors (Team Monitor)

---

## Full inventory - new name, what it does, activity, notes

### Agent / fleet

| Current | NEW name | What it does | Activity (recent) | Notes |
|---------|----------|--------------|-------------------|-------|
| `01-Agent` | **agent-01-claude** | Team Claude worker - Claude Sonnet jobs | Light-moderate CPU (~3-4% 24h) | Keep |
| `02-Agent` | **agent-02-claude** | Team Claude worker | Light (~1%) | Keep |
| `03-Agent` | **agent-03-claude** | Team Claude worker | Moderate (~8%) | Keep |
| `04-Agent` | **agent-04-claude** | Team Claude worker | Light (~2%) | Keep |
| `05-Agent` | **agent-05-claude** | Team Claude worker (powered off) | Off | Rename for clean inventory; power on only if needed |
| `agent-06-ash` | **agent-06-claude** | Team Claude worker in Ashburn | Light (~3%) | Keep - Ashburn Claude stack |
| `agent-20` | **agent-10-codex** | Team Builder - GPT Codex via OpenRouter | Light (~3%) | Keep - only live builder today |
| (none yet) | **agent-11-codex** | Reserved 2nd Codex builder | n/a | Create metal only when you want a second builder |
| `agent-40` | **monitor-01-deepseek** | Team Monitor - DeepSeek via OpenRouter | Light (~2%) | Keep |

### Platform

| Current | NEW name | What it does | Activity (recent) | Notes |
|---------|----------|--------------|-------------------|-------|
| `mdm-01` | **mdm-01** | MDM - manage/support customer tablets & hardware (monthly fee) | Quiet CPU (~1%) | **Critical pool** - keep 24/7 even when quiet. Name already matches convention. |
| `grotap-cobrowse-01` | **openreplay-01** | Self-hosted OpenReplay (k3s, ClickHouse, Assist, coturn) at supportagents.grotap.com | Heavy (~50% 24h) | Misnamed "cobrowse". Load is OpenReplay stack, not Cobrowse.io. Keep; kill leftover cobrowse-runner service. |
| `grotap-runner-01` | **openreplay-ai-support** | OpenReplay AI assist session runner (Playwright) | Near idle (~0.7%); claim API failing | **Strongest retire candidate** after Assist works on openreplay-01 alone |
| `claudecode-01` | **prompt-01-claude** | Claude Code jumpbox / tooling at `178.156.209.112` | Regular (~9%) | Keep. Aaron override: jumpbox rename is ON. Was `claude-code-01`. DNS `claudecode.grotap.com` unchanged. Separate from `prompt-01-astra` `5.161.243.18`. |
| `forge-01` | **forge-01** | Build / forge | Light with spikes (~5%) | Keep - name already close |
| `maps-01` | **maps-01** | Maps service | Light steady (~3%) | Keep |
| `scan-01` | **scan-01** | ClamAV / malware scan | Quiet between scans (~1%) | Keep |

---

## What we can retire (or stop paying for)

| Target | Action | When | Why |
|--------|--------|------|-----|
| **openreplay-ai-support** (today `grotap-runner-01`) | **Retire / delete** after confirming Assist | After Assist sessions work from openreplay-01 (or one dedicated runner you keep) | Duplicate assist path; idle; claim loop broken; clearest unused spend |
| **cobrowse-runner.service** on openreplay-01 | **Disable & remove** now (service, not the whole VM) | As soon as you approve ops cleanup | Broken (404/500 claims); product policy is NO cobrowse |
| **agent-05-claude** (today `05-Agent`) | Keep name, leave **powered off** or delete if you will not use a 5th Claude worker | Optional | Already off - only pay storage/IP if Hetzner still bills the off VM |
| Cobrowse.io dependency / any cobrowse app paths | Already policy: never restore | Ongoing | Replaced by OpenReplay Assist + MDM remote for tablets |
| Old missing boxes (agent-21/41, GPU/Team3, Lane C) | Already gone - do not recreate under old names | - | Leaner fleet is intentional |

**Do not retire:** mdm-01, openreplay-01 (after rename), Claude agents 01-04/06, agent-10-codex, monitor-01-deepseek, prompt-01-claude (was claude-code-01), forge/maps/scan.

---

## Sorted preview (Hetzner console)

```
agent-01-claude
agent-02-claude
agent-03-claude
agent-04-claude
agent-05-claude
agent-06-claude
agent-10-codex
agent-11-codex          (future only)
prompt-01-claude
forge-01
maps-01
mdm-01
monitor-01-deepseek
openreplay-01
openreplay-ai-support    (retire candidate)
scan-01
```

---

## Docs / UI labels (not server names)

- Team Claude / Team Builder / Team Monitor
- Pipe Claude / Pipe OpenRouter
- Live code: Lane A = OpenRouter, Lane B = Claude (do not flip in first rename pass)

---

## Execution (after you say go)

1. Freeze this file.
2. Label dashboard with new names beside old.
3. Rename Hetzner Cloud names (API).
4. Set Linux hostnames to match.
5. Chase Doppler, scripts, SSH config, runner IDs.
6. Disable cobrowse-runner; then retire openreplay-ai-support when Assist is proven.

**Not in first pass:** Lane A/B DB rename, deleting openreplay-01, creating agent-11-codex.


---

## 2026-09-23 addendum — Prompt / Agent Team / Astra (Aaron GO)

Naming stays type-first · lowercase · hyphens. Cloud name = Linux hostname.

| Action | Name | Role |
|--------|------|------|
| **Live** | `prompt-01-astra` `5.161.243.18` | Prompt Option — GPT-6 Astra (`gpt-6-astra`), cpx31 Ashburn, id 167204705. Running |
| **Live** | `agent-team-01-astra` `5.161.80.75` | Agent Team — GPT-6 Astra, cpx31 Ashburn, id 167204706. Running |
| **Rename ON** | `prompt-01-claude` `178.156.209.112` | Jumpbox. Aaron override: rename from `claudecode-01` / `claude-code-01` is ON. DNS `claudecode.grotap.com` unchanged. Running. Not `prompt-01-astra`. |

Constraints:
- Do not put Astra boxes in the Team Claude `agent-0N-claude` pool.
- Do not create `agent-11-codex` unless asked.
- Do not retire `openreplay-ai-support`.
- Bootstrap source of truth after merge: this plan + `SERVERS.md` / `agents/config.sh` in grotap-agents (and platform stub if present).

Why multiple Claude workers exist: parallel **throughput** (concurrent sessions), not faster single-job latency. Astra gets speed the same way — dedicated seats, not more Claude boxes.

## 2026-09-24 — locked live map (Shadow metal PASS)

This table is the IP authority. SSH alias `agent-01` is `agent-01-claude` at `5.161.74.39`. `agent-02` is `agent-02-claude` at `5.161.81.193`. Same number, same IP. `prompt-01-claude` is the current jumpbox name. `agent-04-claude` is running.

| Cloud name | IPv4 | Status |
|---|---|---|
| prompt-01-claude | 178.156.209.112 | running (was claude-code-01; DNS claudecode.grotap.com unchanged) |
| prompt-01-astra | 5.161.243.18 | running (cpx31 Ashburn, id 167204705) |
| agent-team-01-astra | 5.161.80.75 | running (cpx31 Ashburn, id 167204706) |
| agent-01-claude | 5.161.74.39 | running |
| agent-02-claude | 5.161.81.193 | running |
| agent-03-claude | 178.156.222.220 | running |
| agent-04-claude | 5.161.73.195 | running |
| agent-05-claude | 5.78.178.81 | OFF Hillsboro |
| agent-06-claude | 5.161.53.103 | running |
| agent-10-codex | 87.99.148.22 | Cloud OK |
| monitor-01-deepseek | 178.156.219.232 | Cloud OK |

Footnotes: Linux hostname on `agent-06-claude` is `agent-06-claude`. Live ops is on `agent-06-claude` (`5.161.53.103`), not on OFF Hillsboro `agent-05-claude`. `agent-10-codex` Linux hostname may still be `agent-20`. `monitor-01-deepseek` Linux hostname may still be `agent-40`.
