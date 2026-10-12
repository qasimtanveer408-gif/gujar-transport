> Historical release notes. For this update use [UPGRADE-START-HERE.md](../UPGRADE-START-HERE.md) and the current enhancement test report. Do not rerun already applied migrations.

# Release verification — 2026-10-10

## Executed checks

| Check | Result |
|---|---|
| npm run typecheck | Passed: client/shared and compiled server TypeScript |
| npm run lint | Passed |
| npm test | Passed: 51 tests, zero failures |
| npm run build | Passed: frontend and Express server compiled |
| Ordered migrations | All thirteen applied to isolated PostgreSQL |
| HTTP record workflows | Vehicle Address; driver add/reload/edit/filter/print; trip add/edit; custom inputs/formulas; archive; permission failures |
| Formula checks | Decimal arithmetic, functions, missing values, zero, division by zero, unsafe syntax, cycles, dependent archive, saved reload |
| Private driver photos | Ready-image selection, optimistic version conflict, permission checks, authenticated response, source-deletion cleanup |
| Existing safeguards | Approval/ledger idempotency, assignment/duty, loans/payments, closed periods, access/RLS, imports, logout |
| PDF generation | Seven actual A4 PDFs; portrait/landscape settings supported |
| PDF boundary check | 23 total generated pages; zero characters outside page bounds |
| Print visual inspection | Monthly, combined, office, oil and supplementary driver pages; labels, values, margins and blank signing lines checked |
| CSV/XLSX | Numeric/date cells, custom calculated columns and spreadsheet-injection escaping checked |
| Schema inventory | Regenerated from the current isolated schema |

Logs are under verification/checks. The PDF/XLSX/CSV fixtures under verification/report-samples are explicitly TEST DATA ONLY. Rendered pages are under verification/rendered.

## Scope and remaining validation

Database tests use actual isolated PostgreSQL with mock Supabase Auth/Storage schemas and services. HTTP tests use the actual Express handlers, validation and caller-scoped SQL. Production runtime persistence remains Supabase; PGlite is used only by tests and report samples.

This release was not connected to a live Supabase/Hostinger account. Native browser UI checks, mobile/keyboard acceptance, real Storage byte transfers, actual printer/Save-as-PDF behavior and production deployment were not run in this environment. Historical screenshots retained under docs/screenshots predate this redesign and are not current browser evidence.

The templates preserve unavailable accounting source/rule markers. Incomplete report fields are documented in REPORT_DATA_MAPPING.md. Those markers prevent unknown share, settlement or carried-balance meanings from being reported as fabricated values.
