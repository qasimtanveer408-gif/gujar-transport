<<<<<<< HEAD
> **Latest release: archive / restore / permanent delete. Start with [START-HERE-ARCHIVE-DELETE.md](START-HERE-ARCHIVE-DELETE.md), including the new-database setup instructions.** The earlier release notes below remain as history.

=======
>>>>>>> d1a492683f98713288c02ce0dbffae1d235f6a40
# Current update

Use [MASTER-UPDATE-START-HERE.md](MASTER-UPDATE-START-HERE.md) for this release.

## Previous update notes (historical)

> Historical release notes. For this update use [UPGRADE-START-HERE.md](UPGRADE-START-HERE.md) and the current enhancement test report. Do not rerun already applied migrations.

# Update instructions — 2026-10-10

Use this complete release in a new folder beside your current installation. Preserve the old application and a database backup. Keep your existing private .env separately and copy it into the new folder; it is excluded from this ZIP. Your existing login accounts and company relationships are retained.

## Database update

The supplied ZIP contains eleven existing migrations through 20261006140546_reference_reports.sql. This release adds two migrations after that history:

1. 20261008195000_dashboard_form_fields.sql — operational form inputs, route/status/fuel fields, expiry data and dashboard calculation improvements.
2. 20261010103000_custom_fields_cards_print.sql — vehicle Address, persistent custom fields/values, bounded formulas, card filters, safe record archives, private driver-photo selection and print-template/signature settings.

Apply only migrations that are pending in your chosen project. Do not run database reset or drop existing tables. Keep original migration order. All thirteen migrations pass execution against an isolated PostgreSQL test database; hosted Supabase verification remains a staging step.

For a linked Supabase installation, use the existing project reference and review its history before pushing. These commands contact the project you select; they have not been run against your account here:

```powershell
npx.cmd supabase login
npx.cmd supabase link --project-ref YOUR_EXISTING_PROJECT_REFERENCE
npx.cmd supabase migration list --linked
npx.cmd supabase db push --linked --dry-run
```

Review the pending migrations and target. Then apply the reviewed migration set:

```powershell
npx.cmd supabase db push --linked
```

For a new empty project, follow docs/SUPABASE_SETUP.md and apply the complete ordered migration history. Existing installations do not need to reseed or reset their administrator. No new secret is required.

## Windows application update

Stop the old development server. Extract this ZIP and open PowerShell in the new Gujjar-Transport folder containing package.json. Use Node.js 24.x and run the commands individually:

```powershell
node --version
npm.cmd ci
npm.cmd run check:env
npm.cmd run typecheck
npm.cmd test
npm.cmd run dev
```

Open http://localhost:5173. Development uses Vite on 5173 and Express on 5000. Keep APP_URL and ALLOWED_ORIGINS consistent with the address you actually open. Windows users can use npm.cmd to avoid PowerShell npm.ps1 execution-policy issues.

## New workflows

Drivers, Vehicles, Trips and Maintenance open in cards view. Add a record, save it, then use View, Edit and Print on its card. Search, status, sort and table view use saved backend data. The most recently saved record is immediately shown even when its date would otherwise be outside the active period. Delete requires a reason and archives eligible records; assigned records, outstanding trips, posted transactions and closed periods are protected.

Fields & print settings is available to users with settings.manage. Add custom inputs or calculated fields, set defaults/required status/order, and choose forms/cards/tables/print visibility. Field keys and types remain stable once created. Archiving preserves values; dependent formulas must be changed before their source field is archived.

Formulas accept numeric field keys, + - * / %, parentheses, SUM, MIN, MAX, ABS and ROUND. They reject executable JavaScript, unknown or nonnumeric references and circular dependencies. Missing inputs and division by zero display readable errors. For example, add cf_quantity and cf_rate, then use cf_quantity * cf_rate as a calculated field.

Select a document under Print templates & signatures to change A4 orientation and up to six signature labels. Blank signature/name/date lines are provided for physical signing. Card Print and Print full register open a preview with Print / Save as PDF. Reports also provide genuine PDF, Excel and CSV exports.

To add a driver photo, open the driver details, upload an authorized JPEG/PNG under Private documents and choose Use as profile photo. Photos stay private and require driver-document permissions. Deleting the source document clears the photo; initials appear when no image is available.

## Deployment

Keep the existing Node/Express hosting method. Deploy the complete application rather than only the Vite frontend. Run npm ci, npm run build and npm start from the project root. The server entry is dist/server/index.js and it serves dist/client. Keep production environment values and HTTPS origins in your existing protected hosting configuration. Native Chromium is not required for runtime PDF generation.

After staging migration, check sign-in, a reversible save/reopen, a restricted user, card printing, custom-field save/reload, a formula edit, CSV/XLSX/PDF exports and server restart. Native browser responsiveness, actual Storage transfer and printing need validation in your environment. Live hosting has not been changed here.

## Data and rollback

Existing IDs, relationships and ledger entries are retained. Record Delete is an archive action, not a physical purge. The Fleet Companies navigation item is removed but its backing tables/foreign keys are preserved.

Retain the previous release for code rollback. The migrations are additive; preserve new custom values when switching code releases. Do not drop new tables or restore over newer transactions merely to revert the UI.

## Report limits

The five uploaded images guide report structure, headings, table order, component sections and signing areas. Some monthly share/allocation and driver-settlement cells have no confirmed source or business rule in the supplied application. They remain blank and explicitly marked incomplete. Available fare, category expenses, profit, distance, fuel, weight, commission and loan figures use authorized saved records. See REPORT_DATA_MAPPING.md for the exact boundaries.

The verification/report-samples files contain only isolated TEST DATA ONLY fixtures. They are examples for print review, not business statements.
