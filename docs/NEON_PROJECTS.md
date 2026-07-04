# Neon Project Inventory & Decommission Proposal (SCA004)

> Case: CASE-20260704-SCA004 — Neon account hygiene. Generated 2026-07-04.
> Org: info@grotap.com (`org-cool-hill-56739347`), 9 projects.
> HI hold for the deletion decision: `ea5cda58-944e-46a2-850b-314dea978d85` (control plane `human_holds`).
> **Nothing has been deleted — deletion is owner-gated.**

## Inventory

| Project ID | Name | Region | Purpose | Referenced by | Verdict | Keep / Delete-proposed |
|---|---|---|---|---|---|---|
| `green-rice-76766370` | Grotap Platform | us-west-2 | Control plane DB | Everything (DATABASE_URL, app backend) | REFERENCED | **KEEP** |
| `proud-union-74070434` | grotap-tenant-grotap | us-west-2 | GroTap tenant DB | `tenants.neon_project_id` (GroTap) | REFERENCED | **KEEP** |
| `cool-wave-48964273` | tenant-org_01KW8JP2P21CVVGHEP808T847C | us-east-1 | Manor View Farm tenant DB | `tenants.neon_project_id` (Manor View Farm) | REFERENCED | **KEEP** |
| `dry-scene-84148651` | rfid-pipe-knowledge | us-west-2 | App knowledge DB (canonical copy) | Doppler `RFID_PIPE_KNOWLEDGE_DB_URL` prd+dev (endpoint `ep-wild-pine-akam1cxh`) | REFERENCED (config only — no code reads the var yet) | **KEEP** |
| `wispy-sky-20074345` | grotap-platform-rules | us-east-2 | Platform rules DB (canonical copy) | Doppler `PLATFORM_RULES_DB_URL` prd+dev (endpoint `ep-lively-sound-aj36xban`); code: `ingestion-worker/src/functions/platformRulesQuery.ts`, `agent-worker/src/agents/nodes/platformRulesPrecheck.ts` | REFERENCED | **KEEP** |
| `falling-brook-32044564` | rfid-pipe-knowledge | us-east-1 | Duplicate (created 2026-03-08, flagged "created in error" in agents/tasks/951) | Nothing live — only stale doc comments (`ingestion-worker/migrations/knowledge/scantap/v001_schema.sql` header, BACKUP_INDEX.md D5) | UNREFERENCED | **DELETE-PROPOSED** |
| `little-art-07275447` | rfid-pipe-knowledge | us-west-2 | Duplicate (created 2026-03-07) | Nothing live — BACKUP_INDEX.md D6 only | UNREFERENCED | **DELETE-PROPOSED** |
| `plain-boat-59331029` | rfid-pipe-knowledge | us-east-2 | Duplicate (created 2026-03-07) | Nothing live — BACKUP_INDEX.md D8 only | UNREFERENCED | **DELETE-PROPOSED** |
| `jolly-term-00231771` | grotap-platform-rules | us-east-1 | Duplicate (created 2026-03-08); `platform_rules` 27 rows = subset of wispy-sky (34 + key_patterns + never_do) | Nothing live — BACKUP_INDEX.md D3 only | UNREFERENCED | **DELETE-PROPOSED** |

## Evidence method

1. **Repo grep** (`C:\1Claude` incl. platform, agents, docs, ingestion-worker, orchestrator) for all 6 suspect IDs and the names `rfid-pipe-knowledge` / `grotap-platform-rules`: hits only in docs (`BACKUP_INDEX.md`), historical task files (941/942/947/951), and one stale SQL header comment. No live code or config references any project **ID**.
2. **Control plane** (`green-rice-76766370`): `SELECT tenant_id, name, neon_project_id, knowledge_project_id FROM tenants` — `knowledge_project_id` is **NULL for both tenants**; no suspect is wired in.
3. **Doppler** (`grotap` prd and dev): only two relevant secrets. Endpoint hosts matched against each project's connection string:
   - `RFID_PIPE_KNOWLEDGE_DB_URL` → `ep-wild-pine-akam1cxh` → **dry-scene-84148651**
   - `PLATFORM_RULES_DB_URL` → `ep-lively-sound-aj36xban` → **wispy-sky-20074345**
   - The other four suspects' endpoints (`ep-silent-math-adepuj13`, `ep-soft-sunset-akrjneyi`, `ep-flat-morning-aj1tij7q`, `ep-jolly-lab-a4m4qyor`) match nothing in either config.
4. **Data inspection**: the four rfid-pipe-knowledge copies are near-identical seeds (`agent_prompts` 4–5, `app_rules` 12–20, `domain_knowledge` 0, ~31 MB each, `written_data_bytes` 0 since creation).

## Cost note

Direct spend is small (~31 MB storage and ~12 min lifetime compute each), but **all four delete-proposed projects are woken every day at 00:00 UTC by the agent-06 daily Neon backup job** (they are targets D3/D5/D6/D8 in `BACKUP_INDEX.md`) — that is the daily compute billing observed. Estimated saving is under $5/mo combined; the main win is account hygiene and four fewer pointless daily backups.

## Proposed action (owner-gated — HI hold `ea5cda58-944e-46a2-850b-314dea978d85`)

1. Owner approves the HI hold.
2. Delete these **4** Neon projects via console/API: `falling-brook-32044564`, `little-art-07275447`, `plain-boat-59331029`, `jolly-term-00231771`.
3. Remove them from the agent-06 backup targets and update `docs/BACKUP_INDEX.md` (rows D3, D5, D6, D8).
4. Optional follow-up: `RFID_PIPE_KNOWLEDGE_DB_URL` exists in Doppler but no code consumes it — decide whether dry-scene stays the future knowledge DB (per task 951 provisioning plan) or is retired too.
