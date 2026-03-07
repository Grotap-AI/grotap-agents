You are working on the grotap platform codebase at /home/agent/grotap-platform.

## Task #939 — Phase 1: Update RFID backend to use rfid_pipe schema prefix

The RFID Pipe tables have been moved to the `rfid_pipe` PostgreSQL schema (task #938). All queries in the backend must be updated to use the schema-prefixed table names.

### Architecture reference
Read `docs/03-database/neon-app-schema-architecture.md` for context.

### What to change

**File: `platform/backend/app/routers/rfid_pipe.py`**

Replace all bare table names in SQL queries with schema-prefixed versions:

| Old name | New name |
|---|---|
| `rfid_batch_templates` | `rfid_pipe.rfid_batch_templates` |
| `rfid_scan_sessions` | `rfid_pipe.rfid_scan_sessions` |
| `rfid_scan_records` | `rfid_pipe.rfid_scan_records` |
| `ignored_rfid_tags` | `rfid_pipe.ignored_rfid_tags` |
| `rfid_audit_log` | `rfid_pipe.rfid_audit_log` |

Read the full file first. Every SQL query string — including INSERT, SELECT, UPDATE, DELETE — must be updated. The table names appear in:
- audit_log_event() function
- list_templates, create_template, get_template, update_template, archive_template, delete_template
- list_sessions, sync_session, bulk_update_status, get_session, update_session_status, delete_session
- list_records, export_records_csv, ignore_records, delete_records
- sum_by_view (queries both rfid_scan_sessions and rfid_batch_templates and rfid_scan_records)
- list_ignored_tags, unignore_tag
- get_audit_log

**File: `platform/backend/app/seeds/rfid_seed.py`**

Read this file. Update all bare table references to use `rfid_pipe.` prefix same as above.

### Verify correctness
After editing, scan the two files for any remaining bare table references (rfid_batch_templates, rfid_scan_sessions, rfid_scan_records, ignored_rfid_tags, rfid_audit_log) that don't have the `rfid_pipe.` prefix. There should be none in SQL strings.

### Deploy
```bash
cd platform/backend
railway up --service 6cad7f74-9329-406e-b733-719a33c53ac3
```
Check deployment: `railway deployment list --service 6cad7f74-9329-406e-b733-719a33c53ac3`
If FAILED, check logs: `railway logs <deployment_id>`

### Commit
```
git add platform/backend/app/routers/rfid_pipe.py platform/backend/app/seeds/rfid_seed.py
git commit -m "feat: Phase 1 — update RFID backend queries to rfid_pipe schema prefix"
git push origin master
```

Do not run the code review pipeline — push directly to master.
