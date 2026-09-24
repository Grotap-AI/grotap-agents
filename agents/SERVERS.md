# agents/SERVERS.md — Fleet roster (single source of truth; loaded at bootstrap after GLOBAL.md)

Bootstrap names are the locked Cloud names, not `agent-NN`. Map, status, and the Astra GO:
`docs/GROTAP-SERVER-RENAME-PLAN.md`, `docs/GROTAP-SERVER-RENAME-STATUS.md`,
`docs/GROTAP-PROMPT-ASTRA-PROVISION.md`.

Cloud renames already applied (2026-09-21, jumpbox Cloud+Linux rename live): `agent-01-claude` … `agent-06-claude`,
`agent-10-codex`, `monitor-01-deepseek`, `openreplay-01`, `openreplay-ai-support`,
**`prompt-01-claude`** at `178.156.209.112` is the current jumpbox Cloud name (was `claudecode-01`, then `claude-code-01`; DNS `claudecode.grotap.com` unchanged).
Live Ashburn, outside the Team Claude pool: **`prompt-01-astra`** `5.161.243.18` (Hetzner id 167204705), **`agent-team-01-astra`** `5.161.80.75` (id 167204706)
(`gpt-6-astra`, cpx31). Do not create `agent-11-codex`. Do not retire `openreplay-ai-support`.

**Hetzner Cloud name is the primary column.** Short names `agent-01` … `agent-06` are SSH/dispatch aliases only. Each one is the **same IP** as `agent-01-claude` … `agent-06-claude`. `ssh agent-01` is `5.161.74.39`. Do not point `agent-01-claude` at `agent-02`.

## Provisioning rule — ASHBURN ONLY (owner, 2026-09-20)

Every **new** Hetzner server for the fleet is created in **`ash`** (Ashburn, VA). No FSN1, NBG1,
HEL1, HIL or SIN for new capacity. Existing non-Ashburn boxes get moved or retired on a schedule.

Why: the control plane moved to Neon `aws-us-east-1` on 2026-09-20, and fleet-to-database TCP
connect measures **4.2 ms** from Ashburn against **81.0 ms** from the old us-west-2 pairing.
Team 3's FSN1 box also proved the second cost of EU placement — grok-4.5 is xAI-region-blocked
from EU egress, which is why that team had to run a different, weaker model ladder.

Enforced in the grotap-platform repo by `agents/scripts/require-ashburn.sh`, which both
provisioners call before they POST to `/v1/servers`. It refuses any location other than `ash`,
**and refuses an empty one** — the Hetzner API reads a missing location as "any datacenter with
capacity", which is how you land in the EU without anyone choosing it. Covered by
`agents/tests/test_require_ashburn.sh` (grotap-platform).

A default is not a constraint: both scripts already *defaulted* to `ash`, yet
`LOCATION=fsn1 bash agents/setup-claude-app-runner.sh` still built in Germany until the guard
landed.

Deliberate exception: `ALLOW_NON_ASHBURN=1 <command>`, which warns loudly on stderr. Record the
reason here, so the next reader can tell an exception from a mistake.

## Locked live map (Shadow metal PASS, 2026-09-24)

Aaron override: jumpbox rename is ON. `prompt-01-claude` at `178.156.209.112` is the current Cloud name (from `claudecode-01` / `claude-code-01`; DNS `claudecode.grotap.com` unchanged). `prompt-01-astra` at `5.161.243.18` is a separate host. Short aliases `agent-01` … `agent-06` are the same IPv4 as `agent-01-claude` … `agent-06-claude`. `agent-04-claude` is running. `agent-05-claude` is the Hillsboro box that is off. `agent-team-01-astra` is `5.161.80.75`.

| Cloud name | IPv4 | Status |
|---|---|---|
| prompt-01-claude | 178.156.209.112 | running (was claude-code-01; DNS claudecode.grotap.com unchanged) |
| prompt-01-astra | 5.161.243.18 | running |
| agent-team-01-astra | 5.161.80.75 | running |
| agent-01-claude | 5.161.74.39 | running |
| agent-02-claude | 5.161.81.193 | running |
| agent-03-claude | 178.156.222.220 | running |
| agent-04-claude | 5.161.73.195 | running |
| agent-05-claude | 5.78.178.81 | OFF Hillsboro |
| agent-06-claude | 5.161.53.103 | running |
| agent-10-codex | 87.99.148.22 | Cloud OK |
| monitor-01-deepseek | 178.156.219.232 | Cloud OK |

