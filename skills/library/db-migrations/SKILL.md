---
name: db-migrations
description: "Use for a schema or data change. Expand, backfill, then contract on the numbered SQL migrations. Staging first. Pause before a destructive step. Invoke explicitly as db-migrations."
disable-model-invocation: true
---

Written for Grotap. Not a pstack playbook. Idempotency and "migrate callers, then delete" follow pstack principle-make-operations-idempotent and principle-migrate-callers-then-delete-legacy-apis (Lauren Tan, MIT), https://github.com/cursor/plugins/tree/fadd23794c0075468eb8964b0fd93e06e09486ad/pstack.

# Database migrations

Grotap's migration tool, as documented in this agents repo, is numbered SQL files, not Alembic. Confirm that on the platform checkout before you write a file. If that checkout has an `alembic/` directory, stop and follow Alembic. Do not invent a second history.

Documented paths:

- Control plane: `backend/db/migrations/control_plane/vNNN_*.sql`
- App schemas, both trees, same slug: `migrations/apps/<slug>/` and `ingestion-worker/migrations/apps/<slug>/`

Never edit a migration that has been applied. `CREATE TABLE IF NOT EXISTS` does not alter an existing table. A new column needs a new file.

Run on the team the task names. Keep that team's model. Do not switch models from this skill.

## Expand, then contract

One PR does not do both ends when the change is destructive.

1. **Expand.** New file only. Add a nullable column, a new table, or a new index concurrently where Postgres requires it. Keep the old shape working. Dual-read if callers still use the old column.
2. **Backfill.** A separate idempotent script. Batches. Safe to rerun after a crash. It answers: what if it runs twice, and what if it died halfway?
3. **Move callers.** Read and write the new shape. Deploy that code. Do not drop the old shape in the same release.
4. **Contract.** A later PR, after callers are gone. `NOT NULL`, drop the old column, drop the old table. Same rule: new file, never an edit of the expand file.

App-schema files are copied into both trees in the same change. The slug directory matches `apps.slug`. Pooled tenants are the default. Grants for `app_user` ship in the same file. RLS stays `FORCE ROW LEVEL SECURITY` on `current_setting('app.current_tenant_id')::uuid`. Do not weaken it. Do not run DDL on a tenant pool from a request handler.

## Rollback

Prefer a forward file that restores the expand state over editing history. Write that reverse SQL in the PR and do not apply it to production from this skill. There is no Alembic downgrade in the documented tool.

## Staging first

Apply on a Neon branch or the staging database first. Record row counts and the invariant you checked (no nulls in the new column, no orphan keys, tenant predicate still holds). Then pause. Production apply is a human step. Railway serves the API and Vercel serves the frontend: deploy the expand migration before the code that requires the new column, and deploy the contract only after the old code is gone.

## Proof

A migration PR names the file, the expand or contract phase, the staging command, the counts, and the rollback file. Use `verify-and-prove` if the change is user-visible. "It compiled" is not proof.

Reply with the phase, the new filename, the staging result, and what is still paused.
