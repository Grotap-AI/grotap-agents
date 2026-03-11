# BOOTSTRAP.md
# READ THIS BEFORE ANYTHING ELSE. NO EXCEPTIONS.
# This file contains no domain knowledge. Its sole purpose is session initialization.

## Mandatory Session Initialization

Before reading any other MD file or beginning any task, you MUST complete
all five steps below. Do not skip steps on "quick" sessions — there are none.

---

### Step 1 — Verify Git State
Run: `git pull origin master`
Run: `git rev-parse HEAD`
Record the full 40-character commit hash. This is your SESSION_COMMIT.
Report: `Session initialized at commit: {SESSION_COMMIT}`

---

### Step 2 — Validate MD Structure
Run: `./.claude-session-init.sh --validate`
If validation fails: STOP. Report the failure. Do not proceed.

---

### Step 3 — Load Your Context
Load files in this exact order:
1. `agents/GLOBAL.md`                                     ← universal rules, stack, IDs
2. `agents/servers/{your-server}.md`                      ← your roles and triggers
3. `agents/roles/{module}/MODULE.md`                      ← domain context for your task
4. `agents/roles/{module}/{role}/ROLE.md`                 ← your specific role instructions
5. `state/handoffs/handoff-{ticketId}-{timestamp}.md`     ← task context (if exists)

Your server is determined by the IP you are running on:
| IP | Server | File | Notes |
|---|---|---|---|
| 5.161.189.143 | Agent-01 | agents/servers/agent-01.md | Primary executor (3 worktree slots) |
| 5.161.74.39 | Agent-02 | agents/servers/agent-02.md | Overflow executor when idle |
| 5.161.81.193 | Agent-03 | agents/servers/agent-03.md | Overflow executor when idle |
| 178.156.222.220 | Agent-04 | agents/servers/agent-04.md | Primary executor (3 worktree slots) |
| 5.161.73.195 | Agent-05 | agents/servers/agent-05.md | Overflow executor when idle |
| 5.78.178.81 | Agent-06 | agents/servers/agent-06.md | Deploy ops only — never executes |
| 89.167.66.105 | Agent-07 | agents/servers/agent-07.md | Primary executor (3 worktree slots) |
| 77.42.42.213 | Agent-08 | agents/servers/agent-08.md | **Dispatch Coordinator** (systemd) + Execute (2 slots) |

If you are executing a task via overflow (dispatched by `dispatch-execute.sh`),
load `roles/execution/MODULE.md` + `roles/execution/execute/ROLE.md` as your role context.
Your primary roles still take priority — if a primary-role task arrives, it preempts overflow.

---

### Step 4 — Check Handoff Freshness
If a handoff file exists for your task, compare its `generated_at_commit`
field to your SESSION_COMMIT.

| Condition | Action |
|---|---|
| Commits match | Proceed normally |
| Differs by 1–5 commits | Flag STALE. Re-read MODULE.md and ROLE.md. Add caution note to first response. |
| Differs by 6+ commits | Flag SEVERELY STALE. Stop and request human review before proceeding. |
| `generated_at_commit` field missing | Reject handoff as malformed. Request regeneration. |

---

### Step 5 — Confirm Ready
Output exactly:
`BOOTSTRAP COMPLETE | Commit: {SESSION_COMMIT} | Role: {role} | Server: {server}`

Only after this confirmation may you begin the assigned task.

---

## Dispatch Policy — 24/7 Continuous
After bootstrap and task completion, the coordinator MUST:
1. Run `bash agents/server-status.sh` to check idle slots
2. Dispatch tasks to every idle slot — no server sits idle
3. Priority: `pending/` tasks first, then `active/` backlog (lowest ID first)
4. Verify each dispatch: check tmux session started on target server
5. If a server errors (missing API key, stale worktree): fix and re-dispatch immediately
6. Never stop. Never pause. When one batch finishes, dispatch the next.

## SSH Connection — MANDATORY
All agent servers use SSH key auth. **Never connect by raw IP.** Use the configured aliases.
```bash
# CORRECT — uses ~/.ssh/config aliases (Key: ~/.ssh/grotap_agents)
ssh agent-01        # 5.161.189.143  (User: agent)
ssh agent-02        # 5.161.74.39    (User: root)
ssh agent-03        # 5.161.81.193   (User: root)
ssh agent-04        # 178.156.222.220 (User: root)
ssh agent-05        # 5.161.73.195   (User: root)
ssh agent-06        # 5.78.178.81    (User: root)
ssh agent-07        # 89.167.66.105  (User: root)
ssh agent-08        # 77.42.42.213   (User: agent)

# WRONG — wastes tokens on auth failures
ssh root@5.161.189.143
ssh agent@5.161.74.39
ssh 5.161.189.143
```
If SSH fails: check `~/.ssh/config` — Agent-01/08 use `User agent`, all others use `User root`.

## Known Server Setup Requirements
Before dispatching, verify these are in place on every executor server:
1. **API key in BOTH files**: `/home/agent/.env` AND `/home/agent/.profile` must contain `export ANTHROPIC_API_KEY=...`
2. **Git safe.directory**: On servers where dispatch runs as root but repos are owned by `agent`, run:
   `git config --global --add safe.directory /home/agent/grotap-platform`
   `git config --global --add safe.directory /home/agent/grotap-agents`
3. **Task files not in git**: `agents/tasks/pending/` and `agents/tasks/active/` are local-only. When setting up dispatch on a new server, SCP task files first:
   `scp -r agents/tasks/pending agent-08:/home/agent/grotap-platform/agents/tasks/`
   `scp -r agents/tasks/active agent-08:/home/agent/grotap-platform/agents/tasks/`
4. **SSH from dispatch coordinator (agent-08)**: Needs `~/.ssh/grotap_agents` key + `~/.ssh/config` with all server entries
5. **Status server**: `node agents/status-server.js` must be running locally for dashboard to show data

## Server SSH Access Matrix
| Server | `agent` user SSH | `root` user SSH | Notes |
|--------|:-:|:-:|---|
| agent-01 | OK | OK | Primary executor |
| agent-02 | root only | OK | Overflow |
| agent-03 | root only | OK | Overflow |
| agent-04 | root only | OK | Primary executor |
| agent-05 | root only | OK | Overflow |
| agent-06 | root only | OK | Deploy only — no Claude CLI |
| agent-07 | root only | OK | Primary executor |
| agent-08 | OK | OK | Dispatch coordinator |

`dispatch.sh` uses `root@IP` for all operations (mkdir, scp, tmux). This is correct.
`server-status.sh` and `status-server.js` also use `root@IP`. This is correct.
Local `ssh agent-XX` aliases use mixed users — see `~/.ssh/config`.

## Anti-Patterns (never do these)
- Skip bootstrap on "quick" sessions — every session bootstraps, no exceptions
- **SSH by raw IP** — always use `ssh agent-XX` aliases, never `ssh root@<ip>` or `ssh <ip>`
- Load agents/tasks/*.md as context — task files are inputs, not context
- Load docs/CLAUDE.md as context — human docs only, use agents/GLOBAL.md instead
- Load CLAUDE_CODE_INSTRUCTIONS.md — planning artifact, archived
- Begin work before outputting BOOTSTRAP COMPLETE confirmation
- **Leave agents idle** — if a server has free slots, dispatch immediately
- **Assume task files are in git** — pending/active dirs are local, must be synced manually
- **Forget status-server.js** — dashboard is blank without it running on localhost:7654
