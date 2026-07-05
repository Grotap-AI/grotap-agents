# Shared Handoff Schema — All Roles
# Instead of embedding 40-65 line templates in every ROLE.md, roles reference this file.
# Each role section below lists ONLY the unique output fields for that role.

## Common Fields (every handoff)
```
generated_at_commit: {40-char SHA from SESSION_COMMIT}
generated_at_timestamp: {UTC ISO 8601}
generated_by_role: {role-name}
generated_by_server: {agent-XX}
ticket_id: {ticketId}
next_role: {role or 'none'}
next_server: {agent-XX or 'none'}
priority: normal | urgent | blocked
```

## Staleness Rule
Receiving agent compares `generated_at_commit` to their SESSION_COMMIT:
- Match → proceed | 1–5 stale → flag + re-read docs | 6+ stale → STOP

---

## Role-Specific Output Fields

### intake
- validation_result: PASS | REJECT
- rejection_reason: {reason or NONE}
- flags_detected: {list or NONE}
- stage_set_to: triaged

### triage
- module_assigned: {module name}
- routing_reason: {one line}

### execute
- files_created: {list or NONE}
- files_modified: {list or NONE}
- migrations_run: YES | NO
- deployed_frontend: YES | NO
- deployed_backend: YES | NO
- railway_status: SUCCESS | BUILDING | FAILED | N/A

### planner
- files_to_create: {list or NONE}
- files_to_modify: {list or NONE}
- db_migrations_required: YES | NO
- new_app_checklist_required: YES | NO
- approval_gates: {list or NONE}
- rules_check: all 8 satisfied — YES | NO

### fix-reviewer
- verdict: PASS | FAIL
- root_cause_addressed: YES | NO
- regressions_found: {list or NONE}
- unused_imports_found: YES | NO

### logic-reviewer
- verdict: PASS | FAIL
- happy_path_correct: YES | NO
- error_paths_handled: YES | NO
- jsonb_operators_correct: YES | NO
- org_id_column_correct: YES | NO

### perf-reviewer
- verdict: PASS | FAIL
- n_plus_one_found: YES | NO
- unbounded_queries_found: YES | NO
- render_bottlenecks_found: YES | NO
- token_waste_found: YES | NO

### policy-reviewer
- verdict: PASS | FAIL
- rules_violated: {list or NONE}
- patterns_violated: {list or NONE}

### security-reviewer
- verdict: PASS | FAIL
- findings_count: {n}
- owasp_findings: {list or NONE}
- rule_violations: {list or NONE}
- tenant_isolation_verified: YES | NO

### build-validator
- verdict: PASS | FAIL
- typescript_errors: {count or 0}
- eslint_errors: {count or 0}
- python_syntax_errors: {count or 0}
- fastapi_starts: YES | NO
- health_routes_present: YES | NO
- env_files_introduced: YES | NO

### change-reviewer
- verdict: PASS | FAIL
- changes_match_plan: YES | NO
- scope_creep_found: YES | NO
- missing_plan_items: {list or NONE}

### rule-enforcer
- verdict: PASS | FAIL
- rules_violated: {list with rule numbers or NONE}
- violation_confirmed: YES | NO | FALSE-POSITIVE
- enforcement_action: block | warn | escalate

### mobile-approvals
- decision: approved | rejected | expired
- decided_at: {timestamp or NONE}
- action_requested: {one-line summary}

### pipeline-detail
- overall_status: APPROVED | BLOCKED | IN-REVIEW
- reviewers_passed: {list}
- reviewers_failed: {list or NONE}
- reviewers_pending: {list or NONE}

### audit-filters
- verdict: PASS | FAIL
- findings_count: {n}
- tenant_scoping_clean: YES | NO
- jsonb_operators_clean: YES | NO
