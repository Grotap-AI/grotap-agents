# agents/roles/approvals/MODULE.md
# Approvals module — Layer 2 domain context.
# Covers: human-in-the-loop approval flows, mobile approval interface.

## Module Scope
The approvals module handles tasks that require a human decision before
the agent pipeline can continue. This maps to the platform's ApprovalsPage
and the LangGraph `interrupt()` mechanism.

## When Approvals Are Required
- Agent farm scale-out operations (Terraform provisioning)
- Stripe billing changes (plan upgrades, cancellations)
- Production deployments flagged as high-risk
- Any task where an agent hits an `interrupt()` checkpoint

## Platform Integration
- Frontend: `ApprovalsPage` at `/approvals` — human reviews and approves/rejects
- Backend: `interrupt()` in LangGraph graph suspends execution pending approval
- Mobile: Expo app surfaces pending approvals via push notification

## Approval States
- `pending` — awaiting human decision
- `approved` — human confirmed, agent resumes
- `rejected` — human declined, task routed back for re-planning
- `expired` — no decision within timeout window (24hr default)

## Key References
- LangGraph interrupt: `docs/05-agents/langgraph-plan-execute-verify.md`
- Agent farm approvals: `docs/01-platform/architecture-overview.md`
