# Forms and reports verification

Executed against the supplied source plus this patch, using Node 24.19.0 and an isolated PostgreSQL/PGlite database. No hosted credentials or live services were used.

| Check | Result | Evidence / scope |
|---|---|---|
| TypeScript client/server check | PASS | `verification/logs/typecheck.log` |
| ESLint | PASS | `verification/logs/lint.log` |
| Automated tests | PASS — 38 tests, 0 failures | `verification/logs/tests.log`; actual migrations and SQL functions, fixture Auth/Storage |
| Production Vite + server build | PASS | `verification/logs/build.log`; fonts and logo are copied into dist/client |
| Browser regression | PASS | Login/logout, dashboard, nested refresh, mobile navigation, no overflow, no browser exceptions; fixture authentication |
| Form browser → HTTP → database | PASS for all four | All editable controls entered, saved, refreshed, reopened and edited through the actual form handlers and isolated SQL; stored values compared |
| Exact labels and sequence | PASS | Explicit expected arrays independent of implementation; restricted subsets checked separately |
| Purchase price / identity / assignment | PASS | Typed price store; leading-zero identity strings; atomic rollback and assignment history; old trip unchanged |
| Trip expenses and hidden fields | PASS | All ten categories; multiple diesel lines retain IDs/descriptions/dates; old route/cargo/basis survive; approved/closed-period restrictions |
| Requested arithmetic | PASS | 80,000 − 36,000 = 44,000; 145,382 − 144,844 = 538; 538 / 68 = 7.91; 50,000 − 15,000 = 35,000 |
| Maintenance preservation | PASS | Every component string edited/reloaded; undated records remain visible; original invoice item rows and supplier unchanged; unposted approval refused |
| RLS and permissions | PASS in isolated SQL | Viewer lacks identity/finance, cannot save/export unauthorized data; SQL direct mutation checks; no widened table write grants |
| Accounting regressions | PASS | Existing duplicate-posting, rollback, loan/commission payment, close/reopen and session-revocation tests retained |
| Export completeness | PASS | 31 master records exported beyond a 25-row UI page; stable empty headers; no raw IDs in full-field columns |
| Export numeric types | PASS | Excel numbers/dates/text IDs; negative monetary values stay numeric; formula-like text neutralized |
| Reference source rules | PASS | Two bookings share one daily bill; historical oil cutoff excludes future reading; monthly measured AVE 7.9118; unknown subtotals blank |
| Direct PDF / report preview | PASS | Browser loaded reference preview and downloaded a PDF; all five generators produce valid PDF/XLSX bytes |
| PDF rendering | PASS | Every generated PDF rasterized; text and bottom sections inspected; long description continues across pages; 90-trip example includes last row, negatives, totals and signatures |
| Saved workbook rendering | PASS for cell-model rendering | Actual saved XLSX files re-opened and rendered with merges/styles/widths/heights. Native Excel print pagination is **not** verified |
| Schema snapshot / generated row types | PASS | Generated after applying all 11 migrations in isolated PostgreSQL |

## Rendered examples

All examples use synthetic records labelled TEST DATA ONLY. Their amounts are not imported from the photographs. The standard office/oil/monthly PDFs are one landscape page each; the combined example is two A3 landscape pages, including its full bottom detail panels; the supplementary driver output is one A4 landscape page. The 90-trip stress example is five pages, and the oversized office-description case is six. Actual page counts are recorded in `verification/logs/pdf-inspection.json`.

The reference-format sheets preserve the requested heading inventories, duplicate DATE/DESEL positions, grouping, bands, side-by-side upper combined tables, summary/settlement blocks, blank signature areas and four bottom detail panels. They are structural adaptations, not asserted pixel-identical replicas. The original photographs' camera artifacts, private names and suspect handwritten arithmetic are excluded.

Before screenshots were captured from a separate build of the supplied original client. After screenshots show the patched client with test values. Form dialogs were expanded for evidence capture so all controls can be inspected; the normal UI remains scrollable. Register screens use horizontal scrolling. XLSX PNGs are an explicit inspection rendering of saved workbook cells, not a screenshot from Microsoft Excel.

## Not executed / remaining dependencies

- Hosted Supabase Auth, PostgREST, Storage, refresh/recovery, and hosted RLS behavior were not exercised. Supabase-owned schemas are mocked in the isolated SQL tests.
- No database migration was applied to the user's project; no live data, password or admin configuration was changed.
- No Hostinger account, deployment, DNS/SSL, restart persistence or plan capability was verified.
- No native Excel/LibreOffice/printer engine is installed here. Review native workbook page breaks, repeated title rows and conditional data bars locally before operational printing. Direct PDF uses bundled fonts and was rendered here.
- User-owned historical records were not reconciled; new work-detail notes intentionally remain unposted when date/cost sources are missing.
- Company/category meanings, monthly carried balances, share allocation and settlement mappings remain business decisions. See REMAINING_QUESTIONS.md. Incomplete reports are not finalized statements.

The original `docs/TEST_REPORT.md` describes the prior application checkpoint. This file is the patch-specific verification record.
