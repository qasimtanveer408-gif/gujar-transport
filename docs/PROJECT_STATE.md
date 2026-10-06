# Project state — runnable checkpoint

Version 0.1.0, 2026-10-06. Supabase-only architecture preserved. No real Supabase/Hostinger account connected and no production data changed. Local workspace returned to an earlier snapshot during continuation; setup/tests/alerts/imports were restored and rechecked. Test report refers only to this packaged source.

| Path | Purpose |
|---|---|
| client/src; client/public | React screens, supplied logo/template assets |
| server | BFF/session security and protected APIs |
| shared | Contracts, decimal calculations, generated schema catalogue |
| supabase/migrations | Ordered schema, RLS and SQL actions |
| supabase/optional; tests | Cron definition; real-stack pgTAP |
| scripts; tests | Setup/admin/build helpers and isolated verification |
| deploy; docs | Hostinger examples, guides, traceability/test evidence |

Phases 0–3 have core implemented workflows and local tests. Phase 4 is partial (maintenance, loans, accrual/payments, brokerage), Phase 5 partial (dashboard, alerts, reports, periods, operational imports), and Phase 6 has local tests/docs while external acceptance remains pending. This is not the complete requested system.

Remaining implementation: payroll-linked recovery, deductions/advances and loan/payment reversals; source-linked receivable/payable cash settlement entry; approved adjustments and odometer replacement; percentage commission rules; vehicle purchase-price editing; detailed driver statistics and tyre/warranty controls; maintenance/booking correction; full category/monthly reconciliation, dedicated fuel/oil reports and year comparison; historical financial imports; ordinary-user recovery UI; additional service/expense/loan alerts and safe automated orphan cleanup.

Exact next task: implement protected loan/payment reversal and payroll-linked recovery with typed source links, reason/audit, period lock and idempotency; add settlement UI/tests proving no duplicate operating expense. Then implement cash allocations, remaining reports/imports and real Supabase acceptance. Do not regenerate another stack on Continue. Once user migrations are installed, append new migration versions rather than editing applied files.

Checkpoint verification: clean npm ci, typecheck, lint, production build, 22 reported local tests, and fixture-backed desktop/mobile browser checks pass. CSV/XLSX HTTP generation and embedded logo round trip pass. Production dependency audit reports zero known vulnerabilities. See TEST_REPORT.md for mocks, warnings and unverified services.

Database changes: nine ordered migrations through 20261006083000_alerts_imports.sql. The latest adds scoped notification/read/rule/job records and reviewed vehicle/driver imports with atomic commits. Generated schema catalogue/types reflect all nine migrations. Implemented API families are enumerated in DATABASE_AND_API.md.
