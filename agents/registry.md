# agents/registry.md
# Master index — single source of truth for all servers, modules, roles, and files.
# Tier 1 file — only Tech Lead may modify.
# Last updated: 2026-03-06

## Servers
| Server | IP | Roles |
|---|---|---|
| agent-02 | 5.161.74.39 | Intake, Triage, Security Reviewer |
| agent-03 | 5.161.81.193 | Planner, Fix Reviewer, Policy Reviewer, Logic Reviewer, Perf Reviewer |
| agent-04 | 178.156.222.220 | Execute, Change Reviewer, Rule Enforcer, Build Validator |
| agent-05 | 5.161.73.195 | Pipeline Detail, Audit Filters, Mobile Approvals |

## Tier 1 — Protected Files
| File | Owner |
|---|---|
| agents/GLOBAL.md | Tech Lead |
| agents/registry.md | Tech Lead |
| agents/OWNERS.md | Tech Lead |
| BOOTSTRAP.md | Tech Lead |
| .claude-session-init.sh | Infra Lead |

## Tier 2 — Domain Files
| File | Server | Owner |
|---|---|---|
| agents/servers/agent-02.md | Agent-02 | Infra Lead |
| agents/servers/agent-03.md | Agent-03 | Infra Lead |
| agents/servers/agent-04.md | Agent-04 | Infra Lead |
| agents/servers/agent-05.md | Agent-05 | Infra Lead |
| agents/roles/intake/MODULE.md | Agent-02 | Domain Lead |
| agents/roles/security/MODULE.md | Agent-02 | Domain Lead |
| agents/roles/pipeline/MODULE.md | Agent-05 | Domain Lead |
| agents/roles/approvals/MODULE.md | Agent-05 | Domain Lead |
| agents/roles/planning/MODULE.md | Agent-03 | Domain Lead |
| agents/roles/review/MODULE.md | Agent-03 | Domain Lead |
| agents/roles/execution/MODULE.md | Agent-04 | Domain Lead |
| agents/roles/enforcement/MODULE.md | Agent-04 | Domain Lead |

## Tier 3 — Role Files
| File | Server | Role |
|---|---|---|
| agents/roles/intake/intake/ROLE.md | Agent-02 | Intake |
| agents/roles/intake/triage/ROLE.md | Agent-02 | Triage |
| agents/roles/security/security-reviewer/ROLE.md | Agent-02 | Security Reviewer |
| agents/roles/pipeline/pipeline-detail/ROLE.md | Agent-05 | Pipeline Detail |
| agents/roles/pipeline/audit-filters/ROLE.md | Agent-05 | Audit Filters |
| agents/roles/approvals/mobile-approvals/ROLE.md | Agent-05 | Mobile Approvals |
| agents/roles/planning/planner/ROLE.md | Agent-03 | Planner |
| agents/roles/review/fix-reviewer/ROLE.md | Agent-03 | Fix Reviewer |
| agents/roles/review/policy-reviewer/ROLE.md | Agent-03 | Policy Reviewer |
| agents/roles/review/logic-reviewer/ROLE.md | Agent-03 | Logic Reviewer |
| agents/roles/review/perf-reviewer/ROLE.md | Agent-03 | Perf Reviewer |
| agents/roles/execution/execute/ROLE.md | Agent-04 | Execute |
| agents/roles/enforcement/change-reviewer/ROLE.md | Agent-04 | Change Reviewer |
| agents/roles/enforcement/rule-enforcer/ROLE.md | Agent-04 | Rule Enforcer |
| agents/roles/enforcement/build-validator/ROLE.md | Agent-04 | Build Validator |

## Shared
| File | Purpose |
|---|---|
| agents/roles/shared/conventions.md | Cross-cutting conventions (handoff format, verdict format, Neon MCP) |

## Innovation Review Calendar
| Cadence | Activity |
|---|---|
| Every sprint (2 weeks) | Each role owner reviews their ROLE.md sandbox additions |
| Monthly | Domain leads review MODULE.md promotions. registry.md audited for accuracy. |
| Quarterly | Tech lead reviews GLOBAL.md. Deprecated patterns past removal_date deleted. sandbox/proposals/ pruned. |
| On any major schema change | All MODULE.md files reviewed for staleness. Affected ROLE.md files flagged. |
