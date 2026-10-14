# Local Supabase tests

Requires Docker and the official Supabase CLI. The real Docker stack was not run in this workspace.

```sh
supabase start
supabase status
npm run db:migrate -- --local
npm run db:types -- --local
npm run db:test -- --local
```

Copy the local API/key values privately into development .env. Local API is 54321, Studio 54323, PostgreSQL 54322. Config disables signup and automatic seed data. Provision the test administrator explicitly. supabase db reset --local destroys local records; use only for intentionally disposable data. Do not run a remote reset.

Supplied pgTAP tests check real-stack grants and private-session denial. npm test separately uses isolated PostgreSQL with mock Auth/Storage schemas and actual application SQL; it covers accounting transactions and RLS logic but not real provider behavior.

Pending real-stack acceptance: direct anonymous denial; restricted users/direct RPCs; expired/revoked sessions; upload/download policies; two-connection concurrent approval and close race; process restart persistence; generated matching types. Save sanitized outcomes without credentials or private record content.
