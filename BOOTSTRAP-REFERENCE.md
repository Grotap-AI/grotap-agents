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
All agent servers use SSH key auth. Use configured aliases (`~/.ssh/config`).
```bash
ssh agent-01        # 5.161.189.143  (User: agent)
ssh agent-02        # 5.161.74.39    (User: root)
ssh agent-03        # 5.161.81.193   (User: root)
ssh agent-04        # 178.156.222.220 (User: root)
ssh agent-05        # 5.161.73.195   (User: root)
ssh agent-06        # 5.78.178.81    (User: root)
ssh agent-07        # 89.167.66.105  (User: root)
ssh agent-08        # 77.42.42.213   (User: agent)
```
If SSH fails: check `~/.ssh/config` — Agent-01/08 use `User agent`, all others use `User root`.

## Known Server Setup Requirements
1. **API key in BOTH files**: `/home/agent/.env` AND `/home/agent/.profile` must contain `export ANTHROPIC_API_KEY=...`
2. **Git safe.directory**: `git config --global --add safe.directory /home/agent/grotap-platform`
3. **Task files not in git**: `agents/tasks/pending/` and `agents/tasks/active/` are local-only
4. **SSH from coordinator (agent-08)**: Needs `~/.ssh/grotap_agents` key + `~/.ssh/config`
5. **Status server**: `node agents/status-server.js` must be running for dashboard
6. **Swap**: `bash agents/ensure-swap.sh` (this repo — canonical copy) — idempotent 4 GiB swap + vm.swappiness; MUST be re-run after any hard reset/rebuild (OOM has wedged two boxes). Also invoked automatically by grotap-platform `agents/setup-server.sh`.

## Server SSH Access Matrix
| Server | `agent` user SSH | `root` user SSH | Notes |
|--------|:-:|:-:|---|
| agent-01 | OK | OK | Primary executor |
| agent-02 | root only | OK | Overflow |
| agent-03 | root only | OK | Overflow |
| agent-04 | root only | OK | Primary executor |
| agent-05 | root only | OK | Overflow |
| agent-06 | root only | OK | Deploy only |
| agent-07 | root only | OK | Primary executor |
| agent-08 | OK | OK | Dispatch coordinator |