Footnotes: Linux hostname on `agent-06-claude` is `agent-06-claude`. `agent-10-codex` Linux hostname may still be `agent-20`. `monitor-01-deepseek` Linux hostname may still be `agent-40`. `5.161.189.143` is `openreplay-01`. Live ops (`grotap-status`, `cloudflared`, `review-gate.timer`, deploy-ops crons) run on `agent-06-claude`.

## Active dispatch pool

Roles stay on the IP in the locked map. SSH alias is not a Hetzner name.

| Cloud name | IP | Linux hostname | SSH alias (not a Cloud name) | Hardware / DC | Roles | Execute slots |
|---|---|---|---|---|---|---|
| agent-01-claude | 5.161.74.39 | agent-01-claude | `agent-01` | cpx21, Ashburn. **Running** | Intake, Triage, Security Reviewer | 3 |
| agent-02-claude | 5.161.81.193 | agent-02-claude | `agent-02` | cpx21, Ashburn. **Running** | Planner, Fix/Logic/Policy/Perf Reviewer | 3 |
| agent-03-claude | 178.156.222.220 | agent-03-claude | `agent-03` | cpx21, Ashburn. **Running**. Console was **"03-Agent"** (ID 122714167). OOM-froze 7/5 (hard reset); keep swap enabled | Execute, Change Reviewer, Rule Enforcer, Build Validator | 3 |
| agent-04-claude | 5.161.73.195 | agent-04-claude | `agent-04` | cpx21, Ashburn. **Running** | Pipeline Detail, Audit Filters, Mobile Approvals, Marketing (consolidated from agent-11 4/29: grotap.com site, Meta/Instagram/Facebook, YouTube, TikTok APIs) | 3 |
| agent-05-claude | 5.78.178.81 | (off; Hillsboro) | `agent-05` | Hillsboro. **OFF**. | Do not dispatch while it is off. Ops is on `agent-06-claude` | 2 |
| agent-06-claude | 5.161.53.103 | agent-06-claude | `agent-06` | Ashburn. **Running** | Team Claude worker and live ops host (was `agent-06-ash`). `grotap-status`, `cloudflared`, `review-gate.timer` active | 2 |

Routing between roles follows the pipeline graph in `registry.md`; triggers/load-order per role live in each ROLE.md.
**forgejo-runner v13.1.0** (systemd unit `forgejo-runner.service`, installed 2026-09-15) is on the five pre-rename worker IPs, now `agent-01-claude` through `agent-05-claude`. `agent-05-claude` is off, so that runner is down with the box. HOST execution mode: CI jobs run natively as the unprivileged `forge-runner` user in a systemd jail (`ProtectSystem=strict`, `ProtectHome=tmpfs`, `NoNewPrivileges`, empty `CapabilityBoundingSet`), no Docker. Labels `ubuntu-latest:host` and `ubuntu-24.04:host`, capacity 2 per box, registered org-wide to `Grotap-AI` on forge-01. It is independent of the agent tmux sessions and of `dispatch.sh`.

Dispatch assignment is owned by the backend 3-min loop + LangGraph orchestrator on Railway (which SSHes to the fleet). Live ops is on `agent-06-claude` (`5.161.53.103`): `grotap-status`, `cloudflared`, and `review-gate.timer` are active there, with the deploy-ops crons below.

