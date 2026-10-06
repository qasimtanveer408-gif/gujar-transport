# Cron and alerts

Implemented reminders cover vehicle document expiry, driver licence expiry, submitted-trip approval and low measured fuel efficiency. Thresholds can be edited by settings administrators. Service-due, unusual-expense, incomplete-trip and loan-instalment alerts remain pending.

Reconciliation marks old candidates resolved and upserts current ones by a unique key. Per-user read state is separate. Source-based RLS restricts reminders. API mutations request a separate reconciliation after commit; X-Alerts-Pending=true signals that business data saved but reminders await retry. Direct RPC changes appear on the next manual/scheduled run.

Enable pg_cron in the single intended Supabase project, then review/run supabase/optional/alerts-cron.sql in its SQL Editor. The named job runs 04:05 UTC / 09:05 Karachi. Verify exactly one active gbt-alert-reconciliation job. Local-live and hosted apps share it; neither starts an independent background timer.

Settings users can click Refresh alerts. Inspect job_runs and Supabase Cron run history for completion/failures. Repeating reconciliation is locally tested to avoid duplicate notifications. Actual Cron extension/schedule execution is unverified. Disable copied jobs during isolated restores until intended.

Source: [Supabase Cron](https://supabase.com/docs/guides/cron/quickstart), checked 2026-10-05.
