You are working on the grotap platform codebase at /home/agent/grotap-platform.

## Task #938 — RFID Pipe migration files (DB already done)

The grotap tenant DB already has the rfid_pipe schema and all tables migrated.
The apps table already has db_schema='rfid_pipe', migrations=['v001_initial.sql'].
The app_schema_migrations record is already inserted.

You only need to create the migration SQL files on disk and update a comment.

### Step 1 — Create migration directory

Create directory: platform/migrations/apps/rfid-pipe/

### Step 2 — Create v001_initial.sql

Create platform/migrations/apps/rfid-pipe/v001_initial.sql — canonical migration for NEW tenants subscribing to RFID Pipe.

Read platform/backend/migrations/rfid_pipe.sql for the exact column definitions.

The v001_initial.sql must:
1. CREATE SCHEMA IF NOT EXISTS rfid_pipe;
2. Create all 5 tables with rfid_pipe. prefix
3. ALTER TABLE ... ENABLE ROW LEVEL SECURITY on each
4. CREATE POLICY tenant_isolation on each table:
   USING (tenant_id = (SELECT current_setting('app.current_tenant_id')::uuid))
5. All indexes with rfid_pipe. context

Tables: rfid_pipe.rfid_batch_templates, rfid_pipe.rfid_scan_sessions, rfid_pipe.rfid_scan_records, rfid_pipe.ignored_rfid_tags, rfid_pipe.rfid_audit_log

### Step 3 — Create v000_migrate_existing.sql

Create platform/migrations/apps/rfid-pipe/v000_migrate_existing.sql:

```sql
-- One-time: move existing RFID tables into rfid_pipe schema (already applied to grotap tenant)
CREATE SCHEMA IF NOT EXISTS rfid_pipe;
ALTER TABLE IF EXISTS rfid_batch_templates SET SCHEMA rfid_pipe;
ALTER TABLE IF EXISTS rfid_scan_sessions SET SCHEMA rfid_pipe;
ALTER TABLE IF EXISTS rfid_scan_records SET SCHEMA rfid_pipe;
ALTER TABLE IF EXISTS ignored_rfid_tags SET SCHEMA rfid_pipe;
ALTER TABLE IF EXISTS rfid_audit_log SET SCHEMA rfid_pipe;
```

### Step 4 — Update platform/backend/migrations/rfid_pipe.sql

Add this comment at the top of the file (after the existing header):
```
-- NOTE: This file is retained for reference only.
-- The canonical migration for new tenants is: platform/migrations/apps/rfid-pipe/v001_initial.sql
-- Existing tenants were migrated using: platform/migrations/apps/rfid-pipe/v000_migrate_existing.sql
```

### Step 5 — Commit and push

```
git add -A
git commit -m "feat: add rfid-pipe migration files to platform/migrations/apps/"
git push origin master
```
