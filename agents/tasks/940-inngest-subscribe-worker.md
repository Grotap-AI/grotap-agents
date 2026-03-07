You are working on the grotap platform codebase at /home/agent/grotap-platform.

## Task #940 — Inngest app subscribe/unsubscribe schema worker

The apps table already has db_schema, migrations, knowledge_project_id, business_rules_docs columns.
The rfid-pipe app already has db_schema='rfid_pipe' and migrations=['v001_initial.sql'] seeded.
Do NOT run any ALTER TABLE or UPDATE on the apps table — it is already done.

### What to build

Add two Inngest functions to platform/ingestion-worker/src/.

First read platform/ingestion-worker/src/inngest.ts to understand the existing function pattern.

**Function 1: app-schema-provision**

Create platform/ingestion-worker/src/functions/appSchemaProvision.ts

- Event: app/subscribed
- Payload: { tenant_id, app_slug, neon_project_id }

Logic:
1. Query control plane DB (green-rice-76766370) for the app's db_schema and migrations[]:
   SELECT db_schema, migrations FROM apps WHERE slug = $1
   Use NEON_API_KEY from process.env + Neon HTTP API to connect to control plane.
   Control plane connection: use mcp__Neon__get_connection_string equivalent — fetch from:
   GET https://console.neon.tech/api/v2/projects/green-rice-76766370/connection_uri
   Authorization: Bearer {NEON_API_KEY}

2. Get tenant's Neon connection string:
   GET https://console.neon.tech/api/v2/projects/{neon_project_id}/connection_uri
   Authorization: Bearer {NEON_API_KEY}

3. Connect to tenant DB using pg or @neondatabase/serverless (check package.json for what's available)

4. Run: CREATE SCHEMA IF NOT EXISTS {db_schema}

5. For each migration file in migrations[] array:
   - Read SQL from platform/migrations/apps/{app_slug}/{migration_file} using fs.readFileSync
   - Path relative to ingestion-worker: ../../migrations/apps/{app_slug}/{migration_file}
   - Execute against tenant DB

6. Insert into control plane app_schema_migrations for each migration applied:
   INSERT INTO app_schema_migrations (tenant_id, app_slug, migration_version, neon_project_id)
   VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING

7. Log success

Error handling: catch errors, log them, insert with schema_status='failed' — do NOT throw (allow Inngest retry).
Add 'failed' to the schema_status CHECK constraint via: ALTER TABLE app_schema_migrations DROP CONSTRAINT IF EXISTS app_schema_migrations_schema_status_check; ALTER TABLE app_schema_migrations ADD CONSTRAINT app_schema_migrations_schema_status_check CHECK (schema_status IN ('active','suspended','dropped','failed'));

**Function 2: app-schema-suspend**

Create platform/ingestion-worker/src/functions/appSchemaSuspend.ts

- Event: app/unsubscribed
- Payload: { tenant_id, app_slug, neon_project_id }

Logic:
1. Update control plane app_schema_migrations:
   UPDATE app_schema_migrations SET schema_status = 'suspended'
   WHERE tenant_id = $1 AND app_slug = $2
2. Log: "Schema preserved for 30-day grace period. Will not be dropped until grace period expires."
Do NOT drop the schema.

### Register functions

Add both functions to the Inngest serve() call in ingestion-worker. Check inngest.ts or index.ts for where functions are registered.

### Deploy

```bash
cd platform/ingestion-worker
npm install
railway up --service 179c40ce-cd06-4c66-a10b-35b347f1ac67
```

Check deployment: railway deployment list --service 179c40ce-cd06-4c66-a10b-35b347f1ac67
If FAILED check: railway logs <deployment_id>

### Commit

```
git add -A
git commit -m "feat: Inngest app subscribe/unsubscribe schema provisioning worker"
git push origin master
```