**SSH key retirement (started 2026-09-16, in progress).** The shared fleet key `grotap_agents` is being
replaced by per-host keys, host by host — it is NOT removed yet and every fleet script still falls back
to it. Phase 1 (2026-09-16 04:01Z): the Hillsboro box (now `agent-05-claude`, off) got per-target keys for both `root` and `agent`
(`~/.ssh/grotap_from06_agent-0{1,2,3,4,5}`). Short alias `agent-01` is `agent-01-claude` at `5.161.74.39`. It is not `agent-02`.
`ssh-key-for.sh` resolves `agent-0N` to `agent-0N-claude` on that same IP.
Phase 2b (same day): every fleet
script that used to hardcode the shared key now resolves it per target through
`agents/scripts/ssh-key-for.sh` (kept byte-identical in both grotap-agents and grotap-platform — see
that file's header), which falls back to the shared key for any target with no per-host pair yet —
GEX131, maps-01, forge-01 and every other special host below included. Do not remove `grotap_agents`
from any box or from `~/.ssh/config` until a later phase says so explicitly.

## agent-06-claude detail (Ashburn ops host — `5.161.53.103`; Linux hostname `agent-06-claude`)
`agent-05-claude` (`5.78.178.81`) is OFF in Hillsboro and is not the ops host.
- Live units: `grotap-status`, `cloudflared`, `review-gate.timer`.
- root cron: `health-monitor.sh` 5m · `deploy-verify.sh` 15m · `dns-watchdog.sh` + `env-validator.sh` daily · Wasabi DR backup (daily Neon dump 00:00 + weekly full Sun 02:00, object-lock-safe dated heartbeats) · `reconcile_dispatch.py` **10m** (flock; runs the git-pulled repo copy `grotap-platform/scripts/` with `--max 6 --days 14 --stale-min 10` — consolidated 2026-07-14, the old frozen `/home/agent/` copy + duplicate agent-cron entry are RETIRED) · fleet CLI update daily · release notes 13:00 · systemd `grotap-status` (status server).
- agent cron: `pipeline_failure_monitor.py` 10m · `deploy_freshness_watchdog.py` 5m · **review gate every 15 min** (`review-gate-cron.sh`; empty queue exits <5s). `review-gate.timer` is active on this host.
- Deploy Ops roles (trigger → role): merge-to-master → **Deploy Verifier**; verifier FAIL → **Deploy Executor**; before deploy-execute → **Env Validator**; every 5 min → **Health Monitor**; daily / after infra change → **DNS Watchdog**; verifier PASS → **Post-Deploy QA**. Escalate to human when deploy infra itself is broken; hotfix regressions route to agent-03-claude/execute (`178.156.222.220`).

## Team Builder (was Team 2) — open-model executors (Hetzner project **OpenAgents.grotapai**, token `HETZNER_FARM_API_TOKEN`)
Provisioned 2026-07-07 for the Team 2 program (cases AA8CFD/F404F8/959C5E). Aider + OpenRouter runtime —
NO claude CLI on these boxes by design. ⚠ NOT in the Team 1 dispatch pool: do not dispatch until the
`config.sh` team registry (F404F8 children) merges and `case_data.team=team2` routing is live.

| Server | IP | Hardware / DC | Purpose | Execute slots |
|---|---|---|---|---|
| agent-10-codex | 87.99.148.22 | cpx21, Ashburn (id 148646754). Cloud name `agent-10-codex`. Linux hostname may still be `agent-20` | Team Builder — GPT Codex via OpenRouter (was Team 2 open-model executor) | 3 |

**Do not create `agent-11-codex`.** That name is reserved for a second builder and has no metal.

Baseline: Ubuntu 24.04, agent user, node 22, doppler CLI + `git-credential-doppler`, aider (pipx),
4 GiB swap, `~/grotap-agents` + `~/grotap-platform` clones, `~/worktrees`. Scale Team Builder by adding
boxes here + the team2 pool in `config.sh` — box CPU is only builds/git, inference is remote (OpenRouter/Lane C).

## Team 3 — Grok 4.5 executors (Hetzner project **OpenAgents.grotapai**, token `HETZNER_FARM_API_TOKEN`)
Provisioned 2026-07-12 for the Grok 4.5 hedge team (cases D15EF4/A5CE1C/A1CD20/6C7435). Aider +
OpenRouter (`x-ai/grok-4.5`) runtime — NO claude CLI by design. **FSN1 on purpose**: same DC as
GEX131 (llm-gpu-02) and attached to Cloud Network `team2-llm-lan` (12438415) — the Ashburn team2
boxes cannot attach (single-zone rule). ⚠ NOT dispatchable until the `config.sh` team3 registry
(case A5CE1C) merges and pilot cases are tagged `case_data.team=team3`.

> **Team 3 has NO servers. Retired 2026-09-20:** `agent-30` (150155427) was deleted from Hetzner
> and its IP `167.233.59.142` released, for the same reason its sibling `agent-31` went on
> 2026-09-16. Verified 2026-09-20 against every Hetzner token in Doppler
> (`HETZNER_API_TOKEN`, `_CLAUDECODE_`, `_COBROWSE_`, `_FARM_`): no server in any project holds
> that address, and `server_connections` has no agent-30 row. Hetzner recycles released IPs, so
> the address now belongs to a stranger — never SSH it, never map it to a fleet host name, never
> put it in a firewall allowlist. Re-provision with `agents/provision-team3.py` before re-adding.

Baseline identical to Team 2 (agent user, node 22, doppler + `git-credential-doppler`, aider via
pipx, 4 GiB swap, both repo clones, `~/worktrees`). Note: cpx21 is not offered in FSN1 — cpx22
(2c/4GB, €22.99/mo) is the closest; EU premium accepted for GEX131 LAN adjacency.

## Team Monitor (was Team 4) — DeepSeek via OpenRouter (Hetzner project **OpenAgents.grotapai**, token `HETZNER_FARM_API_TOKEN`)
Provisioned 2026-07-13 for the GPT-5.6 hedge team (cases B8EF68/FC0208/BA9BC6/8B9BFC —
`docs/GPT56_SOL_TEAM4_PLAN.md` in grotap-platform). Aider + OpenRouter
(`openai/gpt-5.6-luna` rung 1, `openai/gpt-5.6-sol` strong) runtime — NO claude CLI by design.
Ashburn, public-only: inference is OpenRouter-hosted, so no GPU-LAN adjacency (and ash cannot
join the eu-central `team2-llm-lan` anyway). ⚠ NOT dispatchable until the `config.sh` team4
registry (case FC0208) merges and pilot cases are tagged `case_data.team=team4`.
Team 5 note: the Codex CLI runner experiment (case 8B9BFC) SHARES this box by design
(experiment phase; 3 slots/box, inference remote) — revisit if both teams go live.

| Server | IP | Hardware / DC | Purpose | Execute slots |
|---|---|---|---|---|
| monitor-01-deepseek | 178.156.219.232 | cpx21, Ashburn (id 150671577). Cloud name `monitor-01-deepseek`. Linux hostname may still be `agent-40` | Team Monitor — DeepSeek via OpenRouter (provisioned as the Team 4 GPT-5.6 executor) | 3 |

Baseline identical to Team 2/3 (agent user, node 22, doppler + `git-credential-doppler`, aider
via pipx, 4 GiB swap, docker + `grotap-sandbox:latest`, both repo clones, `~/worktrees`).

> **Retired 2026-09-16:** `agent-21` (148646760), `agent-31` (150155432) and `agent-41`
> (150671582) were deleted from Hetzner. Each had ZERO rows in `pipeline_dispatch_log` for its
> entire life; verified empty first (no tmux, no worktrees, clones clean, load 0.00). Their
> siblings agent-10-codex (was agent-20) and monitor-01-deepseek (was agent-40) carry the work and stay (agent-30 followed them on 2026-09-20).
> `TEAM_POOL` in `agents/config.sh` is now single-host for team2/4/5 (grotap-platform
> `5226d7fc9`) and EMPTY for team3 since 2026-09-20. Rebuild specs: cpx21 (cpx22 for
> team3/FSN1), ubuntu-24.04, labels `role=<open-model|grok|gpt>-executor`, `team=team<N>`;
> provision scripts `agents/provision-team{2,3,4}.py`.

## Special hosts — NOT executors, never dispatch, never add to `config.sh` pools
| Host | IP | Purpose |
|---|---|---|
| openreplay-01 | 5.161.189.143 | **OpenReplay session-replay server** — former names `grotap-cobrowse-01`, supportagents. `supportagents.grotap.com`, rescaled to cpx51 + wiped 2026-07-07 (OpenReplay Docker stack, projectId 2); replaces Cobrowse.io. Duplicate `cobrowse-runner` on this host is DISABLED (rename STATUS). Still in Hetzner project `Cobrowse.Grotap.com` (`HETZNER_COBROWSE_API_TOKEN`). ⚠ IP recycled twice (deleted agent-01 → cobrowse-01 → this) — stale host-key warnings: `ssh-keygen -R 5.161.189.143`. |
| scan-01 | 2.28.16.19 | **ClamAV malware-scanning service** — `scan.grotap.com`, self-hosted virus scanning for all uploaded files (owner policy 2026-07-04: file bytes NEVER go to a third-party vendor; VirusTotal stays dormant). cx33 **fsn1** (id 161203518, $8.99/mo), Hetzner main account, provisioned 2026-08-10 — replaces the stack lost when grotap-cobrowse-01 was wiped 2026-07-07. Docker stack `services/clamav-scan/` (Caddy → scanner-api → clamd; 3310 internal only). ⚠ **Deliberately holds NO Doppler token** — it parses hostile files, so `CLAMAV_SCAN_SECRET` is delivered to a root-owned `.env.runtime`, never a prd-wide token. ⚠ DNS A record still PENDING (hold `CASE-20260810-CLAM01-DNS`) — no cert until it lands. Cases: CLAM01 (stack) / CLAM02 (prod env wiring). |
| openreplay-ai-support | 178.156.199.83 | **OpenReplay AI Support runner — KEEP. Do not retire.** Former name `grotap-runner-01`. Live unit `support-runner`, `RUNNER_ID=openreplay-ai-support` (claim API healthy: runner-status 200, claim 204 on an empty queue; rename STATUS 2026-09-21). cpx21 Ashburn (id 149246895), Hetzner project `Cobrowse.Grotap.com` (`HETZNER_COBROWSE_API_TOKEN`), firewall `runner-fw` (inbound ssh+icmp only — runner is outbound-only). Provisioned 2026-07-09. The old `cobrowse-runner` unit is not the live identity. |
| LLM-LOCAL-02 (grotap-llm-01) | 62.238.7.84 | Lane C open-model engine — Ollama + `llama3.2:3b`, Caddy TLS at `https://ollama.grotap.com`, wired to prod via `LOCAL_MODEL_BASE_URL`. |
| GEX131 GPU box (llm-gpu-02) | 178.63.124.99 | **Primary GPU engine (Lane C + Team 2 rung 1)** — RTX PRO 6000 Blackwell Max-Q 96GB, Hetzner Robot FSN1, live 2026-07-10 (GEX44/llm-gpu-01 CANCELLED eff 7/11). Ubuntu 24.04 RAID1, ⚠ GRUB pinned to kernel `6.8.0-124-generic` via `GRUB_DEFAULT=saved` (6.8.0-134 hangs on boot — do NOT unpin without console access). NVIDIA 595.71.05/CUDA 13.2. Ollama loopback :11434 (`gpt-oss:20b`, `gemma4:26b`, `gemma4:31b`, `ornith:9b`), tuned 2026-09-13: `OLLAMA_NUM_PARALLEL=4`, `OLLAMA_FLASH_ATTENTION=1`, `OLLAMA_CONTEXT_LENGTH=131072`, `KEEP_ALIVE=30m` (override.conf; backups `.bak-20260710`, `.bak-20260913`; was 8/65536 — same total KV budget, gemma4:31b 24 GB 100% GPU). Embedding models `qwen3-embedding:4b` (2560-d) + `nomic-embed-text`. Anthropic-compatible `/v1/messages` verified: Claude Code runs against it via `platform/scripts/claude-local.sh`; scripts use `platform/scripts/llm_local.py`. Caddy TLS + bearer (`GEX44_LLM_BEARER` in Doppler) at `https://llm-gpu.grotap.com` (+ `llm-gpu2`). Root SSH = shared fleet key (no per-host key provisioned for this host; `ssh-key-for.sh` falls back to it automatically — see "New-server onboarding" below). |
| mdm-01 | 87.99.140.189 | **Headwind MDM server** — `mdm.grotap.com`, Android tablet fleet management (Device-Owner QR enroll, silent Scan M APK push; remote-control plugin pending owner purchase). cpx21 Ashburn (id 153766531), Docker stack `/opt/hmdm-docker` (hmdm 0.1.8 + postgres:12 on loopback, MQTT `:31000`), UFW 22/80/443/31000, LE renew cron 1st+15th. Secrets `MDM_*` in Doppler. Full doc: `docs/06-infrastructure/mdm-tablets.md`. Provisioned 2026-07-21. |
| prompt-01-claude | 178.156.209.112 | **Claude Code jumpbox. Current Cloud name `prompt-01-claude`.** Was `claudecode-01`, then `claude-code-01`. DNS `claudecode.grotap.com` unchanged. Running. 5-seat remote-control box, Hetzner project `ClaudeCode` (`HETZNER_CLAUDECODE_API_TOKEN`, id 149250118), cpx31 Ashburn. Users user1–5, per-user `claude-remote` systemd units (start only after one-time `claude` → `/login` claude.ai handshake — **subscription login ONLY, NEVER set ANTHROPIC_API_KEY/ANTHROPIC_BASE_URL**). `claudecode-status` service proxied by backend `/claude-code/*` (secret `CLAUDECODE_STATUS_SECRET` in Doppler). Provisioned 2026-07-09 via `platform/scripts/claudecode/provision.sh`; in `update-fleet-cli.sh` roster. Not in the Team Claude `agent-0N-claude` pool. |
| maps-01 | 5.161.107.80 | **Map services: Martin tiles + TiTiler NAIP + Caddy** — `maps.grotap.com` (A record, unproxied, TTL 300 — no AAAA, no wildcard), MAP-1 CASE-20260914-76CACC / leaf 81D5CE. cpx31 **Ashburn** (id 165776284), Hetzner main project (`HETZNER_API_TOKEN`), firewall `maps-fw` (id 11619661: inbound TCP 22/80/443 + ICMP), labels `role=maps,owner=platform`. Provisioned 2026-09-14 — **bootstrap pending** (MAP-1's `bootstrap.sh` deploys the stack; base only so far: Ubuntu 24.04, docker.io + compose v2, ufw 22/80/443, gdal-bin, 2 GiB swap, `/data/{basemap,naip,ortho}`, `/opt/maps/.env` root:600 with `MAPS_SHARED_SECRET` + `MAPS_PUBLIC_HOST`). Root SSH = shared fleet key (no per-host key provisioned for this host; `ssh-key-for.sh` falls back to it automatically — see "New-server onboarding" below). Doppler prd+dev: `MAPS_TILE_BASE_URL`, `MAPS_SHARED_SECRET`, `MAPS_SERVER_IP` (copied to Railway `grotap-backend`). |
| forge-01 | 178.156.246.81 | **Self-hosted git forge (Forgejo 13.0.5)** — `forge.grotap.com` (A record, **proxied**) for HTTPS, `forge-ssh.grotap.com` (A record, **unproxied** — Cloudflare cannot proxy git-over-SSH) on port **2222**. cpx21 **Ashburn** (id 166078095), Hetzner main project (`HETZNER_API_TOKEN`), firewall `forge-fw` (id 11628446: 22 + ICMP from the five worker IPs and the owner workstation only, 80/443 from Cloudflare ranges only, 2222 from the same fleet+workstation set), labels `role=forge,owner=platform`. Provisioned 2026-09-15. Stack in `/opt/forge`: docker compose (Forgejo + Caddy, Let's Encrypt cert on the origin), sqlite3 DB at `/opt/forge/forgejo/gitea/gitea.db`, 2 GiB swap, sshd drop-in `01-grotap-hardening.conf`. Hardened: `DISABLE_REGISTRATION`, `REQUIRE_SIGNIN_VIEW`, `INSTALL_LOCK`, `OFFLINE_MODE`. ⚠ **GitHub is still the source of truth** — all four repos (grotap-platform, grotap-agents, grotap-landing, grotap-platform-docs) are PULL MIRRORS refreshing every 10 min under the `Grotap-AI` org; no deploy path has moved off GitHub. Doppler prd+dev: `FORGE_URL`, `FORGE_SSH_HOST`, `FORGE_SSH_PORT`, `FORGE_SERVER_IP`, `FORGE_API_TOKEN`, `FORGE_ADMIN_USER`, `FORGE_ADMIN_PASSWORD`, `FORGEJO_WEBHOOK_SECRET`. Root SSH = shared fleet key (no per-host key provisioned for this host; `ssh-key-for.sh` falls back to it automatically — see "New-server onboarding" below). |

## Prompt / Astra — not in the Team Claude pool

Not dispatch executors. Not in `config.sh` pools. `5.161.243.18` was released with deleted `agent-21` and is now this Astra host — use the Cloud name, not `agent-21`.

| Cloud name | IP | Role |
|---|---|---|
| prompt-01-astra | 5.161.243.18 | Prompt Option — GPT-6 Astra (`gpt-6-astra`). **Running.** cpx31 Ashburn, Hetzner id 167204705. Outside the Team Claude pool. |
| agent-team-01-astra | 5.161.80.75 | Agent Team — GPT-6 Astra (`gpt-6-astra`). **Running.** cpx31 Ashburn, Hetzner id 167204706. Outside the Team Claude pool. |

## Hetzner account map
One active account (**K0281854926**, console.hetzner.cloud). Verified via API 7/4: all cloud servers are visible to the single `HETZNER_API_TOKEN`; `HETZNER_API_TOKEN_2` is DEAD. Cobrowse runners live in their own project/token (above). Account `K0390490726` CANCELLED 6/30.

## Retired / cancelled — never dispatch, never re-add
- **Deleted agent-01** (5.161.189.143, deleted 6/29 — IP recycled to openreplay-01, former cobrowse-01). That address is not `agent-01-claude`. Live `agent-01-claude` is `5.161.74.39`. · **agent-07** (89.167.66.105, gone with cancelled account) · **agent-08** (77.42.42.213, deleted; old dispatch box). The Hillsboro box is `agent-05-claude` and is OFF. Live ops is `agent-06-claude`.
- **`agent-11-codex`** — reserved name only. Do not provision.
- **agent-09/10/11** (46.62.184.50/.52/.51, Robot EX44s) — cancelled in Hetzner **Robot** 6/29 (separate from cloud console); they answer ping until their termination date, then get wiped. Verify each shows a cancellation date in Robot.

## New-server onboarding
1. `ssh -i ~/.ssh/grotap_agents root@<IP>`; add a `Host` alias for the **Cloud name** (`agent-01-claude`, `agent-10-codex`, `monitor-01-deepseek`, `prompt-01-claude`, `openreplay-01`, …). Short names `agent-01` … `agent-06` may also exist; each one is the same IP as `agent-01-claude` … `agent-06-claude`, and none of them is a Hetzner name. A brand-new box has no per-host key yet, so this first-contact step always uses the shared fleet key regardless of the SSH key retirement above — that's expected, not a regression.
2. `bash agents/ensure-swap.sh` (script lives in THIS repo — canonical copy; persistent 4 GiB swap — idempotent; OOM has wedged two boxes). No checkout on the box yet? Run it from your local clone: `ssh agent-01-claude "bash -s" < agents/ensure-swap.sh`.
3. Git auth: install `/home/agent/bin/git-credential-doppler` as `credential.helper` (per GLOBAL) — never a static token.
4. Add to `agents/config.sh` (IP, roles, overflow flag); verify it appears in `./agents/server-status.sh` before dispatching.
5. If provisioning a per-host key pair for this box (SSH key retirement, phase 2b started 2026-09-16): add its entry to the `HOST_BY_IP` table in `agents/scripts/ssh-key-for.sh` (kept in BOTH grotap-agents and grotap-platform — see that file's header), and drop `grotap_from<source>_<this-host>` into `~/.ssh/` for both `root` and `agent` on the source box. Until that exists, every script that talks to this host goes on resolving to the shared fleet key automatically — no code change required.
