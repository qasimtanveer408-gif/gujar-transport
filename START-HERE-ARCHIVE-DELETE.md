# Gujjar Brother Transport — archive, restore and permanent delete update

This package is the complete updated application. Open the `Gujjar-Transport` folder containing `package.json`.

Archive and Delete buttons now appear on the business record screens. The **Records & archives** page also covers 22 record types, including accounting periods, vehicles, drivers, trips, repairs, bookings, expenses, loans, payments, companies, routes, custom fields, documents, assignments, duty sessions, imports, notifications, users and roles.

**Archive keeps the values. Delete permanently removes the record and the linked database rows listed in the confirmation.** You can click Delete on an active record; the dialog first requires Archive and continue. You can stop after archive or restore the record later.

## 1. Install the app

Extract into a new folder so that an old `node_modules` folder or linked database reference is not reused. Open PowerShell in the folder containing `package.json`:

```powershell
node -v
npm.cmd ci
Copy-Item .env.example .env
```

Node 24 through 26 is accepted. This release was tested with Node 24.19.0. Dependencies are installed for your own operating system; a copied `node_modules` folder is not included.

## 2. Set up your NEW Supabase database

Create your new Supabase project and wait until it is ready. Choose **one** installation method.

**Method A — one SQL file, simplest for a new project**

1. Open the new project's **SQL Editor**.
2. Open `supabase/setup/NEW_DATABASE_SETUP.sql` from this package in your editor.
3. Copy the entire file into one new SQL query and run it as the database administrator.
4. The file installs all 17 migrations, records their versions and refreshes the API schema. It contains no sample transport data and does not create a login password.
5. Do not run the individual migration files again. Re-running this installer against an installed app deliberately stops with an “already contains the app” message.

The installer is transactional. An error rolls back the installation; inspect the first error before retrying. It is for a **new empty Supabase project**, not a generic PostgreSQL database without Supabase Auth and Storage.

**Method B — migration commands**

The CLI is pinned in this project. A global Supabase installation is unnecessary:

```powershell
npm.cmd run db:login
npm.cmd run db:link -- --project-ref YOUR_NEW_PROJECT_REFERENCE
npm.cmd run db:check
npm.cmd run db:migrate
npm.cmd run db:status
```

Use your new project's reference. The migration command asks you to type that reference before applying changes. The launcher executes the installed CLI through Node and works with Windows paths containing spaces.

If you used Method A, you can link the project later and use the CLI for future updates; its migration history is already recorded.

## 3. Connect the app to the new project

Edit the local `.env` file. Set:

```dotenv
APP_ENV=development
NODE_ENV=development
PORT=5000
APP_URL=http://localhost:5173
ALLOWED_ORIGINS=http://localhost:5173
SUPABASE_URL=https://YOUR_NEW_PROJECT_REFERENCE.supabase.co
SUPABASE_PUBLISHABLE_KEY=YOUR_NEW_PROJECT_PUBLISHABLE_KEY
SUPABASE_SECRET_KEY=YOUR_NEW_PROJECT_SECRET_KEY
ALLOW_LIVE_DATABASE_ACCESS=false
```

Use the URL and both keys from the **new** project. A legacy anon key can be used for the publishable-key setting and a legacy service_role key for the secret-key setting. Keep the secret key in the server environment.

Generate a session encryption key:

```powershell
npm.cmd run secrets:generate
```

This writes `.session-encryption-key` without printing the key. Open that file privately, copy its contents into `SESSION_ENCRYPTION_KEY` in `.env`, and remove the temporary key file after keeping your own secure copy.

## 4. Create your administrator

Temporarily set these values in `.env`:

```dotenv
ADMIN_BOOTSTRAP_ENABLED=true
ADMIN_EMAIL=YOUR_ADMIN_EMAIL
ADMIN_PASSWORD=YOUR_UNIQUE_PASSWORD_AT_LEAST_14_CHARACTERS
```

Then run:

```powershell
npm.cmd run check:env
npm.cmd run seed:admin
```

Confirm the displayed project and email in the terminal. After success, clear `ADMIN_PASSWORD` and change `ADMIN_BOOTSTRAP_ENABLED=false`.

Start the app:

```powershell
npm.cmd run dev
```

Open **http://localhost:5173** and sign in with the administrator you just created. No old database credentials or default password are bundled.

## 5. First records and deletion

1. In **Business settings**, confirm the accounting-period convention and save.
2. In **Accounting periods**, create the date range for your entries. Overlapping periods are still rejected.
3. Add vehicles, drivers and their assignments, then enter trips and other transactions as before.
4. Use **Archive** to hide a record from its normal active list. Archive keeps existing financial history and does not reverse posted values.
5. Use **Include archived** on the supported registers or open **Records & archives**, choose the record type, then choose **Archived**.
6. Use **Restore** to bring it back, or **Delete** to review exactly which linked database rows will be removed. Enter a reason, check the acknowledgment and type `DELETE`.

Deletion controls are enabled for Super Admin by default. Other roles keep their existing rights; an administrator can explicitly grant `records.archive` and/or `records.delete` with **All** scope in Roles & permissions.

### Accounting periods

Archive makes a period unavailable for new postings but keeps its dates reserved. To reuse its dates, permanently delete it. Period deletion removes transactions dated in the period and their complete linked documents, allocations and close snapshots. The preview warns if linked transactions extend into another period. Other affected closed periods reopen, and their old close snapshots are cleared so they can be reviewed and closed again.

### Linked records

Deleting a vehicle can remove its trips, repairs, attributed expenses, assignments, attachments and related accounting entries. It does not delete the driver master. Deleting a driver can remove that driver's linked records, but does not delete vehicle masters. Deleting a company unlinks its vehicles and keeps the vehicles. An affected combined payment is removed as a whole, which makes its surviving earnings unpaid again. Deleting a loan opening/disbursement includes its related repayments to avoid leaving an invalid balance.

A minimal action log records who performed the deletion and the reason; deleted record values are not copied to a hidden archive table. The built-in Super Admin role and your currently signed-in account remain protected. Sign in with a different administrator to delete an account. Business settings, standard categories and print-template definitions remain application configuration.

Documents and sign-in accounts are removed through Supabase's APIs after the business deletion commits. If a provider is temporarily unavailable, the app shows cleanup pending and retries every minute while the server is running. **Records & archives → Retry cleanup** retries it immediately.

Generated notifications can reappear after a later alert refresh if their source condition still applies. Archive a reminder to hide it persistently, or resolve its source condition.

## Updating an existing database instead

Do not run `NEW_DATABASE_SETUP.sql` against an existing app. Preserve your existing `.env`, install this source, link the existing project, run `db:check` and then `db:migrate`. Only `20261014120000_record_lifecycle.sql` is new; the earlier migration files are unchanged. Sign out and sign in again after the update to refresh your permissions. Existing data remains until you explicitly delete records.

## Build and deployment

```powershell
npm.cmd run typecheck
npm.cmd run lint
npm.cmd test
npm.cmd run build
```

For your existing hosting method, follow the corresponding Hostinger guide in `docs/`, deploy the updated source/build, and configure that server with the new database credentials. For a production server, use its HTTPS origin in both `APP_URL` and `ALLOWED_ORIGINS`, `APP_ENV=production`, `NODE_ENV=production`, and `ALLOW_LIVE_DATABASE_ACCESS=true`. Start with `npm start`. Never put server secrets into the client build.

See `docs/ARCHIVE_DELETE_VERIFICATION.md` for the checks performed and the scope of validation.
