# agents/SERVERS.md — Fleet roster (single source of truth; loaded at bootstrap after GLOBAL.md)

## Active dispatch pool

| Server | IP | Hardware / DC | Roles (→ load roles/<module>/MODULE.md + ROLE.md per GLOBAL load order) | Execute slots |
|---|---|---|---|---|
| agent-02 | 5.161.74.39 | cpx21, Ashburn | Intake, Triage, Security Reviewer | 3 |
| agent-03 | 5.161.81.193 | cpx21, Ashburn | Planner, Fix/Logic/Policy/Perf Reviewer | 3 |
| agent-04 | 178.156.222.220 | cpx21, Ashburn — Hetzner console name **"03-Agent"** (ID 122714167). OOM-froze 7/5 (hard reset); keep swap enabled | Execute, Change Reviewer, Rule Enforcer, Build Validator | 3 |
| agent-05 | 5.161.73.195 | cpx21, Ashburn | Pipeline Detail, Audit Filters, Mobile Approvals, Marketing (consolidated from agent-11 4/29: grotap.com site, Meta/Instagram/Facebook, YouTube, TikTok APIs) | 3 |
| agent-06 | 5.78.178.81 | cpx31, Hillsboro | **Deploy Ops + pipeline monitoring** (see below) | 2 |

Routing between roles follows the pipeline graph in `registry.md`; triggers/load-order per role live in each ROLE.md.
Dispatch assignment is owned by the backend 3-min loop + LangGraph orchestrator on Railway (which SSHes to the fleet) — there is no dispatcher daemon on agent-06.

## agent-06 detail (ops/monitoring box — its crons must ALWAYS run; verified live 2026-07-05)
- root cron: `health-monitor.sh` 5m · `deploy-verify.sh` 15m · `dns-watchdog.sh` + `env-validator.sh` daily · Wasabi DR backup (daily Neon dump 00:00 + weekly full Sun 02:00, object-lock-safe dated heartbeats) · `reconcile_dispatch.py` 30m (flock) · fleet CLI update daily · release notes 13:00 · systemd `grotap-status` (status server).
- agent cron: `pipeline_failure_monitor.py` 10m · `deploy_freshness_watchdog.py` 5m · **review gate every 4h** (`review-gate-cron.sh`) · reconcile 30m.
- Deploy Ops roles (trigger → role): merge-to-master → **Deploy Verifier**; verifier FAIL → **Deploy Executor**; before deploy-execute → **Env Validator**; every 5 min → **Health Monitor**; daily / after infra change → **DNS Watchdog**; verifier PASS → **Post-Deploy QA**. Escalate to human when deploy infra itself is broken; hotfix regressions route to agent-04/execute.

## Special hosts — NOT executors, never dispatch, never add to `config.sh` pools
| Host | IP | Purpose |
|---|---|---|
| grotap-cobrowse-01 | 5.161.189.143 | Cobrowse AI support runner (headless Chromium + Agent SDK, `cobrowse-runner` systemd). Dedicated Hetzner project `Cobrowse.Grotap.com` (`HETZNER_COBROWSE_API_TOKEN`); scale with `agents/setup-cobrowse-runner.sh`. ⚠ IP recycled from deleted agent-01 — stale host-key warnings: `ssh-keygen -R 5.161.189.143`. SSH `User agent`. |
| LLM-LOCAL-02 (grotap-llm-01) | 62.238.7.84 | Lane C open-model engine — Ollama + `llama3.2:3b`, Caddy TLS at `https://ollama.grotap.com`, wired to prod via `LOCAL_MODEL_BASE_URL`. |
| GEX44 GPU box | (incoming) | Ordered 7/3 (RTX 4000 Ada 20GB, Hetzner Robot, ETA mid-July) — future primary Lane C engine at `llm-gpu.grotap.com`. HI hold `3adc9488`. |

## Hetzner account map
One active account (**K0281854926**, console.hetzner.cloud). Verified via API 7/4: all cloud servers are visible to the single `HETZNER_API_TOKEN`; `HETZNER_API_TOKEN_2` is DEAD. Cobrowse runners live in their own project/token (above). Account `K0390490726` CANCELLED 6/30.

## Retired / cancelled — never dispatch, never re-add
- **agent-01** (5.161.189.143, deleted 6/29 — IP recycled to cobrowse-01) · **agent-07** (89.167.66.105, gone with cancelled account) · **agent-08** (77.42.42.213, deleted; old dispatch box, role moved to agent-06 4/29).
- **agent-09/10/11** (46.62.184.50/.52/.51, Robot EX44s) — cancelled in Hetzner **Robot** 6/29 (separate from cloud console); they answer ping until their termination date, then get wiped. Verify each shows a cancellation date in Robot.

## New-server onboarding
1. `ssh -i ~/.ssh/grotap_agents root@<IP>`; add an `agent-NN` alias to `~/.ssh/config`.
2. `bash agents/ensure-swap.sh` (script lives in THIS repo — canonical copy; persistent 4 GiB swap — idempotent; OOM has wedged two boxes). No checkout on the box yet? Run it from your local clone: `ssh agent-NN "bash -s" < agents/ensure-swap.sh`.
3. Git auth: install `/home/agent/bin/git-credential-doppler` as `credential.helper` (per GLOBAL) — never a static token.
4. Add to `agents/config.sh` (IP, roles, overflow flag); verify it appears in `./agents/server-status.sh` before dispatching.
