# BOOTSTRAP.md — Mandatory Session Init. No exceptions. No quick sessions.

## 6 Steps (do all, in order)
1. `git pull origin master` + `git rev-parse HEAD` → record as SESSION_COMMIT
2. `./.claude-session-init.sh --validate` → STOP if fails, report error
3. `/codex:setup` → verify Codex CLI ready. WARN if unavailable (non-blocking).
4. Load context in order: `agents/GLOBAL.md` → `agents/SERVERS.md` → `roles/{module}/MODULE.md` → `roles/{module}/{role}/ROLE.md` → `state/handoffs/handoff-{ticketId}-*.md`
5. Check handoff `generated_at_commit` vs SESSION_COMMIT: 1-5 commits = flag STALE; 6+ = stop, request human review; missing field = reject, request regeneration
6. Output: `BOOTSTRAP COMPLETE | Commit: {SESSION_COMMIT} | Role: {role} | Server: {server} | Codex: {ready|unavailable}`

Identify your server by IP (`hostname -I`) against the roster in `agents/SERVERS.md`.
Overflow executor: load `roles/execution/MODULE.md` + `roles/execution/execute/ROLE.md`.

## Server Setup Checklist (new server or after reset — full list in agents/SERVERS.md)
- API key in **both**: `/home/agent/.env` AND `/home/agent/.profile` (`export ANTHROPIC_API_KEY=...`)
- Git safe.directory if root/agent mismatch: `git config --global --add safe.directory /home/agent/grotap-platform`
- SCP task files (not in git): `scp -r agents/tasks/pending agents/tasks/active agent-06:/home/agent/grotap-platform/agents/tasks/`
- Status server: `node agents/status-server.js` running on localhost:7654

## Post-Task
The continuous dispatcher (agent-06 + backend loop) refills slots automatically. For manual ops:
`bash agents/server-status.sh` then `bash agents/dispatch-execute.sh <task.md> <session>` (platform repo root).

## Never Do
- SSH by raw IP — use `ssh agent-NN` aliases (`~/.ssh/grotap_agents`)
- `git add -A` or `git add .`
- Leave agents idle or skip bootstrap
- Load `docs/CLAUDE.md` as agent context — use `agents/GLOBAL.md`
- Assume task files are in git (pending/active are local-only, must SCP)
