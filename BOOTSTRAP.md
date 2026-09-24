# BOOTSTRAP.md — Mandatory Session Init. No exceptions. No quick sessions.

## 6 Steps (do all, in order)
1. `git pull origin master` + `git rev-parse HEAD` → record as SESSION_COMMIT
2. `./.claude-session-init.sh --validate` → STOP if fails, report error
3. `/codex:setup` → verify Codex CLI ready. WARN if unavailable (non-blocking).
4. Load context in order: `agents/GLOBAL.md` → `agents/SERVERS.md` → `roles/{module}/MODULE.md` → `roles/{module}/{role}/ROLE.md` → `state/handoffs/handoff-{ticketId}-*.md`. Implemented-plan must-obey pointers live in `agents/GLOBAL.md`; do not load full plan novels.
5. Check handoff `generated_at_commit` vs SESSION_COMMIT: 1-5 commits = flag STALE; 6+ = stop, request human review; missing field = reject, request regeneration
6. Output: `BOOTSTRAP COMPLETE | Commit: {SESSION_COMMIT} | Role: {role} | Server: {server} | Codex: {ready|unavailable}`

Identify your server by IP (`hostname -I`) against the roster in `agents/SERVERS.md`.
Fleet names: `docs/GROTAP-SERVER-RENAME-PLAN.md` (status + Astra GO: `docs/GROTAP-SERVER-RENAME-STATUS.md`, `docs/GROTAP-PROMPT-ASTRA-PROVISION.md`).
Overflow executor: load `roles/execution/MODULE.md` + `roles/execution/execute/ROLE.md`.

## Server Setup Checklist (new server or after reset — full list in agents/SERVERS.md)
- Swap: `bash agents/ensure-swap.sh` (this repo; idempotent 4 GiB swap + swappiness). Re-run after ANY hard reset/rebuild — OOM has wedged two boxes. Also runs automatically in grotap-platform `agents/setup-server.sh`.
- API key in **both**: `/home/agent/.env` AND `/home/agent/.profile` (`export ANTHROPIC_API_KEY=...`)
- Git safe.directory if root/agent mismatch: `git config --global --add safe.directory /home/agent/grotap-platform`
- SCP task files (not in git): `scp -r agents/tasks/pending agents/tasks/active agent-06-claude:/home/agent/grotap-platform/agents/tasks/` — live ops host (`5.161.53.103`). `agent-05-claude` (Hillsboro) is OFF.
- Status server: `node agents/status-server.js` running on localhost:7654

## Post-Task
The continuous dispatcher (backend loop, with live ops on `agent-06-claude` at `5.161.53.103`) refills slots automatically. For manual ops:
`bash agents/server-status.sh` then `bash agents/dispatch-execute.sh <task.md> <session>` (platform repo root).

## Never Do
- SSH by raw IP — use the Cloud name in `agents/SERVERS.md` (`ssh agent-01-claude`, `ssh agent-10-codex`, `ssh monitor-01-deepseek`, `ssh prompt-01-claude`). Short alias `ssh agent-01` is `agent-01-claude` at `5.161.74.39`; `ssh agent-02` is `agent-02-claude`. Jumpbox is `prompt-01-claude` at `178.156.209.112`. Key: `~/.ssh/grotap_agents`
- `git add -A` or `git add .`
- Leave agents idle or skip bootstrap
- Load `docs/CLAUDE.md` as agent context — use `agents/GLOBAL.md`
- Assume task files are in git (pending/active are local-only, must SCP)
