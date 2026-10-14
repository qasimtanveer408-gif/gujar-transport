# Archive/delete release verification — 14 October 2026

## Results

- TypeScript checks: passed for client and server.
- ESLint: passed.
- Automated regression suite: **83 tests passed, 0 failed**.
- Production client/server build: passed.
- All **17 migrations** executed in isolated PostgreSQL (PGlite).
- The single-file fresh installer executed successfully, recorded all migration versions, and rejected a second installation without removing existing tables.
- The new forward migration was applied to a populated previous-version test database; existing records remained intact.
- CLI launcher resolved the project-pinned CLI and returned version **2.119.0**. An unlinked migration attempt stopped with the correct setup instruction.
- Browser validation used the actual compiled React UI, Express routes and PostgreSQL business functions at **1440 × 1000** and **390 × 844**.

## Business behavior checked

- Permanent deletion is rejected until the record is archived.
- Restore preserves original vehicle status and makes the record visible again.
- Active registers exclude archived rows and the archive manager retrieves them.
- Archived forms reject edits/new references through database checks.
- Viewers cannot preview or perform lifecycle actions; HTTP requests still require permissions, Origin and CSRF checks.
- The reviewed token is invalidated when a linked payment is added after the preview.
- A posted vehicle's purge removes its trips, fares, expense lines, histories, revenue, related earnings, entire affected payments, allocations and attachments.
- Unrelated vehicle and driver masters survive. Surviving salary earnings become unpaid again when their combined payment is removed.
- Vehicle odometers are recalculated after deletion.
- Closed periods affected by deletion reopen and obsolete close snapshots are cleared.
- Accounting periods archive/restore/delete; a deleted period's date range can be created again without overlap.
- Deleting a loan disbursement removes related repayments and cash rows.
- Maintenance, office expenses, bookings, routes, companies, custom field definitions/values, duties, assignments, import rows, notifications, custom roles and users physically delete.
- User deletion keeps business records, transfers their ownership to the acting administrator and queues removal of the sign-in account.
- A new foreign-key blocker causes the whole attempted deletion to roll back, preserving the original records and financial rows.
- Failed file cleanup remains queued; retry clears it. A previously deleted Auth account is handled as an idempotent success.

## Browser checks

The browser performed Archive → cancel permanent deletion → Restore → Archive → Delete permanently. Database queries confirmed that the vehicle and linked trip were gone while the unrelated driver survived. A second browser workflow permanently deleted the accounting period from its own register.

Existing edit forms and added card/table/dialog buttons were checked for intersecting button rectangles. Mobile layout had no page-wide overflow. No browser JavaScript errors occurred. Screenshots were visually inspected during development.

## Validation boundary

Testing used Node 24.19.0 and isolated PostgreSQL with test Auth/Storage schemas. Supabase sign-in and Storage/Auth provider responses were simulated. No hosted Supabase project, production data, live credentials or external account was changed. Windows launcher logic avoids shell/.cmd execution; it was not run on a Windows machine. Node 24–26 is accepted by package metadata; Node 26 was not executed in this environment.

## Commands

```sh
npm run typecheck
npm run lint
npm test
npm run build
npm run test:sql
node --import tsx scripts/lifecycle-e2e.ts
```

For browser tests install the matching Playwright Chromium build, or set `PLAYWRIGHT_EXECUTABLE_PATH` to a compatible local Chromium executable. Optional `LIFECYCLE_SCREENSHOTS` stores diagnostic screenshots outside the release.

## Official references used

- [Supabase database migrations](https://supabase.com/docs/guides/deployment/database-migrations)
- [Supabase CLI installation](https://supabase.com/docs/guides/local-development/cli/getting-started)
- [Delete Storage objects through the API](https://supabase.com/docs/guides/storage/management/delete-objects)
