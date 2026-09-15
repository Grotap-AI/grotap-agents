---
title: "Git"
source: rewritten-from-verified-infrastructure
converted: 2026-03-01
rewritten: 2026-09-15
component: "GitHub"
category: devops
doc_type: reference
related:
  - "Doppler"
  - "Forgejo-Cutover-Gate"
tags:
  - git
  - github
  - forgejo
  - version-control
  - source-code
  - claude-agentic
status: active
---


# Git

**GitHub is the source of truth.** All four repositories live under the `Grotap-AI` organization on
GitHub, every human and every agent pushes there, and both deploy providers build from there. A
self-hosted Forgejo instance exists and mirrors those repositories, but it is a read-only copy: no
deploy path, no build, and no release reads from it.

Any change to that arrangement is governed by `docs/06-infrastructure/forgejo-cutover-gate.md`, which
is the authority on moving the source of truth. Nothing on this page authorizes a cutover.

## 1. Repositories

| Repository | Default branch | Local path | What builds from it |
|---|---|---|---|
| `Grotap-AI/grotap-platform` | `master` | `C:\1Claude\platform\` | Railway (`api.grotap.com`), Vercel (`apps.grotap.com`) |
| `Grotap-AI/grotap-agents` | `master` | `C:\1Claude\` | Nothing deploys; `agents/dispatch.sh` bootstraps from it on every agent run |
| `Grotap-AI/grotap-landing` | `main` | not cloned | Vercel (`grotap.com`) |
| `Grotap-AI/grotap-platform-docs` | `master` | not cloned — working docs live in `C:\1Claude\docs\` | Nothing |

Read the default branch from the API or from `git ls-remote` rather than assuming `master`;
`grotap-landing` is the exception, and scripts that hard-code `master` silently mis-compare it.

## 2. The Forgejo mirror

`forge-01` (Hetzner cpx21, Ashburn) runs **Forgejo 13.0.5** behind Caddy at
`https://forge.grotap.com`. All four repositories exist there under the `Grotap-AI` organization as
**pull mirrors**, refreshing every ten minutes.

- **Direction is GitHub → Forgejo, never the reverse.** A commit that exists only on the forge does
  not exist anywhere that matters.
- **No deploy path reads from the forge.** Railway and Vercel are both wired to GitHub.
- `forge.grotap.com` is Cloudflare-proxied and currently locked at the edge by WAF ruleset
  `833d63affc5d44be931d2ce74bf8f9fd`, which admits only the five worker boxes, forge-01 and the
  owner workstation. Anything else gets a Cloudflare block rather than an application error.
- `forge-ssh.grotap.com:2222` carries git-over-SSH and is deliberately **unproxied** — Cloudflare
  cannot proxy the SSH protocol.

Treat "the forge is up and mirroring" as a statement about the forge, never as a statement about the
migration.

## 3. CI

**GitHub Actions is the live CI.** Workflows live in `.github/workflows/` and run on GitHub-hosted
runners; that is what gates merges today.

**Forgejo Actions** runs alongside it on self-hosted runners: `forgejo-runner` v13.1.0 in **HOST**
execution mode on agent-02 through agent-06, as an unprivileged `forge-runner` user inside a systemd
jail, capacity 2, registered org-wide with labels `ubuntu-latest:host` / `ubuntu-24.04:host`. Each
runner is bounded by the drop-in `/etc/systemd/system/forgejo-runner.service.d/10-resources.conf`
(agent-02..05 `CPUQuota=200%`, `MemoryHigh=1600M`, `MemoryMax=2G`; agent-06 `CPUQuota=300%`,
`MemoryHigh=3G`, `MemoryMax=4G`). A runner unit without that drop-in is a regression.

The canary repository is `Grotap-AI/forge-smoke` — one workflow that checks out, runs
`setup-python`, and proves host execution. Use it rather than creating a second canary.

## 4. The push webhook

There is one real integration between the forge and the platform:

