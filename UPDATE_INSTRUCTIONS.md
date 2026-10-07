# Gujjar Brother Transport — forms and reports patch

Start with a backup. This is a patch of the supplied application, not a new scaffold. Authentication and admin provisioning code are unchanged. No live Supabase service, real credential, account, migration or deployment was used in producing this package.

## What to replace

Use the complete patched source folder as a new release. Keep your private `.env` separately and copy it into the new release yourself. Do not overwrite your only working copy. The ZIP intentionally excludes `.env`, linked-project cache, node_modules, build output, private records and original photographs. `CHANGED_FILES.md` lists the exact differences against the supplied ZIP.

Two new migrations are required, in this order, after the existing migration history:

1. `20261006135132_exact_forms.sql` — additive year/work fields, maintenance component records, atomic form functions, register/export functions, explicit completion action and unposted-maintenance approval guard.
2. `20261006140546_reference_reports.sql` — caller-scoped snapshot for the five reference templates.

Existing migrations were not rewritten. The schema additions were tested by applying all eleven migrations to isolated PostgreSQL. Hosted Supabase validation is still required in your staging project.

## Windows update commands

Stop the running server with Ctrl+C. Extract this patched folder beside the old one, then open PowerShell in the new folder containing `package.json`.

```powershell
node --version
npm.cmd ci
npm.cmd run typecheck
npm.cmd run lint
npm.cmd test
npm.cmd run build
```

Use Node 24.x, matching the existing `engines` requirement. Copy your existing private `.env` into this new project root. Keep the already working administrator settings; this patch does not reset or synchronize a password, change the bootstrap rules, or require reseeding an existing admin.

Before changing a database, take a provider-supported backup/export and confirm you are targeting a disposable/staging project first. The following commands contact the project you choose; they were **not run** against your account here:

```powershell
npx.cmd supabase login
npx.cmd supabase link --project-ref YOUR_CONFIRMED_PROJECT_REFERENCE
npx.cmd supabase migration list --linked
npx.cmd supabase db push --linked --dry-run
```

Review the target and the migration list. If your project already has the original nine migrations, only the two new migrations should be pending. Investigate any different history; do not use reset or migration-repair to force a match. After approving the reviewed target and pending SQL yourself:

```powershell
npx.cmd supabase db push --linked
npm.cmd run dev
```

Open `http://127.0.0.1:5173/` and sign in with your existing admin. The API should listen on port 5000. Use **Reports & exports → Output** to choose either a full-field register or a reference-format sheet. Select dates (or a listed accounting period), then Preview / Excel / Download PDF. The oil report has a vehicle filter; combined and supplementary driver sheets require both vehicle and driver.

The CLI commands use `npx.cmd` explicitly on Windows. The existing `scripts/database.mjs` wrapper is preserved; it expects a native Supabase executable on PATH and may not resolve an npm `.cmd` shim with `shell:false` on Windows. The commands above avoid that wrapper issue without weakening its target checks.

## Browser and isolated report verification

These create synthetic TEST records only in in-memory PostgreSQL, not in Supabase:

```powershell
npx.cmd playwright install chromium
npm.cmd run build
npm.cmd run test:e2e
npm.cmd run report:samples
npm.cmd run schema:snapshot
```

`test:e2e` includes fixture login/logout/navigation checks and real form HTTP handlers backed by isolated PostgreSQL. Supabase Auth/Storage are mocked. The generated schema snapshot is not a replacement for types generated from your confirmed hosted schema. Browser executable overrides are available through `PLAYWRIGHT_EXECUTABLE_PATH` if needed.

## Hostinger update

Keep the existing Node/Express deployment method. Do not upload only the Vite frontend. In a new release directory, install with `npm ci`, run `npm run build`, and use `npm start` (entry `dist/server/index.js`) from the project root. Retain `dist/client`, including brand and font assets, plus runtime dependencies. PDFKit is a runtime dependency; no Chromium, native PDF service, or LibreOffice is needed in production.

Keep existing protected environment values and actual HTTPS origins in the hosting configuration. No new secret is required. Apply the reviewed migrations from your trusted machine after staging verification, then deploy/restart the application. On the existing VPS/systemd setup, switch the release symlink and restart the existing `gbt` service. On managed hosting, use your current build/redeploy/restart controls. Exact account controls and plan support were not verified here; see the retained Hostinger setup documents for your selected deployment model.

After restart, check health, login, one reversible record save/reopen, a restricted user, full-field CSV/XLSX, a reference PDF, nested-page refresh, and a server restart. Verify the logo and font assets load from the built release. Check accounting period labels and actual dates, including any configured 21st-to-20th period. This patch does not change the accounting calendar.

## Rollback

Keep the old code release and your separate protected environment backup. For an application rollback, stop writes, switch to the previous compatible code and restart. Prefer retaining the additive schema and its new data until a forward fix is ready; old UI screens will not expose new component notes. Do not drop new fields/tables, delete expense lines, reverse posted entries, or restore the database over newer transactions merely to roll back UI code.

Any database restore requires a separately approved recovery point and reconciliation of later financial activity. No destructive down migration is provided.

## Included evidence and open decisions

- `FIELD_CONTRACT.md`: every literal form label, field source, permission and export position.
- `REPORT_DATA_MAPPING.md`: every printed column/section and missing source.
- `docs/forms-reports/REFERENCE_IMAGE_MAPPING.md`: all eight image references.
- `docs/forms-reports/TEST_RESULTS.md`: executed checks and limitations.
- `verification/screenshots`: before/after forms, registers, mobile and preview evidence.
- `verification/report-samples`: genuine PDF/XLSX samples and full-field CSV/XLSX, all clearly marked TEST DATA ONLY.
- `verification/rendered`: PDF raster pages and renderings of saved workbook cell models.

Confirm the meaning of company, fines/permit scope, ambiguous monthly headings and settlement/share sources before treating affected reports as finalized. Incomplete markers are intentional safeguards against invented financial totals.
