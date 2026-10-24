# agents/SERVERS.md — Fleet roster (single source of truth; loaded at bootstrap after GLOBAL.md)

## Fleet rename 2026-10-02 PT (owner order) — transitional state

Hetzner Cloud names changed on 2026-10-02 PT. IPs, server ids, protection, firewalls and labels did not change.
Until the code accepts the new names, **the old names remain the live dispatch / pool / alias keys**
(`agents/config.sh`, `agents/fleet-aliases.json`, `team_pools.json`, `FLEET_HOSTS`, key files `grotap_from06_<old>`).

| IP | Hetzner id | New Hetzner name | Old name (still the pool key; kept as SSH alias and /etc/hosts alias) | OS hostname (SSH check 2026-10-11) |
|---|---|---|---|---|
| `178.156.199.83` | 149246895 | `openreplay-ai-support-01` | `openreplay-ai-support` (`runner-01`) | `openreplay-ai-support-01` (renamed). `RUNNER_ID=openreplay-ai-support` unchanged. |
| `5.161.80.75` | 167204706 | `team-astra-01` | `agent-team-01-astra` | `team-astra-01` (renamed) |
| `178.156.215.173` | 167604967 | `team-codex-grok-monitor-01` | `agent-22-shared` | `team-codex-grok-monitor-01` (renamed) |
| `5.161.119.92` | 167539331 | `team-claude-01` | `agent-21-shared` | `team-claude-01` (renamed) |
| `5.161.53.103` | 166626264 | `ops-01` | `agent-06-claude` (`agent-06`, `agent-06-ash`) | `ops-01` (renamed) |

Unchanged: `maps-01`, `forge-01`, `mdm-01`, `scan-01`. (`openreplay-01` was deleted 2026-10-03; `openreplay-02` replaced it.)

OS hostnames now equal the Hetzner names on every live box (SSH check 2026-10-11). The old names are still
the pool / dispatch keys in code, so they stay as aliases until `agents/fleet-aliases.json` expires
(`remove_after` 2026-12-31). Where the old names still matter: the per-host key files keep their old
stems (`grotap_from06_<old>`); `agents/status-server.js` and `agents/scripts/ssh-key-for.sh` pick those
keys when the local hostname is `agent-06` or `ops-01` (both accepted); `ggshield-lib.sh` accepts both
`team-codex-grok-monitor-01` and `agent-22-shared` as the canary host; and `agents/scripts/report-progress.sh` posts
`$(hostname)` as `agent_server`, which the backend resolves through `fleet-aliases.json` and which
`team_dispatch_target.py` / the orchestrator slot map match against the pool host name. `fleet-aliases.json`
folds each new hostname onto its old pool name; a hostname missing from that map would drop running work
out of per-host load counts (over-admission).
Each box has `/etc/cloud/cloud.cfg.d/99-grotap-rename.cfg` (`preserve_hostname: true`,
`manage_etc_hosts: false`) (written before the hostname change; still present on the team boxes).
New SSH aliases: workstation `~/.ssh/config` and ops-01 `/root/.ssh/config` (`ops-01`, `team-claude-01`,
`team-codex-grok-monitor-01`, `team-astra-01`, `openreplay-ai-support-01`), with key symlinks
`/root/.ssh/grotap_from06_<new> -> grotap_from06_<old>`. No Cloudflare DNS record used any old name, so none was added.

Bootstrap names are the locked Cloud names, not `agent-NN`. Map, status, and the Astra GO:
`docs/GROTAP-SERVER-RENAME-PLAN.md`, `docs/GROTAP-SERVER-RENAME-STATUS.md`,
`docs/GROTAP-PROMPT-ASTRA-PROVISION.md`.

Cloud renames already applied (2026-09-21): `agent-01-claude` … `agent-06-claude`,
`agent-10-codex`, `monitor-01-deepseek`, `openreplay-01`, `openreplay-ai-support`.
`prompt-01-claude` (was `claudecode-01`, then `claude-code-01`) was **deleted 2026-09-26**. Hetzner has no server by that name.
Post-cutover, the seat hosts are **`team-claude-01`** (formerly `agent-21-shared`) `5.161.119.92` (Team Claude seat) and **`team-codex-grok-monitor-01`** (formerly `agent-22-shared`) `178.156.215.173` (Team Codex, Grok, and Monitor seats). `ops-01` (formerly `agent-06-claude`, `5.161.53.103`) stays the ops host. `prompt-01-astra` (Hetzner id 167204705) is deleted (absent from every Hetzner project, API check 2026-10-11). `team-astra-01` (formerly `agent-team-01-astra`, `5.161.80.75`, id 167204706) is running and is still the `team5` pool in `agents/config.sh`, but idle: last dispatch 2026-10-03 04:36Z, no tmux, no worktrees, load 0.0 (check 2026-10-11). No retirement is scheduled; that is an owner decision. Do not retire `openreplay-ai-support-01`.

**Hetzner Cloud name is the primary column.** Short names `agent-01` … `agent-06` are SSH/dispatch aliases only. Each one is the **same IP** as `agent-01-claude` … `agent-06-claude`. `agent-01-claude` … `agent-04-claude` are deleted. `5.161.74.39` (former `agent-01-claude`) was recycled by Hetzner to **`openreplay-02`** (id 168488339) — never point `agent-01` or `agent-01-claude` at it.

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

## Fleet map after the shared-host cutover

`prompt-01-claude` (from `claudecode-01` / `claude-code-01`) was **deleted 2026-09-26**. Hetzner has no server by that name. `agent-05-claude` (Hillsboro) was **deleted the same day**; do not put its former address back on a monitor or roster list. Short aliases `agent-01` … `agent-04` and `agent-06` are the same IPv4 as `agent-01-claude` … `agent-04-claude` and `agent-06-claude`. `team-astra-01` (formerly `agent-team-01-astra`) is `5.161.80.75`.

