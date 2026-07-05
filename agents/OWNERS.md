# agents/OWNERS.md
# Ownership contract. Owner AND backup for every file = @Grotap1 (sole operator — expand as team grows).
# Tier 1: Tech Lead only (PR + 2 senior reviews + 48hr window)
# Tier 2: Domain/Infra Lead (PR + 1 senior + 1 peer + 24hr window)
# Tier 3: Role Owner (PR + 1 peer review, same-day merge allowed)
# Tier 4: Agent auto-generated (no review, auto-committed)

## Tier 1 — Protected
agents/GLOBAL.md
agents/SERVERS.md
agents/registry.md
agents/OWNERS.md
BOOTSTRAP.md
.claude-session-init.sh

## Tier 2 — Module Files
agents/roles/{intake,security,pipeline,approvals,planning,review,execution,enforcement,dispatch,deployment-ops}/MODULE.md

## Tier 3 — Role + Shared Files
agents/roles/*/*/ROLE.md          (all 23 — inventory in registry.md)
agents/roles/shared/handoff-schema.md
agents/roles/shared/conventions.md
agents/LESSONS-ARCHIVE.md

## Tier 4 — Agent-Generated (no review required)
state/handoffs/handoff-*.md
