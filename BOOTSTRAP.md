# BOOTSTRAP.md — Mandatory Session Init. No exceptions. No quick sessions.

## 6 Steps (do all, in order)
1. `git pull origin master` + `git rev-parse HEAD` → record as SESSION_COMMIT
2. `./.claude-session-init.sh --validate` → STOP if fails, report error
3. `/codex:setup` → verify Codex CLI ready. WARN if unavailable (non-blocking).
4. Load context in order: `GLOBAL.md` → `servers/{server}.md` → `roles/{module}/MODULE.md` → `roles/{module}/{role}/ROLE.md` → `state/handoffs/handoff-{ticketId}-*.md`
5. Check handoff `generated_at_commit` vs SESSION_COMMIT: 1-5 commits = flag STALE; 6+ = stop, request human review; missing field = reject, request regeneration
6. Output: `BOOTSTRAP COMPLETE | Commit: {SESSION_COMMIT} | Role: {role} | Server: {server} | Codex: {ready|unavailable}`

## Server → Context File Map
| IP | Server | File | SSH User |
|---|---|---|---|
| 5.161.189.143 | agent-01 | servers/agent-01.md | agent |
| 5.161.74.39 | agent-02 | servers/agent-02.md | root |
| 5.161.81.193 | agent-03 | servers/agent-03.md | root |
| 178.156.222.220 | agent-04 | servers/agent-04.md | root |
| 5.161.73.195 | agent-05 | servers/agent-05.md | root |
| 5.78.178.81 | agent-06 | servers/agent-06.md | root |
| 89.167.66.105 | agent-07 | servers/agent-07.md | root |
| 77.42.42.213 | agent-08 | servers/agent-08.md | agent |
| 46.62.184.50 | agent-09 | servers/agent-09.md | root |
| 46.62.184.52 | agent-10 | servers/agent-10.md | root |

Overflow executor: load `roles/execution/MODULE.md` + `roles/execution/execute/ROLE.md`.

## Server Setup Checklist (new server or after reset)
- API key in **both**: `/home/agent/.env` AND `/home/agent/.profile` (`export ANTHROPIC_API_KEY=...`)
- Git safe.directory if root/agent mismatch: `git config --global --add safe.directory /home/agent/grotap-platform`
- SCP task files (not in git): `scp -r agents/tasks/pending agents/tasks/active agent-08:/home/agent/grotap-platform/agents/tasks/`
- Status server: `node agents/status-server.js` running on localhost:7654

## Post-Task: Keep Servers Full
After every task completion — check slots, dispatch immediately to every idle slot.
```bash
bash agents/server-status.sh
bash agents/dispatch-execute.sh <task.md> <session>
```

## Never Do
- SSH by raw IP — use `ssh agent-NN` aliases (`~/.ssh/grotap_agents`)
- `git add -A` or `git add .`
- Leave agents idle or skip bootstrap
- Load `docs/CLAUDE.md` as agent context — use `agents/GLOBAL.md`
- Assume task files are in git (pending/active are local-only, must SCP)
