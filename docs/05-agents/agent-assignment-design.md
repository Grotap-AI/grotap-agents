# Agent Assignment Design — separate assignment, no model lock-in, lower cost, higher throughput

**Status:** OFFICIAL — adopted by the owner 2026-10-11. **Design only until the Manor View go-live freeze ends
(2026-11-13); build starts 2026-11-17.** Applies to every AI working in these repos (Claude Code, Grok, Gemini, Codex).

## 1. Goals (owner, 2026-10-11)

1. **Separate agent-team assignment from execution.** Deciding *who* does a job is one layer; doing the job is another.
2. **No vendor lock-in on any model.** Any model can be swapped by config; no workflow depends on one vendor.
3. **Reduce cost.**
4. **Increase performance** — more merged-and-deployed changes per dollar and per hour.

## 2. Principles carried over from the infrastructure review

The owner's infrastructure document ("Improving Infrastructure for Rapid Development and Low Risk") is about app
isolation. Its principles transfer to the agent fleet; its concrete app-split steps do not (see §7).

| Infrastructure idea | Agent-fleet equivalent |
|---|---|
| Thin gateway that routes to isolated services | LangGraph orchestrator is the **only** assignment layer; executors are interchangeable workers behind a fixed contract |
| Independently deployable remotes (module federation) | **Pluggable executor adapters** — adding/removing a vendor is an adapter + config, never an orchestrator change |
| Per-app database roles, no cross-talk | Executors never touch another case's worktree or state; hand-off only through orchestrator state |
| Path-based CI gates | **Changed paths set the risk tier**, which sets model strength and review depth |
| Pre-flight import check | **Deterministic gates before any LLM review** (commit exists, tsc/py_compile, migration-validator, secret scan) |
| Always-green, trusted migration validator | Only gates that can actually fail; an "unsure" verdict escalates, never silently rejects |
| Doppler least privilege | Per-role / per-executor scoped secrets (`grotap-scoped` configs); one vendor's key never exposes another's |

## 3. Architecture

### 3.1 Assignment layer (LangGraph orchestrator)
`intake → classify (task type, risk tier, size) → select executor profile (routing table) → budget check → dispatch →
deterministic gates → review ladder → policy → human gate (exceptions only) → deploy → learn`.

- **Teams become capability profiles**, not boxes or seats: `{model, tools, allowed risk tiers, cost ceiling}`.
- The **routing table is config**, not code. Today routing is hardcoded in backend
  `agent_dispatch._route_dispatch`; that moves into the orchestrator's config-driven selector.
- The orchestrator enforces a **dollar cap per case and per org** itself — it never trusts runner-reported token counts.
  Direct `/dispatch` calls go through the same budget gate.

### 3.2 Executor contract (identical for every vendor)
- **Input:** case id, fresh worktree from `origin/master`, allowed paths, risk tier, dollar cap, turn cap, model id.
- **Output:** commit SHA **or** a named failure class (`no_commit`, `gate_fail`, `budget_exceeded`, `tool_error`,
  `model_refused`), plus measured cost and wall time.
- "No commit" fails immediately — it was the dominant failure of the previous multi-team setup.
- Adapters, in order: **(1) Claude Code**, **(2) one OpenRouter-backed open-model CLI worker**, then **(3) Codex** after
  the first scorecard (owner decision 2026-10-11).

### 3.3 Model registry (anti-lock-in)
- Model ids live only in config (OpenRouter for open models; Anthropic and OpenAI direct).
- A **per-task-type scorecard** picks defaults: pass rate at the gates, cost per merged change, wall time. Re-run when
  a new model ships; promote by config edit.
- Sensitive / PII / secret-bearing work stays on Claude (Lane B) — never OpenRouter.

### 3.4 Risk tiers (from changed paths)
| Tier | Example paths | Executor | Review |
|---|---|---|---|
| T0 low | docs, copy, styles, tests-only | cheapest passing model | deterministic gates + cheap reviewer |
| T1 normal | app routers/pages, scripts | mid model | gates + cheap reviewer, escalate on doubt |
| T2 high | migrations, auth, billing/money, secrets, infra/CI, orchestrator | strongest model | gates + full ladder + human on exceptions |

### 3.5 Review ladder
Deterministic gates first; then cheap reviewer → second opinion → strong final reviewer → human. Only escalate on
doubt or tier. An "unsure" verdict goes up a rung, never becomes a reject.

## 4. Cost levers (measured basis)
- Spend is dominated by cache reads and grows with **context size × turns** → smaller context packs, per-tier turn caps.
- Cheap models for triage, classification, summaries, learning extraction; strong models only for T2 or after failure.
- Fail fast on deterministic gates so review tokens are never spent on broken work.
- **Prerequisite:** cost telemetry must cover ~100% of billed spend (it captured 2–4% in September), or no saving can be proven.

## 5. Performance
- North-star metric: merged-and-deployed changes per dollar and per hour, per executor profile.
- Parallelism up to real slot capacity; fail-fast cuts wasted attempts; finalize-node learnings feed the next case's context.

## 6. Build phases (start 2026-11-17)
1. **Measure:** full cost telemetry per case/executor; baseline the scorecard on the Claude Code executor.
2. **Separate:** move assignment from backend `_route_dispatch` into the orchestrator's config-driven selector; define
   the executor contract; wrap Claude Code as adapter #1.
3. **Gate:** deterministic pre-review gates + risk tiers from changed paths; per-case dollar and turn caps.
4. **Diversify:** OpenRouter open-model worker as adapter #2; run the scorecard; promote by config.
5. **Extend:** Codex adapter #3; retire per-team budgets in favour of per-case/per-org caps.
6. **Least privilege:** per-executor scoped Doppler configs; runner permission allowlist instead of skip-permissions.

## 7. Not adopted from the infrastructure document
FastAPI gateway + per-app Railway services, frontend module federation, per-app Postgres roles (deferred: under
5 active users/day they add more surface than they remove); the three-project Doppler split (we use `grotap-scoped`
configs instead); the document's wrong premises (yoyo, Postgres 16, a read/write fleet token, `sync-all-agents.sh`).

## 8. Preconditions before the build
- Pipeline dispatch freeze (2026-10-11) lifted by the owner.
- Resumer guard (`CASE-20261011-ED3338`): `graph-resumer.ts` must skip cases whose status is done/closed/merged.
- Mechanical-gates `ALLOW-DELETION:` trailer must read the PR head SHA, not GitHub's merge commit.
