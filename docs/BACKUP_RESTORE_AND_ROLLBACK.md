# Backup and recovery

No real restore rehearsal was performed. Confirm the selected Supabase plan's current retention, point-in-time recovery and recovery limits; none are assumed.

Back up PostgreSQL business/schema/RLS/functions/grants, migration history, Auth identity UUID mappings, Storage metadata **and separate object bytes**, scheduler definitions, and protected configuration. A database backup does not include uploaded file bytes. Preserve an object bucket/path/checksum manifest. Auth recovery must preserve UUIDs linked by business foreign keys; do not simply recreate users with new IDs.

Choose an independently protected encrypted recovery destination outside the live project. No destination was selected or uploaded to silently. Keep secrets/encryption keys in a separate protected secret store, never source/public archives. Record backup time, source release and reconciliation counts without private data.

Rehearse into an isolated project using the supported Supabase restore procedure. Verify Auth UUID links, permissions, private documents/checksums and period/loan/payment totals. Disable copied schedules until intended; revoke restored sessions and configure target-specific keys. Test login and restricted users, then record actual results and recovery time.

Lost/rotated session encryption keys invalidate encrypted login credentials, not business records. Revoke sessions and require login; coordinate replicas. Audit is not tamper-proof against database owners.

Code rollback selects a prior build compatible with current schema; it does not reverse live financial data. Prefer forward migrations and reviewed accounting reversals. A point-in-time database restore may lose newer transactions and requires a business-approved recovery window.

Source: [Supabase backups](https://supabase.com/docs/guides/platform/backups), checked 2026-10-05.
