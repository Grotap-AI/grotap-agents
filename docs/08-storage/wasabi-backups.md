---
title: "Wasabi _ Neon _ PageIndex _ Gitbucket _ Backups"
source: google-drive-docx
converted: 2026-03-01
component: "Wasabi"
category: storage
doc_type: how-to
related:
  - "Neon"
  - "PageIndex"
  - "GitHub"
tags:
  - wasabi
  - b2
  - backup
  - neon
  - pageindex
  - github
  - cold-storage
status: active
---


# Wasabi _ Neon _ PageIndex _ Gitbucket _ Backups

Wasabi | Neon | PageIndex | Gitbucket | Backups

To set up Wasabi to receive backups from Neon and PageIndex, you must first configure your B2 environment and then use compatible integration tools, as neither platform has a one-click native "Backup to B2" button.
1. Prepare Wasabi
Before connecting your services, you need the following credentials from your Wasabi Web Console :
- Enable B2: In "My Settings," ensure "B2 Cloud Storage" is checked.
- Create a Bucket: Navigate to "Buckets" and create a private bucket for your backups.
- Generate Application Key: Go to "Application Keys" and create a new key. Copy the Key ID and Application Key immediately, as they will not be shown again.
   Find Endpoint: Note your S3 Endpoint (e.g., s3.us-west-004.wasabib2.com) from the Bucket details.

   Discourse

2. Connect Neon (Postgres Database)
Since Neon is a managed Postgres service, you can back it up to B2 using S3-compatible tools or automated backup managers:
- SimpleBackups (Recommended):
     Sign in to SimpleBackups .
     Add your Wasabi as a "Storage" provider using your Key ID, Application Key, and Endpoint.
     Create a "Backup Job," select Postgres as the type, and provide your Neon connection string.
- Custom Script (pg_dump + rclone):
     Use pg_dump to export your Neon database.
      Use rclone  or the B2 CLI  to sync the resulting file to your B2 bucket.

3. Connect PageIndex (Application/Files)
PageIndex typically refers to a file-based indexing or web application. You can back up its data (files/database) using:
- S3-Compatible Integration: If PageIndex supports S3 destinations, enter your B2 Key ID as the Access Key, Application Key as the Secret Key, and your B2 Endpoint URL.
- Agent-Based Backups:
     Restic/rclone: Install these on the server hosting PageIndex to automate folder syncing to B2.
      BackupAssist: If running on Windows, use BackupAssist to select PageIndex files and target "S3 compatible cloud storage" (B2).

## Summary Checklist for Setup
Requirement
Value from Wasabi
Storage Type
S3 Compatible
Endpoint / Service URL
Found in Bucket details (e.g., s3.us-east-005.wasabib2.com)
Access Key ID
Your generated Key ID
Secret Access Key
Your generated Application Key
Bucket Name
The name of your private B2 bucket

---

## Agent Instructions

- **Use this when:** Setting up cold storage backups for Neon, PageIndex, and GitHub
- **Before this:** Neon and PageIndex operational with data
- **After this:** Automate backup schedule via INNGEST jobs
