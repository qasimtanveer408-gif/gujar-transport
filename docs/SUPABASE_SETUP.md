<<<<<<< HEAD
> For this release, use [START-HERE-ARCHIVE-DELETE.md](../START-HERE-ARCHIVE-DELETE.md) for the complete new-database setup.

=======
>>>>>>> 2aef45882bd9ec54781d025e3620f1f2677a5c83
# Supabase setup

Account-side execution is pending. Configure credentials privately, never in chat.

1. Create a disposable development Supabase project. Keep production separate and record the confirmed project reference privately.
2. In API settings copy the HTTPS project URL, publishable (or legacy anon) key and server secret (or legacy service_role) key into the server environment. Never expose the privileged key through VITE_ or client/public.
3. Disable public and anonymous signup in Authentication settings. Keep refresh rotation enabled. Configure the real application origin and exact allowed redirects. Email recovery requires appropriate SMTP and a recovery UI; that UI is not implemented in this checkpoint.
<<<<<<< HEAD
4. Use the single SQL installer, or run `npm run db:login`, `npm run db:link -- --project-ref YOUR_CONFIRMED_REFERENCE`, `npm run db:check`, then `npm run db:migrate`. Confirm the displayed reference.
=======
4. Install the official Supabase CLI. From this repository run `supabase login`, then `supabase link --project-ref YOUR_CONFIRMED_REFERENCE`. Review `supabase db push --linked --dry-run`. Run `npm run db:migrate` and confirm the displayed reference.
>>>>>>> 2aef45882bd9ec54781d025e3620f1f2677a5c83
5. Migrations create RLS, roles/functions and five private Storage buckets. Do not expose the private schema through the Data API. Run `npm run db:types` against the same project.
6. Generate an encryption key with `npm run secrets:generate`. Copy it privately into SESSION_ENCRYPTION_KEY, protect an encrypted recovery copy and delete the temporary file.
7. Temporarily set ADMIN_BOOTSTRAP_ENABLED=true, ADMIN_EMAIL and a unique ADMIN_PASSWORD of at least 14 characters. Run `npm run seed:admin` in an interactive terminal and confirm the target. Remove the password and set the flag false afterwards. Web startup rejects retained setup credentials.
8. Sign in, confirm Business settings and period-start convention, then create a period covering test transactions. No period or sample production dataset is automatically seeded.
9. Configure one alert schedule per intended project; test all real-service acceptance steps before production use.

Runtime uses HTTPS Data API/Auth/Storage, not a database-owner connection string. Check the project's status and applicable network restrictions if connectivity fails. Sources: [CLI](https://supabase.com/docs/guides/local-development/cli/getting-started), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [types](https://supabase.com/docs/guides/api/rest/generating-types).
