# Gujjar Brother Transport — accounting-period deletion repair

This patch contains updated files only. Copy them into your existing project,
preserving the folder paths and replacing the matching files.

## What the screenshot establishes

The old application uses the same “data service is unavailable or its schema
needs updating” message for unknown database failures. That message does not
identify the actual database error. The empty-period case shown in the screenshot
passes against the supplied schema in an isolated PostgreSQL test database.
The live database error has not been reproduced or verified on your hosted project.

This update reinstalls the archive/delete database functions, refreshes API schema
metadata, and makes any remaining database error identifiable by its error code
and request reference. It does not claim that every failure is a missing migration.

## Apply to your existing Supabase database

1. Open the Supabase project whose URL matches `SUPABASE_URL` in your deployed
   application's environment settings.
2. Open **SQL Editor → New query**.
3. Open `supabase/setup/REPAIR_RECORD_DELETE.sql` from this patch in a text editor.
   Copy its entire contents into SQL Editor and click **Run**.
4. Wait for the result: **Archive/delete database repair applied...**

The repair runs in a transaction. It installs the original archive/delete feature
when missing, otherwise reinstalls its functions, and records both migration
versions so subsequent CLI migrations do not reinstall them. It is safe to rerun.
Applying this script does not delete business records. Actual deletion still
requires the application's permission checks, archive step, reviewed preview,
reason, and explicit DELETE confirmation.

Do not run `NEW_DATABASE_SETUP.sql` on this existing database. That file is updated
in this patch only so future empty database installations include the repair.

If the repair says the base app migrations are missing, use the CLI migration
workflow below. If it reports a lock timeout, retry the script once active
database updates have finished; the failed transaction does not partially apply.

## Deploy the updated application

Copy this patch into the folder containing your project's `package.json`.
No dependencies or environment variables change.

For your local application, from PowerShell in the project folder:

```powershell
npm run build
npm start
```

Stop an existing local server before starting its replacement. For development,
restart `npm run dev` instead.

For Render, commit and push these updated files to the GitHub repository linked
to the Render service, then wait for the new deployment to finish. If automatic
deployment is off, choose **Manual Deploy → Deploy latest commit** in Render.
The database repair is a separate step; a website redeployment does not execute SQL.

Refresh the website. Open the accounting period's Delete dialog again, review the
linked records, enter the reason and DELETE confirmation, and submit the deletion.
The period dates become reusable after the deletion succeeds.

## Alternative: use the project's CLI migration workflow

Use this instead of SQL Editor when your project is already managed through the
Supabase CLI. Run the following in the project folder:

```powershell
npm run db:status
npm run db:check
npm run db:migrate
```

The command asks you to confirm the linked project reference. If it is not linked,
run `npm run db:login` and then `npm run db:link -- --project-ref` followed by the
actual project reference shown in your Supabase dashboard. Review the target
before applying pending migrations. The project scripts explain missing linkage.

## If deletion still fails

The dialog now distinguishes these conditions and shows a reference that can be
matched to the server log:

| Displayed error | Next action |
| --- | --- |
| DATABASE_SCHEMA_OUTDATED | Apply the repair to the same Supabase project the app uses. If a code remains, send the code and reference for diagnosis. |
| DATABASE_TIMEOUT | Refresh the list to check the record's current state; reload the preview before retrying. |
| DATABASE_BUSY | Another transaction is using the records. Wait briefly and reload the preview. |
| LINKED_RECORDS | Review remaining dependencies; the transaction has not silently ignored a foreign-key constraint. |
| DATABASE_UNAVAILABLE | Check the database service and connection. Refresh records before retrying an operation with an uncertain response. |
| DATABASE_ERROR | Send the database code and request reference; the server log contains the safe code and operation name. |

The app never automatically retries a destructive deletion. On failure it discards
the old preview and confirmation. A new preview and explicit confirmation are
required before another attempt. If the record is no longer found after a lost
response, close the dialog and refresh the list to check whether it was deleted.

Provider SQL, row contents, credentials, and raw provider messages are not added
to logs by this patch. Safe database codes and request references are retained.

## Validation

- 89 automated tests passed using isolated PostgreSQL and mocked external services.
- Empty accounting-period deletion removes exactly the reviewed row and preserves
  other periods, vehicles, drivers, and transactions.
- Missing delete RPC repaired; repeated repair preserves existing rows and archive state.
- Older application without the lifecycle migration upgraded without losing data.
- Permission checks, CSRF, archive-first behavior, stale-preview protection,
  transaction rollback, and linked-record deletion remain covered.
- TypeScript checks, ESLint, and production build passed.
- Browser regression passed on desktop and mobile: archive/cancel/restore/delete,
  missing-schema preview recovery, timeout recovery, fresh confirmation, and no
  JavaScript errors. The browser used the compiled app and isolated PostgreSQL.
- Hosted Supabase/Render verification must happen after you apply this patch.

Run the checks locally with:

```powershell
npm run typecheck
npm run lint
node --import tsx --test --test-concurrency=2 tests/*.test.ts
npm run build
```

The browser regression script is `scripts/lifecycle-e2e.ts`. After installing a
Playwright browser, run `node --import tsx scripts/lifecycle-e2e.ts` against the
compiled local app; it creates its own isolated database and server.

## Official references

- [PostgREST error codes](https://docs.postgrest.org/en/v16/references/errors.html)
- [PostgREST schema cache reloading](https://docs.postgrest.org/en/v16/references/schema_cache.html)

The patch preserves your earlier Render fixes and does not include an `.env` file.
