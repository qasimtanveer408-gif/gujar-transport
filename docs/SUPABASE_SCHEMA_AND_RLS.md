# Schema and RLS

See generated/DATA_DICTIONARY.md for every column, generated/RPC_CATALOGUE.md for RPC signatures, and generated/schema.json for policies and seeded grants.

Auth users link to app_users by stable UUID. user_roles joins role_permissions. Fleet companies own vehicles; driver assignments and duty sessions have one-open-row constraints. driver_identity_details and vehicle/trip financial tables isolate sensitive fields. Trips, maintenance items, office expenses and bookings are typed ledger sources. Revenue/expense entries have unique source indexes and reversal links. Loans and payment allocations maintain principal and accrued-earning balances. Period close snapshots preserve history. Attachments identify exactly one source and private path. Notifications/imports have their own row policies.

Every exposed business table has RLS and intentional SELECT grants. Ordinary users cannot directly mutate business tables. Security-definer actions use fixed empty search paths, qualified names and current authorization checks. Reporting uses invoker context. private.active_session requires an active profile and current, unrevoked, unexpired application session matching the verified Auth session claim.

Anonymous business reads/writes are denied. Private sessions, encrypted token material and privileged RPCs are unavailable to ordinary users. A database owner/service role remains privileged: RLS does not protect against trusted-owner misuse. Keep keys and owner access restricted. Audit records are append-only for app users, not tamper-proof against a database owner.
