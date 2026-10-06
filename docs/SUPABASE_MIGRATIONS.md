# Migrations and schema types

Apply supabase/migrations in filename order. These initial migrations were refined before any external installation. After your first installation, keep applied files immutable and append forward migrations.

Install the official Supabase CLI on PATH using its current OS-specific instructions. Confirm `supabase --version`. The cross-platform scripts invoke the CLI directly and never download an unpinned executable at runtime.

```sh
supabase login
supabase link --project-ref YOUR_CONFIRMED_REFERENCE
supabase db push --linked --dry-run
npm run db:migrate
npm run db:types
```

Remote scripts require interactive project-reference confirmation. Use a private secure prompt for database administration credentials, not a saved credential-bearing command. Web runtime credentials do not substitute for migration permissions.

For local disposable Supabase, start Docker then run `supabase start`, `npm run db:migrate -- --local`, `npm run db:types -- --local` and `npm run db:test -- --local`. Never run reset against live data. Compare migration history before attempting any repair.

`schema:snapshot` generates SQL row types and data dictionaries from actually applied migrations in isolated PostgreSQL. These are not claimed as hosted-generated Supabase client types. `db:types` writes shared/generated/database.types.ts from the selected real Supabase schema. Numeric Data API columns are generally numbers; application financial RPCs explicitly return decimal strings.