- `POST /api/v1/forgejo/pipeline-sync` on `api.grotap.com`
- Authenticated by **HMAC-SHA256 over the raw request body**, keyed by `FORGEJO_WEBHOOK_SECRET`
  (Doppler `grotap`, `prd`/`dev`). It accepts Forgejo's `X-Forgejo-Signature` (bare hex) or the
  GitHub-style `X-Hub-Signature-256`.
- Returns **202** on a valid signature. It fails closed when the secret is unset.
- Sibling health probe: `GET /api/v1/forgejo/health` returns `{"ok":true,"configured":<bool>}`.
- Implementation: `backend/app/routers/forgejo.py` (commit `f86d599ed`), covered by
  `backend/tests/test_forgejo_webhook.py`.

Auth here is deliberately **not** the platform-wide `X-Node-Secret`. The forge is a separate trust
domain — it renders untrusted diffs and runs a web UI — so a breach there must not hand over the
credential that opens every other machine endpoint.

**The webhook records pushes and cannot start an agent run.** That is a design decision stated in the
handler's own docstring, not a gap waiting to be filled: letting a forge push spawn execution would
hand anyone who can write to a branch a way to run code on the fleet. Work continues to come from
`pipeline_cases` via the assign loop. Do not design anything on the assumption that pushing to the
forge triggers work.

## 5. Secrets

**Doppler only** — project `grotap`, configs `prd` (Railway + Vercel) and `dev` (local).

```
doppler secrets set KEY="val" --project grotap --config dev   # repeat for prd
doppler run -p grotap -c prd -- <command>
```

The **only** GitHub secret is `DOPPLER_SERVICE_TOKEN`, which exists so CI can fetch everything else.
Never add a secret to GitHub, to Forgejo, or to a committed `.env`. Railway environment variables are
static copies — after any Doppler rotation, refresh every service copy
(`scripts/railway_secret_audit.py`).

## 6. Working in the repositories

**Branching.** Staging is suspended; changes ship `master` to prod. Human feature work goes on a
short-lived branch named for its kind (`feat/…`, `fix/…`, `docs/…`) and merges to `master`. Agent
work goes on `case-CASE-YYYYMMDD-XXXXXX`, one branch per case, merged by the review gate as
`merge: case-CASE-… (orchestrator-approved)`.

**Commit messages.** Conventional commits with the surface as the scope —
`fix(loop-engine): …`, `feat(print-cloud): …`, `security(ci): …`, `docs: …`. The subject states what
changed and, for a fix, what was actually wrong.

**Shared-tree etiquette.** Several Claude sessions often work in the same local checkout at once, and
a session has previously swept a peer's in-flight work into its own commit. Multi-file work belongs
in its own git worktree. On a shared tree, stage explicit paths only — never `git add -A` or
`git add .` — and never `git stash`, `git reset`, `git checkout --`, amend, or rebase over files you
did not author in this session. Commit small, `pull --rebase` first, and push promptly. The full rule
is in `platform/CLAUDE.md` under "Concurrent Claude Sessions".

**Before committing.** Run `tsc` / `py_compile` over what you touched, and put the change through a
Codex review; a review finding blocks the commit. Codex review complements the four-reviewer agent
gate — it does not replace it.

## Summary Checklist

| Concern | Where it actually lives |
|---|---|
| Source of truth | GitHub, `Grotap-AI` org, four repositories |
| Deploys | Railway and Vercel, both from GitHub |
| Mirror | Forgejo at `forge.grotap.com`, pull-only, 10-minute refresh, nothing deploys from it |
| CI | GitHub Actions (live); Forgejo Actions on self-hosted host-mode runners, agent-02..06 |
| Forge to platform | `POST /api/v1/forgejo/pipeline-sync`, HMAC-SHA256, records pushes only |
| Secrets | Doppler (`grotap` / `prd`, `dev`); the only GitHub secret is `DOPPLER_SERVICE_TOKEN` |
| Changing any of the above | `docs/06-infrastructure/forgejo-cutover-gate.md` |

---

## Agent Instructions

- **Use this when:** working with the repositories, the Forgejo mirror, or CI wiring
- **Before this:** None — foundational reference
- **After this:** `docs/06-infrastructure/forgejo-cutover-gate.md` before touching the source of truth
