# Requirements traceability — 2026-10-06 checkpoint

The controlling source is MASTER_REQUIREMENTS.txt. Implemented means source exists; locally tested means the named isolated test passed. Neither means a real Supabase project or hosted deployment was verified. Partial rows are implementation work, not merely missing credentials. Test evidence and service boundaries are in TEST_REPORT.md.

| Brief | Screen / implementation | SQL / API | Evidence and remaining work |
|---|---|---|---|
| 1, 24 — phased implementation | README; PROJECT_STATE | Cumulative source, one architecture | Runnable checkpoint; full system incomplete; next task explicitly recorded |
| 2 — identity | Login, sidebar, Settings, print/export branding | business_settings | Supplied raster logo preserved; CSV is text-only; XLSX embeds logo; no invented business identifiers |
| 3 — template | React shell, responsive tables/dialogs; template styles/icons | client/public/vendor; TEMPLATE_INTEGRATION | Browser fixtures at desktop/mobile; broad keyboard and all-role accessibility acceptance pending |
| 4 — architecture | React/Vite, Express BFF, request-scoped caller client | server/supabase.ts; server/session.ts | Supabase owns durable runtime state; PGlite is disposable tests only; real Data API context verification pending |
| 5 — authentication | Login/logout, user provisioning; seed/reset CLI | identity migration; session RPCs; /auth/* | Encryption/CSRF/mock HTTP and SQL bootstrap tests pass; real Auth provisioning recovery, token rotation and cross-process refresh unverified; ordinary-user recovery UI pending |
| 6 — roles and scope | Users, roles matrix, scopes, restricted fields | roles/grants, RLS, live session/permission helpers | Viewer direct SQL/financial suppression, privileged function grants, last owner and revocation tested; comprehensive cross-scope/concurrency and direct REST acceptance pending |
| 7 — vehicles | Vehicles, assignments, detail documents | save_vehicle, assign_vehicle_driver; /records/vehicles | Core operational entry/history; purchase price editor and consolidated vehicle audit/financial detail remain partial |
| 7 — drivers and duty | Drivers, restricted identity, duty, statements | driver identity table, duty sessions, driver_statement | One open duty session counted once; identity view without edit permission has no save action; full driver performance statistics/leave UI pending |
| 8 — trips | Trip editor, operational and financial states, expenses, actions | save_trip, trip_action, trip finance | Submission/approval/void, version checks, canonical postings implemented; approved adjustment workflow and complete multi-user transition coverage pending |
| 9 — calculations | Decimal previews and SQL dashboard | NUMERIC posting functions, source constraints, lock order | Required 44,000 profit / 7.91 km/L, pooled fuel, missing fuel, forced approval rollback tested; odometer reset, cash allocations and broader reconciliation pending |
| 10 — maintenance/oil | Maintenance lines, oil details, approval/documents | maintenance/oil tables, approve_maintenance | One posting per source tested; tyre serial/warranty controls, correction and full service-due calculations/reports pending |
| 11 — loans | Issue/repay, statement, balances | loan_transaction; /loans/:id/repay | Excess repayment and no operating expense duplication tested; payroll recovery, credit workflow and reversals pending |
| 11 — earnings/payment | Accrual, driver payments and allocations | accrue_earning, settle_driver_payment | Settlement does not duplicate expense; salary schedule, advances/deductions, percentage rule snapshot and full payment voucher pending |
| 12 — office | Office expenses and bookings | approve_office_expense, approve_booking | External booking recognizes commission only; owned-trip duplication prevented in source; correction and full payment-method workflow pending |
| 13 — accounting periods | Period creation/confirmation, close/reopen | accounting_periods, period_close_snapshots; monthly_accounts | Closed-posting refusal and retained snapshot tested; category-complete monthly accounts, year comparison and opening/closing reconciliation pending |
| 14 — dashboard | Today cards; date-filtered graphs/rankings; refresh/errors | dashboard SQL aggregation | Numeric SQL results and Karachi boundary helper tested; all component breakdowns, quality/class/load controls and very large multi-join acceptance pending |
| 15 — alerts | Alerts/read state/rules/source links | alerts_imports migration; reconcile_alerts, optional cron | Expiry, approval and low-efficiency reconciliation/dedup implemented; latest 100 display. Service/missing-data/expense/loan reminders and real scheduled-run verification pending |
| 16 — private files | Upload/list/download/delete per record | reserve/finalize/delete attachment RPCs; storage.objects policies | Signature rejection and unauthorized reservation tested; real Storage transfer, retries/orphan races and safe scheduled cleanup unverified/incomplete |
| 17 — schema/API | Generated dictionary, RPC catalogue, schema types; API docs | Nine ordered migrations; authenticated context, strict resources | Migrations applied to isolated PostgreSQL with mock Supabase schemas; real-stack pgTAP and CLI-generated project types pending |
| 18 — environments | Three guarded profiles; separate cookie namespaces | config.ts; .env.example | Live HTTP rejected and keys server-only by design; two installations sharing a real project unverified |
| 19 — local setup | Windows, optional local Supabase and local-live guides | scripts for env/admin/CLI/build/tests | Clean npm ci, compile, tests locally verified; Docker/CLI/cloud commands documented but not executed here |
| 20 — hosting | Managed and VPS guides; nginx/systemd samples | production Express entry dist/server/index.js | Actual build output verified; account eligibility, deployment, SSL/domain and restart persistence pending user execution |
| 21 — exports | Reports, CSV/XLSX, browser print / Save as PDF | export_records, monthly_accounts; /reports | Real CSV/XLSX HTTP generation with mock DB and logo round trip tested; dedicated fuel/oil reports, complete filters/category reports pending; print-to-PDF is browser facility |
| 21 — imports | Vehicle/driver CSV template, preview, history, commit | prepare_import / commit_import | Parsing, row errors, atomic duplicate failure/retry tested; existing database duplicates checked at commit (not preview). Historical financial/photo imports and opening balance import pending |
| 22 — verification | tests; scripts/e2e; test report | isolated SQL plus supplied pgTAP | Local tests are not external integration; true parallel transactions, large datasets, real service/file/session recovery and restoration unverified |
| 23 — handover/recovery | Required guides, cumulative source ZIP | Deployment and backup runbooks | No secrets or private business data included. Database and object backup separated; restore rehearsal and actual plan retention not verified |

## File and test map

- Identity/session/RLS: `server/app.ts`, `server/session.ts`, `server/crypto.ts`, identity/throttle migrations; `tests/api.test.ts`, `tests/core.test.ts`, `tests/security-ledger.test.ts`.
- Operations/finance: `shared/modules.ts`, `server/domain.ts`, `client/src/ResourcePage.tsx`, fleet/accounts/finance_actions migrations; `tests/security-ledger.test.ts`.
- Dashboard/reports: reporting/exports migrations, `server/reports.ts`, dashboard/report screens; core/SQL/reports tests.
- Documents: `server/documents.ts`, documents migration; core signature and SQL permission tests, with external Storage testing pending.
- Alerts/imports: `server/operations.ts`, `client/src/OperationsPages.tsx`, `shared/csv-import.ts`, alerts_imports migration; core parser and SQL atomic import/dedup tests.
- UI fixtures: `scripts/e2e.mjs`; no production mock-login path. Screenshots under docs/screenshots use synthetic empty test responses.
- Database inventory: `docs/generated/DATA_DICTIONARY.md`, `RPC_CATALOGUE.md`, `schema.json`; `shared/generated/schema.ts`. Types were introspected from the applied isolated schema; regenerate linked-project types after actual migration rollout.

Tables that support future workflows do not imply a finished UI or financial action. Consult PROJECT_STATE.md before planning live adoption.
