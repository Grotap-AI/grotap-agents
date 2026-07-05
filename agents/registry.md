# agents/registry.md
# Master index — modules, roles, and file tiers. Server roster lives in agents/SERVERS.md (single source).
# Tier 1 file — only Tech Lead may modify. Last updated: 2026-07-05

## Servers
See `agents/SERVERS.md` — active pool agent-02…06; special hosts (cobrowse, LLM engine); retired list.

## Module → owning server
| Module | Server | Roles (ROLE.md under agents/roles/<module>/) |
|---|---|---|
| intake | agent-02 | intake, triage |
| security | agent-02 | security-reviewer |
| planning | agent-03 | planner |
| review | agent-03 | fix-reviewer, policy-reviewer, logic-reviewer, perf-reviewer |
| execution | agent-04 primary; overflow agent-02/03/05, agent-06 (2 slots) | execute |
| enforcement | agent-04 | change-reviewer, rule-enforcer, build-validator |
| pipeline | agent-05 | pipeline-detail, audit-filters |
| approvals | agent-05 | mobile-approvals |
| dispatch | agent-06 | coordinator, watchdog |
| deployment-ops | agent-06 | deploy-verifier, deploy-executor, env-validator, health-monitor, dns-watchdog, post-deploy-qa |

## File tiers
| Tier | Files | Policy |
|---|---|---|
| 1 — Protected | GLOBAL.md, SERVERS.md, registry.md, OWNERS.md, BOOTSTRAP.md, .claude-session-init.sh | Tech Lead only |
| 2 — Domain | all `roles/*/MODULE.md` | Domain/Infra Lead |
| 3 — Role | all `roles/*/*/ROLE.md`, `roles/shared/*.md` | Role owner |
| 4 — Agent-generated | `state/handoffs/handoff-*.md` | auto, no review |

## Shared
| File | Purpose |
|---|---|
| roles/shared/handoff-schema.md | Canonical handoff fields (common + per-role) — ROLE.md files reference, never re-embed |
| roles/shared/conventions.md | Cross-cutting conventions (verdict format, DB access — direct SQL, Neon MCP retired; paths; branch naming) |
| LESSONS-ARCHIVE.md | Dated incident/review-gate ledgers (distilled into GLOBAL.md FAIL causes; not auto-loaded) |

## Innovation Review Calendar
| Cadence | Activity |
|---|---|
| Every sprint (2 weeks) | Each role owner reviews their ROLE.md sandbox additions |
| Monthly | Domain leads review MODULE.md promotions. registry.md audited for accuracy. |
| Quarterly | Tech lead reviews GLOBAL.md. Deprecated patterns past removal_date deleted. |
| On any major schema change | All MODULE.md files reviewed for staleness. Affected ROLE.md files flagged. |