`team-claude-01` and `team-codex-grok-monitor-01` (formerly `agent-21-shared` / `agent-22-shared`) are **active**. `ops-01` (formerly `agent-06-claude`) is the ops host and stays running. The pre-cutover executor boxes below were **deleted** between 2026-09-26 and 2026-10-03: none of them is in any Hetzner project (API check 2026-10-11, all four tokens), so their addresses are released and not listed. Only `team-astra-01` still runs.

| Cloud name | IPv4 | Status |
|---|---|---|
| ai-workstation-grotap-01 | 5.161.82.78 | active — owner AI workstation (Claude Code, Gemini CLI, Grok CLI under user `grotap`, `ai-session` tmux). ccx43 Ashburn, id 172152945, created 2026-10-24. Tailnet node `ai-workstation-grotap-01.tail0642b7.ts.net` (100.93.92.55, joined 2026-10-24, key expiry disabled); browser terminals via `tailscale serve` + ttyd at `http://ai-workstation-grotap-01.tail0642b7.ts.net/{claude,gemini,grok,shell}` (tailnet only; HTTPS once the tailnet enables certs). Aider 0.86.2 (2026-10-24, platform PR #438): web GUI at `http://ai-workstation-grotap-01.tail0642b7.ts.net:8080/` (Streamlit, systemd `aider-gui`, 127.0.0.1:7690) and terminal at `/aider` (`ttyd-ai@aider`, 127.0.0.1:7685, same tmux session as `ai-session aider`); models Claude/Gemini/Grok via Doppler `grotap/claudecode` references (ANTHROPIC_API_KEY, GEMINI_API_KEY, XAI_API_KEY); config committed in platform root `.aider.conf.yml`, `.aiderignore`, `.aider.model.settings.yml`, `scripts/aider/*.aider`. Not in any dispatch pool; recycled fleet IP (old known_hosts entry removed) |
| team-claude-01 (formerly `agent-21-shared`) | 5.161.119.92 | active — Team Claude seat. ccx33 Ashburn, id 167539331, created 2026-09-26 |
| team-codex-grok-monitor-01 (formerly `agent-22-shared`) | 178.156.215.173 | active — Team Codex, Grok, and Monitor seats. ccx33 Ashburn, id 167604967, created 2026-09-27 |
| ops-01 (formerly `agent-06-claude`) | 5.161.53.103 | running — ops host. cpx31 Ashburn, id 166626264, created 2026-09-20 |
| agent-01-claude | — (released) | **deleted** — absent from every Hetzner project (API check 2026-10-11) |
| agent-02-claude | — (released) | **deleted** — absent from every Hetzner project (API check 2026-10-11) |
| agent-03-claude | — (released) | **deleted** — absent from every Hetzner project (API check 2026-10-11) |
| agent-04-claude | — (released) | **deleted** — absent from every Hetzner project (API check 2026-10-11) |
| agent-10-codex | — (released) | **deleted** — absent from every Hetzner project (API check 2026-10-11) |
| agent-11-codex | — | **deleted** — absent from every Hetzner project (API check 2026-10-11) |
| agent-13-monitor | — | **deleted** — absent from every Hetzner project (API check 2026-10-11) |
| monitor-01-deepseek | — (released) | **deleted** — absent from every Hetzner project (API check 2026-10-11) |
| agent-01-grok | — (released) | **deleted** — absent from every Hetzner project (API check 2026-10-11) |
| agent-02-grok | — (released) | **deleted** — absent from every Hetzner project (API check 2026-10-11) |
| prompt-01-astra | — (released) | **deleted** — absent from every Hetzner project (API check 2026-10-11) |
| team-astra-01 (formerly `agent-team-01-astra`) | 5.161.80.75 | running, idle since 2026-10-03 — `team5` pool. cpx31 Ashburn, id 167204706, created 2026-09-24. Workstation per-host root key `~/.ssh/grotap_agent-team-01-astra` rotated 2026-10-22 to SHA256:2k4D3eAQrf3ueTP6hfFauyHhJZI2M/YTH994EQfdzHE (comment `grotap-astra-host-20261022`); the old key was Railway-held as orchestrator `SSH_PRIVATE_KEY_AGENT_TEAM_01_ASTRA_B64` (var deleted). The seat key `grotap-astra-20261022` is for `astra@team-claude-01`, not this host. |

Footnotes: Linux hostname on `ops-01` is `ops-01` (renamed from `agent-06-claude`). `agent-10-codex` Linux hostname may still be `agent-20`. `monitor-01-deepseek` Linux hostname may still be `agent-40`. `5.161.74.39` is `openreplay-02` (not `agent-01-claude`). Live ops (`grotap-status`, `cloudflared`, `review-gate.timer`, deploy-ops crons) run on `ops-01`. `agent-11-codex` and `agent-13-monitor` have no IPv4 in this file (`ssh-key-for.sh` maps the names only).

**2026-10-22 — SSH keys rotated after the Railway env-var breach (2026-10-21).** Every SSH key that Railway held a copy of was replaced, same name, new material (platform repo `docs/incidents/2026-10-21-railway-fleet-ssh-rotation.md` has per-host fingerprints): shared fleet key `grotap-shared-20261022` (Doppler prd `SSH_PRIVATE_KEY`/`SSH_PRIVATE_KEY_B64`/`SSH_AGENT_PUBLIC_KEY`, workstation `~/.ssh/grotap_agents`), `grotap-agent-06-20261022` (`agent@ops-01`), and the seat keys `grotap-{claude,astra,codex,grok,monitor}-20261022` (ops-01 `/home/agent/.ssh/grotap_from06_<seat>`, Doppler prd `SSH_PRIVATE_KEY_{CLAUDE,ASTRA,CODEX,GROK,MONITOR}_B64`). The Hetzner `grotap-agents` key object was replaced in all four projects (new ids 131625643, 131625645, 131625648, 131625650). The shared key is authorized for root on team-claude-01, team-codex-grok-monitor-01, team-astra-01, ops-01, forge-01, scan-01 and mdm-01, and is NOT on maps-01 (per-host keys only there). Railway orchestrator copies of the SSH key vars were re-synced from Doppler on 2026-10-22 (afternoon, platform repo `docs/incidents/2026-10-21-railway-env-breach.md` sections 8-9). Afternoon correction: the workstation per-host root key for team-astra-01 (`~/.ssh/grotap_agent-team-01-astra`, old fingerprint `qwF1/…VszY`) WAS also Railway-held, as orchestrator `SSH_PRIVATE_KEY_AGENT_TEAM_01_ASTRA_B64`; it was rotated to SHA256:2k4D3eAQrf3ueTP6hfFauyHhJZI2M/YTH994EQfdzHE (comment `grotap-astra-host-20261022`), the old public key removed from team-astra-01 root `authorized_keys`, the old private key kept as `.revoked-20261022`, and the orchestrator vars `SSH_PRIVATE_KEY_AGENT_TEAM_01_ASTRA_B64`, `SSH_PRIVATE_KEY_AGENT_01_GROK_B64` and `SSH_PRIVATE_KEY_AGENT_02_GROK_B64` deleted (their hosts are deleted or, for astra, the key is workstation-only now). `NAMED_HOST_KEY_VARS` in `orchestrator/src/config.ts` still names those three vars, so the orchestrator cannot dial team-astra-01 until that mapping is fixed; dispatch is frozen, fix when it resumes. Two open owner items: an undocumented root key `agent-infrastructure@grokbot-box` is authorized on ops-01, team-astra-01, maps-01, openreplay-ai-support-01, mdm-01 and scan-01 (left in place; hold `SEC-GROKBOT-KEY-20261022` asks keep / remove / treat as compromise), and `PasswordAuthentication yes` is still on 7 hosts (team-claude-01, team-codex-grok-monitor-01, team-astra-01, maps-01, openreplay-02, openreplay-ai-support-01, mdm-01).


## Active dispatch pool

SSH alias is not a Hetzner name. After cutover, the Team Claude seat is on `team-claude-01` (formerly `agent-21-shared`, active); Team Astra (`team5`) moved to `team-astra-01` on 2026-09-27. Team Codex, Grok, and Monitor seats are on `team-codex-grok-monitor-01` (formerly `agent-22-shared`, active). `agent-01-claude` through `agent-04-claude` keep their old role rows for history only; all four are deleted. `ops-01` (formerly `agent-06-claude`) remains the ops host.

| Cloud name | IP | Linux hostname | SSH alias (not a Cloud name) | Hardware / DC | Roles | Execute slots |
|---|---|---|---|---|---|---|
| ai-workstation-grotap-01 | 5.161.82.78 | ai-workstation-grotap-01 | — | ccx43, Ashburn. **active** | Owner AI workstation: `ssh ai-ashburn` / `ai claude|gemini|grok|aider|shell` (desktop alias). Scripts: platform `scripts/claudecode/hetzner-bootstrap.sh`, `hetzner-create-workstation.sh`, `hetzner-web-tailscale.sh` (Tailscale + ttyd web UI, 2026-10-24: `ttyd-ai@{menu,claude,gemini,grok,shell}` on 127.0.0.1:7680-7684, `tailscale serve` paths, stock `ttyd.service` masked), `hetzner-aider-workspace.sh` (Aider venv `~/.venvs/aider`, `aider-gui.service`, `ttyd-ai@aider`, serve `/aider` + `:8080`; 2026-10-24). Dedicated vCPU limit 32->40 (2026-10-24) | — |
| team-claude-01 | 5.161.119.92 | team-claude-01 | `agent-21-shared` (pool key) | ccx33, Ashburn. **active** | Team Claude seat (`astra` user still exists; `team5` pool is on `team-astra-01`) | — |
| team-codex-grok-monitor-01 | 178.156.215.173 | team-codex-grok-monitor-01 | `agent-22-shared` (pool key) | ccx33, Ashburn. **active** | Team Codex, Grok, and Monitor seats | — |
| ops-01 | 5.161.53.103 | ops-01 | `agent-06`, `agent-06-claude` | cpx31, Ashburn. **Running** | Live ops host (was `agent-06-ash`). `grotap-status`, `cloudflared`, `review-gate.timer` active | 2 |
| agent-01-claude | — (released) | agent-01-claude | `agent-01` | cpx21, Ashburn. **deleted** — absent from every Hetzner project (API check 2026-10-11) | Intake, Triage, Security Reviewer | 3 |
| agent-02-claude | — (released) | agent-02-claude | `agent-02` | cpx21, Ashburn. **deleted** — absent from every Hetzner project (API check 2026-10-11) | Planner, Fix/Logic/Policy/Perf Reviewer | 3 |
| agent-03-claude | — (released) | agent-03-claude | `agent-03` | cpx21, Ashburn. **deleted** — absent from every Hetzner project (API check 2026-10-11). Console was **"03-Agent"** (ID 122714167). OOM-froze 7/5 (hard reset); keep swap enabled | Execute, Change Reviewer, Rule Enforcer, Build Validator | 3 |
| agent-04-claude | — (released) | agent-04-claude | `agent-04` | cpx21, Ashburn. **deleted** — absent from every Hetzner project (API check 2026-10-11) | Pipeline Detail, Audit Filters, Mobile Approvals, Marketing (consolidated from agent-11 4/29: grotap.com site, Meta/Instagram/Facebook, YouTube, TikTok APIs) | 3 |

Routing between roles follows the pipeline graph in `registry.md`; triggers/load-order per role live in each ROLE.md.
**forgejo-runner v13.1.0** (systemd unit `forgejo-runner.service`, installed 2026-09-15) was on `agent-01-claude` through `agent-04-claude` (all deleted; their runners went with them) and is on `ops-01`. `agent-05-claude` was deleted 2026-09-26, so that runner is gone with the box. HOST execution mode: CI jobs run natively as the unprivileged `forge-runner` user in a systemd jail (`ProtectSystem=strict`, `ProtectHome=tmpfs`, `NoNewPrivileges`, empty `CapabilityBoundingSet`), no Docker. Labels `ubuntu-latest:host` and `ubuntu-24.04:host`, capacity 2 per box, registered org-wide to `Grotap-AI` on forge-01. It is independent of the agent tmux sessions and of `dispatch.sh`.

Dispatch assignment is owned by the backend 3-min loop + LangGraph orchestrator on Railway (which SSHes to the fleet). Live ops is on `ops-01` (`5.161.53.103`): `grotap-status`, `cloudflared`, and `review-gate.timer` are active there, with the deploy-ops crons below.

**SSH key retirement (started 2026-09-16, in progress).** The shared fleet key `grotap_agents` is being
replaced by per-host keys, host by host — it is NOT removed yet and every fleet script still falls back
to it. Phase 1 (2026-09-16 04:01Z): the Hillsboro box (`agent-05-claude`, deleted 2026-09-26) got per-target keys for both `root` and `agent`
(`~/.ssh/grotap_from06_agent-0{1,2,3,4,5}`). Short alias `agent-01` was `agent-01-claude` (deleted); its former address now belongs to `openreplay-02`.
`ssh-key-for.sh` resolves `agent-0N` to `agent-0N-claude` on that same IP.
Phase 2b (same day): every fleet
script that used to hardcode the shared key now resolves it per target through
`agents/scripts/ssh-key-for.sh` (kept byte-identical in both grotap-agents and grotap-platform — see
that file's header), which falls back to the shared key for any target with no per-host pair yet —
maps-01, forge-01 and every other special host below included. Do not remove `grotap_agents`
from any box or from `~/.ssh/config` until a later phase says so explicitly.

## ops-01 detail (formerly `agent-06-claude`; Ashburn ops host — `5.161.53.103`; Linux hostname `ops-01`)
`agent-05-claude` was deleted 2026-09-26 and is not the ops host.
- Live units: `grotap-status`, `cloudflared`, `review-gate.timer`.
- root cron: `health-monitor.sh` 5m · `deploy-verify.sh` 15m · `dns-watchdog.sh` + `env-validator.sh` daily · Wasabi DR backup (daily Neon dump 00:00 + weekly full Sun 02:00, object-lock-safe dated heartbeats) · `reconcile_dispatch.py` **10m** (flock; runs the git-pulled repo copy `grotap-platform/scripts/` with `--max 6 --days 14 --stale-min 10` — consolidated 2026-07-14, the old frozen `/home/agent/` copy + duplicate agent-cron entry are RETIRED) · fleet CLI update daily · release notes 13:00 · systemd `grotap-status` (status server).
- agent cron: `pipeline_failure_monitor.py` 10m · `deploy_freshness_watchdog.py` 5m · **review gate every 15 min** (`review-gate-cron.sh`; empty queue exits <5s). `review-gate.timer` is active on this host.
- Deploy Ops roles (trigger → role): merge-to-master → **Deploy Verifier**; verifier FAIL → **Deploy Executor**; before deploy-execute → **Env Validator**; every 5 min → **Health Monitor**; daily / after infra change → **DNS Watchdog**; verifier PASS → **Post-Deploy QA**. Escalate to human when deploy infra itself is broken; hotfix regressions route to the Team Claude seat on `team-claude-01` (`agent-03-claude` is deleted).

## Team Builder (was Team 2) — open-model executors (Hetzner project **OpenAgents.grotapai**, token `HETZNER_FARM_API_TOKEN`)
Provisioned 2026-07-07 for the Team 2 program (cases AA8CFD/F404F8/959C5E). Aider + OpenRouter runtime —
NO claude CLI on these boxes by design. ⚠ NOT in the Team 1 dispatch pool: do not dispatch until the
`config.sh` team registry (F404F8 children) merges and `case_data.team=team2` routing is live.

Team Codex seats are **active** on `team-codex-grok-monitor-01` (formerly `agent-22-shared`, `178.156.215.173`). The boxes in this table are deleted.

| Server | IP | Hardware / DC | Purpose | Execute slots |
|---|---|---|---|---|
| agent-10-codex | — (released) | cpx21, Ashburn (id 148646754). Cloud name `agent-10-codex`. **deleted** — absent from every Hetzner project (API check 2026-10-11) | Team Builder — GPT Codex via OpenRouter (was Team 2 open-model executor) | 3 |
| agent-11-codex | — | **deleted** — absent from every Hetzner project (API check 2026-10-11). No IPv4 in this file | Second Codex builder. Not a reserved name | — |

Baseline: Ubuntu 24.04, agent user, node 22, doppler CLI + `git-credential-doppler`, aider (pipx),
4 GiB swap, `~/grotap-agents` + `~/grotap-platform` clones, `~/worktrees`. Scale Team Builder by adding
boxes here + the team2 pool in `config.sh` — box CPU is only builds/git, inference is remote (OpenRouter).

## Team 3 — Grok 4.5 executors (Hetzner project **OpenAgents.grotapai**, token `HETZNER_FARM_API_TOKEN`)
Provisioned 2026-07-12 for the Grok 4.5 hedge team (cases D15EF4/A5CE1C/A1CD20/6C7435). Aider +
OpenRouter (`x-ai/grok-4.5`) runtime — NO claude CLI by design. **FSN1 on purpose**: attached to Cloud
Network `team2-llm-lan` (12438415) — the Ashburn team2 boxes cannot attach (single-zone rule). ⚠ NOT dispatchable until the `config.sh` team3 registry
(case A5CE1C) merges and pilot cases are tagged `case_data.team=team3`.

Team Grok seats are **active** on `team-codex-grok-monitor-01` (formerly `agent-22-shared`, `178.156.215.173`). `agent-01-grok` and `agent-02-grok` are **deleted** — absent from every Hetzner project (API check 2026-10-11).

> **Deleted 2026-09-20:** `agent-30` (150155427) was deleted from Hetzner
> and its IP released, for the same reason its sibling `agent-31` went on
> 2026-09-16. Verified 2026-09-20 against every Hetzner token in Doppler
> (`HETZNER_API_TOKEN`, `_CLAUDECODE_`, `_COBROWSE_`, `_FARM_`): no server in any project holds
> that address, and `server_connections` has no agent-30 row. Hetzner recycles released IPs, so
> the address now belongs to a stranger — never SSH it, never map it to a fleet host name, never
> put it in a firewall allowlist. Re-provision with `agents/provision-team3.py` before re-adding.

Baseline identical to Team 2 (agent user, node 22, doppler + `git-credential-doppler`, aider via
pipx, 4 GiB swap, both repo clones, `~/worktrees`). Note: cpx21 is not offered in FSN1 — cpx22
(2c/4GB, €22.99/mo) is the closest.

## Team Monitor (was Team 4) — DeepSeek via OpenRouter (Hetzner project **OpenAgents.grotapai**, token `HETZNER_FARM_API_TOKEN`)
Provisioned 2026-07-13 for the GPT-5.6 hedge team (cases B8EF68/FC0208/BA9BC6/8B9BFC —
`docs/GPT56_SOL_TEAM4_PLAN.md` in grotap-platform). Aider + OpenRouter
(`openai/gpt-5.6-luna` rung 1, `openai/gpt-5.6-sol` strong) runtime — NO claude CLI by design.
Ashburn, public-only: inference is OpenRouter-hosted (and ash cannot join the eu-central
`team2-llm-lan` anyway). ⚠ NOT dispatchable until the `config.sh` team4
registry (case FC0208) merges and pilot cases are tagged `case_data.team=team4`.
Team 5 note: the Codex CLI runner experiment (case 8B9BFC) SHARES this box by design
(experiment phase; 3 slots/box, inference remote) — revisit if both teams go live.

Team Monitor seats are **active** on `team-codex-grok-monitor-01` (formerly `agent-22-shared`, `178.156.215.173`). The boxes below are deleted.

| Server | IP | Hardware / DC | Purpose | Execute slots |
|---|---|---|---|---|
| monitor-01-deepseek | — (released) | cpx21, Ashburn (id 150671577). Cloud name `monitor-01-deepseek`. **deleted** — absent from every Hetzner project (API check 2026-10-11) | Team Monitor — DeepSeek via OpenRouter (provisioned as the Team 4 GPT-5.6 executor) | 3 |
| agent-13-monitor | — | **deleted** — absent from every Hetzner project (API check 2026-10-11). No IPv4 in this file | Team Monitor box | — |

Baseline identical to Team 2/3 (agent user, node 22, doppler + `git-credential-doppler`, aider
via pipx, 4 GiB swap, docker + `grotap-sandbox:latest`, both repo clones, `~/worktrees`).

> **Retired 2026-09-16:** `agent-21` (148646760), `agent-31` (150155432) and `agent-41`
> (150671582) were deleted from Hetzner. Each had ZERO rows in `pipeline_dispatch_log` for its
> entire life; verified empty first (no tmux, no worktrees, clones clean, load 0.00). Their
> siblings agent-10-codex (was agent-20) and monitor-01-deepseek (was agent-40) are deleted too. Seats for those teams are active on `team-codex-grok-monitor-01` (agent-30 followed the deleted boxes on 2026-09-20).
> `TEAM_POOL` in `agents/config.sh` is now single-host for team2/4/5 (grotap-platform
> `5226d7fc9`) and EMPTY for team3 since 2026-09-20. Rebuild specs: cpx21 (cpx22 for
> team3/FSN1), ubuntu-24.04, labels `role=<open-model|grok|gpt>-executor`, `team=team<N>`;
> provision scripts `agents/provision-team{2,3,4}.py`.

## Special hosts — NOT executors, never dispatch, never add to `config.sh` pools
| Host | IP | Purpose |
|---|---|---|
| openreplay-02 | 5.161.74.39 | **OpenReplay session-replay server** — `supportagents.grotap.com` (A record, DNS-only, verified 2026-10-11). ccx23 Ashburn (id 168488339), Hetzner project `Cobrowse.Grotap.com` (`HETZNER_COBROWSE_API_TOKEN`), created 2026-10-03; took over `supportagents.grotap.com` from `openreplay-01` on 2026-10-02. Linux hostname `openreplay-02`. ⚠ The address is recycled from deleted `agent-01-claude` — it is not an agent host; stale host-key warnings: `ssh-keygen -R 5.161.74.39`. `openreplay-01` (former names `grotap-cobrowse-01`, supportagents) was **deleted 2026-10-03**; its address is released and not listed. |
| scan-01 | 5.161.75.121 | **ClamAV malware-scanning service** — `scan.grotap.com`, self-hosted virus scanning for all uploaded files (owner policy 2026-07-04: file bytes NEVER go to a third-party vendor; VirusTotal stays dormant). cpx21 **Ashburn** (id 168175702), Hetzner main project (`HETZNER_API_TOKEN`), created 2026-10-01 — rebuilt from the original fsn1 box (provisioned 2026-08-10, now gone; its address is released and not listed). Linux hostname `scan-01`; reachable over SSH from the ops host (`grotap_from06_scan-01`), while a direct connection from the owner workstation times out — replaces the stack lost when grotap-cobrowse-01 was wiped 2026-07-07. Docker stack `services/clamav-scan/` (Caddy → scanner-api → clamd; 3310 internal only). ⚠ **Deliberately holds NO Doppler token** — it parses hostile files, so `CLAMAV_SCAN_SECRET` is delivered to a root-owned `.env.runtime`, never a prd-wide token. DNS: `scan.grotap.com` A → `5.161.75.121`, DNS-only (verified 2026-10-11; HTTPS answers). Cases: CLAM01 (stack) / CLAM02 (prod env wiring). |
| openreplay-ai-support-01 | 178.156.199.83 | **OpenReplay AI Support runner — KEEP. Do not retire.** Formerly `openreplay-ai-support` (still the pool key and `RUNNER_ID`), before that `grotap-runner-01`. Linux hostname `openreplay-ai-support-01`. Live unit `support-runner`, `RUNNER_ID=openreplay-ai-support` (claim API healthy: runner-status 200, claim 204 on an empty queue; rename STATUS 2026-09-21). cpx21 Ashburn (id 149246895), Hetzner project `Cobrowse.Grotap.com` (`HETZNER_COBROWSE_API_TOKEN`), firewall `runner-fw` (inbound ssh+icmp only — runner is outbound-only). Provisioned 2026-07-09. The old `cobrowse-runner` unit is not the live identity. |
| mdm-01 | 87.99.140.189 | **Headwind MDM server** — `mdm.grotap.com`, Android tablet fleet management (Device-Owner QR enroll, silent Scan M APK push; remote-control plugin pending owner purchase). cpx21 Ashburn (id 153766531), Docker stack `/opt/hmdm-docker` (hmdm 0.1.8 + postgres:12 on loopback, MQTT `:31000`), UFW 22/80/443/31000, LE renew cron 1st+15th. Secrets `MDM_*` in Doppler. Full doc: `docs/06-infrastructure/mdm-tablets.md`. Provisioned 2026-07-21. |
| maps-01 | 5.161.107.80 | **Map services: Martin tiles + TiTiler NAIP + Caddy** — `maps.grotap.com` (A record, unproxied, TTL 300 — no AAAA, no wildcard), MAP-1 CASE-20260914-76CACC / leaf 81D5CE. cpx31 **Ashburn** (id 165776284), Hetzner main project (`HETZNER_API_TOKEN`), firewall `maps-fw` (id 11619661: inbound TCP 22/80/443 + ICMP), labels `role=maps,owner=platform`. Provisioned 2026-09-14 — **bootstrap pending** (MAP-1's `bootstrap.sh` deploys the stack; base only so far: Ubuntu 24.04, docker.io + compose v2, ufw 22/80/443, gdal-bin, 2 GiB swap, `/data/{basemap,naip,ortho}`, `/opt/maps/.env` root:600 with `MAPS_SHARED_SECRET` + `MAPS_PUBLIC_HOST`). Root SSH = per-host keys only (workstation `~/.ssh/grotap_maps-01`, ops-01 `grotap_from06_maps-01`); the shared fleet key was stripped 2026-10-02 and is NOT authorized here (census 2026-10-22), so `ssh-key-for.sh`'s shared-key fallback does not reach this host. Doppler prd+dev: `MAPS_TILE_BASE_URL`, `MAPS_SHARED_SECRET`, `MAPS_SERVER_IP` (copied to Railway `grotap-backend`). |
| forge-01 | 178.156.246.81 | **Self-hosted git forge (Forgejo 13.0.5) — PROTECTED. Do not delete, downsize, or retire.** `forge.grotap.com` (A record, **proxied**) for HTTPS, `forge-ssh.grotap.com` (A record, **unproxied** — Cloudflare cannot proxy git-over-SSH) on port **2222**. **Restored and running.** cpx21 **Ashburn** (id 167546044; previous id 166078095 is gone), created 2026-09-26 10:49 AM PT from snapshot `436438026`. IPv4 `178.156.246.81` is the same address as before the deletion. Hetzner main project (`HETZNER_API_TOKEN`), firewall `forge-fw` (id 11628446: 22 + ICMP from the five worker IPs and the owner workstation only, 80/443 from Cloudflare ranges only, 2222 from the same fleet+workstation set), labels `role=forge,owner=platform`. Provisioned 2026-09-15. Stack in `/opt/forge`: docker compose (Forgejo + Caddy, Let's Encrypt cert on the origin), sqlite3 DB at `/opt/forge/forgejo/gitea/gitea.db`, 2 GiB swap, sshd drop-in `01-grotap-hardening.conf`. Hardened: `DISABLE_REGISTRATION`, `REQUIRE_SIGNIN_VIEW`, `INSTALL_LOCK`, `OFFLINE_MODE`. ⚠ **GitHub is still the source of truth** — all four repos (grotap-platform, grotap-agents, grotap-landing, grotap-platform-docs) are PULL MIRRORS refreshing every 10 min under the `Grotap-AI` org; no deploy path has moved off GitHub. Doppler prd+dev: `FORGE_URL`, `FORGE_SSH_HOST`, `FORGE_SSH_PORT`, `FORGE_SERVER_IP`, `FORGE_API_TOKEN`, `FORGE_ADMIN_USER`, `FORGE_ADMIN_PASSWORD`, `FORGEJO_WEBHOOK_SECRET`. Root SSH = shared fleet key (rotated to `grotap-shared-20261022` on 2026-10-22; `ssh-key-for.sh` falls back to it) plus the workstation per-host key `~/.ssh/grotap_forge-01`. See **Protected infrastructure** below. |

## Protected infrastructure

**forge-01** (Forgejo at `forge.grotap.com`, Ashburn `cpx21`, IPv4 `178.156.246.81`) is protected infrastructure and is **restored and running**. Protected by owner order 2026-09-26 after accidental deletion. Hetzner server ID `167546044` (previous ID `166078095` is gone), type `cpx21`, created 2026-09-26 10:49 AM PT from snapshot `436438026`. IPv4 `178.156.246.81` is the same address as before the deletion.

It matters because:

- It is the local git mirror of the four GitHub repos (`grotap-platform`, `grotap-agents`, `grotap-landing`, `grotap-platform-docs`), as pull mirrors every 10 minutes.
- CI runners on the agent servers register to it.
- It reduces GitHub API and rate-limit hits and makes fetches faster for multi-team jobs.
- It keeps a nightly encrypted Wasabi backup.
- It holds a copy of the code if GitHub is down.

**Rule:** forge-01 is never on any delete, downsize, or cost-cut list. Hetzner delete protection and rebuild protection stay on. Changes need Aaron's explicit approval.

## Prompt / Astra — not in the Team Claude pool

Not in the Team Claude pool. `team-astra-01` (formerly `agent-team-01-astra`) is the `team5` pool in `config.sh` (moved off `agent-21-shared` 2026-09-27). `prompt-01-astra` is deleted.

| Cloud name | IP | Role |
|---|---|---|
| prompt-01-astra | — (released) | Prompt Option — GPT-6 Astra (`gpt-6-astra`). **deleted** — absent from every Hetzner project (API check 2026-10-11). cpx31 Ashburn, Hetzner id 167204705. Outside the Team Claude pool. |
| team-astra-01 (formerly `agent-team-01-astra`) | 5.161.80.75 | Agent Team — GPT-6 Astra (`gpt-6-astra`), `team5` pool. Linux hostname `team-astra-01`. `HETZNER_CLAUDECODE_API_TOKEN` project, cpx31 Ashburn ($73.49/mo), Hetzner id 167204706, created 2026-09-24. **Running but idle** (check 2026-10-11): last dispatch 2026-10-03 04:36Z, no tmux sessions, no worktrees, no custom systemd units or crontabs besides docker (no containers), load 0.0. Not scheduled for retirement; owner decision pending. Outside the Team Claude pool. Workstation per-host root key `~/.ssh/grotap_agent-team-01-astra` rotated 2026-10-22 to SHA256:2k4D3eAQrf3ueTP6hfFauyHhJZI2M/YTH994EQfdzHE (comment `grotap-astra-host-20261022`); the old key was Railway-held as orchestrator `SSH_PRIVATE_KEY_AGENT_TEAM_01_ASTRA_B64` (var deleted). The seat key `grotap-astra-20261022` is for `astra@team-claude-01`, not this host. |

## Hetzner account map
One active account (**K0281854926**, console.hetzner.cloud). Verified via API 7/4: all cloud servers are visible to the single `HETZNER_API_TOKEN`; `HETZNER_API_TOKEN_2` was DEAD (401) and was retired on 2026-10-03; nothing should read it. Cobrowse runners live in their own project/token (above). Account `K0390490726` CANCELLED 6/30.

## Retired / cancelled — never dispatch, never re-add
- **prompt-01-claude** (Hetzner server ID 149250118, Hetzner project `ClaudeCode`, was `claudecode-01` / `claude-code-01`, DNS `claudecode.grotap.com`). **Deleted 2026-09-26.** Hetzner has no server by that name. Not `prompt-01-astra`.
- **Deleted agent-01** (deleted 6/29; its address went to `openreplay-01`, itself deleted 2026-10-03). · **agent-01-claude … agent-04-claude, agent-10/11-codex, monitor-01-deepseek, agent-13-monitor, agent-01/02-grok, prompt-01-astra, openreplay-01** — deleted 2026-09-26 … 2026-10-03; absent from every Hetzner project (API check 2026-10-11). `agent-01-claude`'s former address is now `openreplay-02`. · **agent-07** (gone with cancelled account; address released, in no Hetzner project as of 2026-10-03) · **agent-08** (deleted; old dispatch box). Live ops is `ops-01`.
- **agent-05-claude** (Hillsboro). **Deleted 2026-09-26.** Hetzner can reassign its former address. Do not put it on a health, monitor, or fleet roster.
- **agent-09/10/11** (Robot EX44s) — cancelled in Hetzner **Robot** 6/29 (separate from cloud console). The Robot API lists **0 servers** (check 2026-10-11), so all three are gone.

## New-server onboarding
1. First contact: `ssh -i <the key you gave Hetzner at create time> root@<IP>`; add a `Host` alias for the **Cloud name** (`ops-01`, `team-claude-01`, `openreplay-02`, …). Deleted hosts (`prompt-01-claude`, `agent-01-claude` … `agent-04-claude`, `openreplay-01`, …) get no alias. Short names `agent-01` … `agent-06` may also exist; each one is the same IP as `agent-01-claude` … `agent-06-claude`, and none of them is a Hetzner name. A brand-new box has no per-host key yet, so this first-contact step uses whichever key was injected at provisioning. Do NOT assume `~/.ssh/grotap_agents` still works — the shared fleet key is being retired and has already been left out of at least one new box's `authorized_keys` (2026-09-20). Register the real keys in step 5 before anything automated talks to the box.
2. `bash agents/ensure-swap.sh` (script lives in THIS repo — canonical copy; persistent 4 GiB swap — idempotent; OOM has wedged two boxes). No checkout on the box yet? Run it from your local clone: `ssh agent-01-claude "bash -s" < agents/ensure-swap.sh`.
3. Git auth: install `/home/agent/bin/git-credential-doppler` as `credential.helper` (per GLOBAL) — never a static token. The Doppler token behind it is a per-host read-only service token (`fleet-<host>-ro-20261003*`); the shared fleet token `FLEET_DOPPLER_TOKEN` (`agent-fleet-git`) was deleted 2026-10-03 and must not be recreated.
4. Add to `agents/config.sh` (IP, roles, overflow flag); verify it appears in `./agents/server-status.sh` before dispatching.
5. **Register the box's SSH key in all four places below before you dispatch anything to it.** This is
   no longer optional housekeeping: see "SSH key registration" immediately below.

## SSH key registration — the four places (mandatory for every new box)

A new fleet host is only reachable once its key is registered in four separate places. There is no
generator that does this for you: every one of these steps is a deliberate manual edit. Miss any of
them and the box does not report an authentication error — it reports as unreachable, which is why
this drift has gone unnoticed for days before.

**1. The orchestrator's Railway variable.** The LangGraph orchestrator on Railway reads each host's
private key, base64-encoded, from an environment variable (`ssh_private_key_for` in
`orchestrator/src/config.ts`, grotap-platform). Which variable depends on the host:
- a host named `agent-NN` or `agent-NN-<role>` derives `SSH_PRIVATE_KEY_AGENT_<NN>_B64` from its two
  digits (`agent-04-claude` → `SSH_PRIVATE_KEY_AGENT_04_B64`) — always two digits, uppercase, `_B64`;
- a host whose name cannot derive a variable, or whose digits belong to another box, is listed in
  `NAMED_HOST_KEY_VARS` with its own variable (e.g. `agent-team-01-astra` →
  `SSH_PRIVATE_KEY_AGENT_TEAM_01_ASTRA_B64`); a mapped host takes only that variable and never the
  shared key. **Stale since 2026-10-22:** `SSH_PRIVATE_KEY_AGENT_TEAM_01_ASTRA_B64`,
  `SSH_PRIVATE_KEY_AGENT_01_GROK_B64` and `SSH_PRIVATE_KEY_AGENT_02_GROK_B64` were deleted from the
  orchestrator after the Railway breach (the astra one held the workstation per-host root key, now
  rotated to `grotap-astra-host-20261022`, SHA256:2k4D3eAQrf3ueTP6hfFauyHhJZI2M/YTH994EQfdzHE, and
  held only on the workstation; the two grok hosts are deleted). The map still names all three, so
  a mapped dial throws `MissingSshKeyError` until the map is updated when dispatch resumes;
- a dedicated seat user on a shared host reads `SSH_PRIVATE_KEY_<USER>_B64` and never the shared key.

A new host that fits none of these has no per-host key path in the orchestrator — add it to
`NAMED_HOST_KEY_VARS` or it will use the shared key or fail.

**2. The IP→host map in `agents/scripts/ssh-key-for.sh`.** The table `_SSH_KEY_FOR_HOST_BY_IP` turns
whatever token a caller holds — an IP, a DNS name, `root@host` — into the canonical fleet host name the
key filename is built from. A host absent from this table is not an error; it falls through to the
shared-key step.

**3. `SSH_KEY_HOST_BY_IP` in `agents/status-server.js`** (grotap-platform). A *second*, independently
maintained copy of the same host table, re-implemented in JavaScript for the status server ("Same rows
as ssh-key-for.sh"). It has already drifted from the shell resolver more than once. Adding a host to one
and not the other is the normal way this breaks.

**4. The orchestrator's PUBLIC key in `/home/agent/.ssh/authorized_keys` on the new box.** The three
places above are the outbound half — which private key we offer. This is the inbound half: without it
Railway cannot open a session at all, no matter how correctly the variable is named. It is the step most
often forgotten because nothing in the repo records it.

### Two copies of ssh-key-for.sh, and which one is current

`agents/scripts/ssh-key-for.sh` exists in **both** grotap-agents and grotap-platform and must be
byte-identical (see the TWIN FILE note in its header). The duplication is deliberate — callers live in
both repos (dispatch.sh, config.sh, update-fleet-cli.sh and reconcile_dispatch.py on the platform side;
health-monitor.sh, sync-all-agents.sh and setup-agent06.sh on the agents side) and neither repo reaches
across a guessed checkout path. Duplication is the design; *silent* duplication is the defect.

**This drifted once and it was expensive.** Until 2026-09-20 the published grotap-agents copy carried
only five host rows while the grotap-platform copy carried fourteen, so seven hosts (forge-01 and
maps-01 among them) resolved to the retired shared key for every consumer that ran out of the
grotap-agents checkout, `health-monitor.sh` above all. Commit `f4ccb58` in grotap-agents reconciled the
two copies. Treat grotap-platform as the current one if they ever disagree again: that is where
per-host-key work lands first — but confirm with `git log` in both repos before copying.

**Verify, do not assume.** Run

```bash
bash agents/scripts/ssh-key-for.twin-check.sh
```

It diffs the two checkouts against **each other** (never a file against itself, and it fails rather
than skips when it cannot find the twin), and it covers `ssh-key-for.sh`, its test, and itself.
Compare published copies — `git show origin/master:agents/scripts/ssh-key-for.sh` in each repo —
rather than working trees, because a local branch can make the two look identical while the published
copies differ.

### The failure mode: a key-registration miss looks like an unreachable host

When a host is missing from the resolver's table, `ssh-key-for.sh` falls through to the shared fleet
key `~/.ssh/grotap_agents`; the connection is attempted with a credential the host may no longer accept,
and it simply fails. The host then surfaces in monitoring as UNREACHABLE — indistinguishable from a box
that is down, a firewall change, or a network fault. **Read an unreachable fleet host as a possible
key-registration miss** and check these four places before you go looking at the box itself.

The fallthrough announces itself: `ssh-key-for.sh` writes a line to **stderr** when it hands back the
shared key for a target it does not recognise:

```
ssh-key-for: WARNING: no per-host key for <target> -- falling back to the RETIRED shared key ...
```

The literal target `agents` is the shared key by name and stays quiet. If the shared key file itself is
missing or unreadable the resolver exits 1 and names the path — callers must not substitute
`grotap_agents` themselves. Running the resolver by hand is the quickest way to tell a key miss from a
dead box:

```bash
bash agents/scripts/ssh-key-for.sh <host-or-IP>   # a WARNING line means place 2 is the one you missed
```

The orchestrator warns too: `config.ts` logs a fallback-to-SHARED warning when a host has no
`SSH_PRIVATE_KEY_AGENT_<NN>_B64`, a separate warning when the variable does not decode to a PEM key, and
throws `MissingSshKeyError` when there is neither a per-host key nor a shared key. Those lines in the
Railway logs are the fastest confirmation that place 1 is the one you missed.

### The shared-key fallback is disappearing

The fallback is not a safety net any more. The shared key `grotap_agents` is being retired — it was
left out of a new Ashburn box's `authorized_keys` outright on 2026-09-20, and named/seat hosts already
refuse it. "Falls back to the shared key" is becoming "falls back to nothing". Any host still relying on
that fallthrough is already broken or about to be, which is what makes all four registration points
mandatory rather than best-effort.

## Shared-host ggshield pre-commit hook

Seats on `team-claude-01` (`claude`, `astra`) and `team-codex-grok-monitor-01` (`codex`, `grok`, `monitor`) can install a GitGuardian `ggshield` pre-commit hook with `agents/scripts/install-ggshield-hook.sh`. The hook is off after install. `--canary` enables it only for `codex` on `team-codex-grok-monitor-01` (formerly `agent-22-shared`; `ggshield-lib.sh` accepts both names). Runbook: `docs/06-infrastructure/ggshield-seat-hook.md`. Do not install it on `forge-01` or `maps-01`.
