# BOOTSTRAP-REFERENCE.md — Extended reference (NOT loaded into agent prompts)
# This material was extracted from BOOTSTRAP.md to reduce token cost.
# Consult this only when troubleshooting SSH, dispatch, or server setup issues.

## Dispatch Policy — ONCE DAILY at High Noon (12:00 UTC) — changed 2026-06-28
**Retired the old "24/7 continuous" policy.** Per the platform owner (2026-06-28), pipeline work +
agent assignment run **once a day at 12:00 UTC**, NOT continuously. Do NOT restart
`continuous-dispatch.sh` or always-on dispatch systemd services.
- The daily run is scheduled: agent-06 root cron `auto_dispatch_dependents.py` at `0 12 * * *`,
  and the backend `pipeline_automation` loop anchored to 12:00 UTC daily (interval_hours=24).
- During a noon run (or a human-requested one-off), dispatch order is:
  1. `bash agents/server-status.sh` to check idle slots
  2. Dispatch to idle slots, `pending/` first then `active/` backlog (lowest ID first)
  3. Verify each dispatch: tmux session started on target server
  4. If a server errors (missing API key, stale worktree): fix and re-dispatch
- Do NOT keep looping after the batch — the next run is tomorrow at noon.

## SSH Connection Details
All agent servers use SSH key auth. Use the canonical aliases in `agents/SERVERS.md`
(`~/.ssh/config`). `agent-NN` is not the name. Rename map:
`docs/GROTAP-SERVER-RENAME-PLAN.md`.
```bash
ssh agent-01-claude        # 5.161.74.39     (User: root)  SSH alias agent-01
ssh agent-02-claude        # 5.161.81.193    (User: root)  SSH alias agent-02
ssh agent-03-claude        # 178.156.222.220 (User: root)  SSH alias agent-03
ssh agent-04-claude        # 5.161.73.195    (User: root)  SSH alias agent-04; RUNNING
ssh agent-05-claude        # 5.78.178.81     (User: root)  SSH alias agent-05; OFF Hillsboro
ssh agent-06-claude        # 5.161.53.103    (User: root)  SSH alias agent-06; hostname agent-06-claude; live ops
ssh agent-10-codex         # 87.99.148.22    (User: root)  was agent-20
ssh monitor-01-deepseek    # 178.156.219.232 (User: root)  was agent-40
ssh prompt-01-claude       # 178.156.209.112 (User: root)  jumpbox; was claudecode-01 / claude-code-01; DNS claudecode.grotap.com
ssh prompt-01-astra        # 5.161.243.18    (User: root)  id 167204705; was released agent-21 IP
ssh agent-team-01-astra    # 5.161.80.75     (User: root)  id 167204706
ssh openreplay-01          # 5.161.189.143   (User: root)  was grotap-cobrowse-01
ssh openreplay-ai-support  # 178.156.199.83  (User: root)  was grotap-runner-01; do not retire
```
Do not create `agent-11-codex`. Retired boxes `agent-07` and `agent-08` are not fleet hosts. Deleted `agent-01` at `5.161.189.143` is `openreplay-01`, not `agent-01-claude`.

## Known Server Setup Requirements
1. **API key in BOTH files**: `/home/agent/.env` AND `/home/agent/.profile` must contain `export ANTHROPIC_API_KEY=...`
2. **Git safe.directory**: `git config --global --add safe.directory /home/agent/grotap-platform`
3. **Task files not in git**: `agents/tasks/pending/` and `agents/tasks/active/` are local-only
4. **SSH from the ops box** (`agent-06-claude`, Ashburn `5.161.53.103`; `agent-05-claude` Hillsboro is OFF; agent-08 is retired): Needs `~/.ssh/grotap_agents` key + `~/.ssh/config`. Prefer Cloud-name `Host` aliases.
5. **Status server**: `node agents/status-server.js` must be running for dashboard
6. **Swap**: `bash agents/ensure-swap.sh` (this repo — canonical copy) — idempotent 4 GiB swap + vm.swappiness; MUST be re-run after any hard reset/rebuild (OOM has wedged two boxes). Also invoked automatically by grotap-platform `agents/setup-server.sh`.

## Server SSH Access Matrix
| Server | `agent` user SSH | `root` user SSH | Notes |
|--------|:-:|:-:|---|
| agent-01-claude | root only | OK | Intake / triage. SSH alias `agent-01` |
| agent-02-claude | root only | OK | Planner. SSH alias `agent-02` |
| agent-03-claude | root only | OK | Execute. SSH alias `agent-03` |
| agent-04-claude | root only | OK | Pipeline detail. Running. SSH alias `agent-04` |
| agent-05-claude | root only | OK | Hillsboro. OFF. SSH alias `agent-05`. Not the ops host |
| agent-06-claude | root only | OK | Ashburn live ops. Hostname `agent-06-claude`. SSH alias `agent-06` |
| agent-10-codex | root only | OK | Team Builder |
| monitor-01-deepseek | root only | OK | Team Monitor |
| prompt-01-claude | root only | OK | Jump seat at `178.156.209.112`. Was `claudecode-01` / `claude-code-01` |
| prompt-01-astra | root only | OK | `5.161.243.18`, id 167204705 |
| agent-team-01-astra | root only | OK | `5.161.80.75`, id 167204706 |
