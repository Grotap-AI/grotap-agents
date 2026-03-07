# agents/roles/enforcement/MODULE.md
# Enforcement module — Layer 2 domain context.
# Covers: change review, rule enforcement, and build validation.

## Module Scope
The enforcement module ensures that every change landing on master is safe,
rule-compliant, and builds cleanly. It contains three roles, all on Agent-04.

## Role Summary
| Role | When It Runs | What It Enforces |
|---|---|---|
| Change Reviewer | task.type == 'change-review' | Scope of change vs. plan — no scope creep |
| Rule Enforcer | task.type == 'rule-enforcement' OR flags contain 'rule-violation' | Any of the 9 absolute rules |
| Build Validator | task.type == 'build' OR task.stage == 'build-validation' | Zero compile errors, zero lint errors |

## Enforcement Authority
- Any FAIL from this module blocks merge unconditionally
- Rule Enforcer can escalate to agent-02 / security-reviewer for Rule 1–6 violations
- Build Validator failure means no deployment — period

## Key References
- Absolute rules: `agents/GLOBAL.md` rules 1–9
- TypeScript config: `platform/frontend/tsconfig.json` (`noUnusedLocals: true`)
- Railway health check: `@router.get("")` AND `@router.get("/")` — Railway hits `/health` not `/health/`
