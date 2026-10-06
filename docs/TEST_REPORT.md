# Test report — 2026-10-06

Target: isolated Linux execution workspace, Node 24.19.0 / npm 11.9.0, project v0.1.0. No real Supabase or Hostinger project was connected. No production data was changed. This report applies to the packaged restored checkpoint, not earlier workspace versions.

## Executed checks

| Exact command | Result | Scope |
|---|---|---|
| `npm ci` | PASS | Clean lockfile install, 351 packages; deprecation warnings recorded below |
| `npm run typecheck` | PASS | Client/shared and server TypeScript configurations |
| `npm run lint` | PASS | ESLint on client, server, shared, scripts, tests |
| `npm test` | PASS — 22 reported tests, 0 failures/skips | Includes one parent SQL test and 11 nested SQL cases; unit and mocked-service HTTP tests |
| `npm run build` | PASS | Vite client plus TypeScript server; emitted dist/client/index.html and dist/server/index.js |
| `npm run schema:snapshot` | PASS | Applied migrations to disposable PostgreSQL and introspected generated types/dictionary/RPC catalogue |
| `npm audit --omit=dev --json` | PASS — 0 reported vulnerabilities | Production dependency snapshot only; not a comprehensive security audit |
| `PLAYWRIGHT_EXECUTABLE_PATH=/workspace/scratch/771749f94614/verification/browser/chromium FONTCONFIG_PATH=/workspace/scratch/771749f94614/verification/browser/fonts npm run test:e2e` | PASS | Chromium 131 runtime fallback; compiled production UI with explicit browser HTTP fixtures |
| Local Python archive/source/bundle checks | PASS | ZIP integrity; required guide/link presence; no live env files or tested secret patterns; privileged variable names absent from built client |

Browser command paths above identify this execution environment, not user installation instructions. Normally run `npx playwright install chromium`, `npm run build`, then `npm run test:e2e`. The developer-only Chromium package supplies an alternative runtime here; production exports do not depend on a server browser. Users print reports through their own browser and may select Save as PDF.

## What passed

- Decimal calculations: fare 80,000 less 36,000 expenses gives 44,000 operating profit; 538 km / 68 L rounds to 7.91 km/L. Pooled ratios use matched distances/litres and a single measurement basis. Invalid odometers and zero/missing fuel handled.
- Karachi date helper changes business date at 19:00 UTC. This is not exhaustive SQL/DST/period boundary verification.
- AES-GCM credentials bound to session handle, tamper rejection; live-environment HTTPS guard; CSV parsing/escaping/formula defense; file-signature rejection.
- Mocked-Auth HTTP BFF: origin rejection, CSRF, HttpOnly/SameSite cookie, restricted route denial, JSON API 404, logout/revoked cookie.
- Actual nine migrations applied to PGlite PostgreSQL with intentionally mocked Supabase Auth/Storage schemas. Idempotent bootstrap, RLS enablement, privileged grants, restricted identity/finance, immediate revoked-session denial, last owner protection and duty deduplication tested.
- Forced trip posting failure rolled back state and revenue. Duplicate approval produced one posting. Exact SQL profit/fuel results validated. Maintenance posts once, brokerage recognizes commission only, loan repayment and accrued salary settlement do not duplicate operating expenses.
- Period closure blocks posting; reopening retains the original close snapshot. Import duplicate failure is atomic and retry is idempotent; alert reconciliation deduplicates.
- HTTP CSV/XLSX generator with mock report database: readable Excel round trip, embedded supplied logo, preserved decimal strings, correct text escaping/formula defense.
- Browser fixtures: login/logout, empty dashboard, vehicle dialog, nested-route refresh, mobile navigation/import screen, no page errors and no horizontal overflow at 390px. Visually inspected login, dashboard and vehicle-dialog screenshots. These checks do not save a record through real Supabase.

Screenshots under screenshots are synthetic empty-state fixture captures, not real account or live data screenshots.

## Warnings and limits

`npm ci` emitted deprecation notices for some transitive dependencies (including ExcelJS archive dependencies) and the pinned ESLint release. The environment also adds an npm http-proxy configuration warning. Installation/build/tests succeeded. A zero production audit result does not assert all dependencies are maintained or vulnerability-free; reassess upgrades before production rollout.

PGlite uses actual SQL execution in an isolated process but does not emulate Supabase services completely. Tests substitute Auth/Storage schemas and verified claims; HTTP tests substitute service calls, and UI tests intercept API responses. No real direct PostgREST request, Auth password/token rotation, Storage transfer or hosted API request was verified. Sequential retry tests do not prove true parallel-connection race behavior.

## Not run / still required

- `npm run db:migrate`, project `db:types`, real-stack `db:test -- --local` (supplied pgTAP), real `seed:admin`/`reset:admin`, or configured production `npm start`: require a confirmed project/environment and private credentials. Environment checks intentionally reject missing configuration.
- Clean real Supabase migration installation, anonymous and authenticated direct REST/RPC/Storage access tests for every role and scope, user-context enforcement, actual disabled-user/provider session behavior, token-refresh races, cross-process sessions and Auth partial-provision recovery.
- Independent database connections racing approval/close/last-owner updates; large datasets above default REST page limits; all multi-join and allocation combinations; full timezone/period edge cases.
- Real private upload/download/delete, interrupted-upload recovery, orphan cleanup safety, account recovery delivery, cron installation/timezone/dedup/success history.
- Hostinger subscription/path selection, domain/SSL, production startup/restart, platform PORT, hosted/local-live shared data, authorized CRUD and persistence after deployment.
- Backup of database AND Storage bytes, restore into a separate project, identity mappings, financial reconciliation and login after restoration.
- Missing business workflows listed in PROJECT_STATE.md and REQUIREMENTS_TRACEABILITY.md. These require additional implementation, not just secrets or account configuration.

The archive scan detects specific secret formats and prohibited file classes; it cannot prove absence of every possible secret format. No live credentials were supplied. Test values are neutral, synthetic, and confined to test code.
