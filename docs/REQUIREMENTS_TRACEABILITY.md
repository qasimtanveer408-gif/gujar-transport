# Redesign requirements traceability — 2026-10-10

The controlling redesign request is MASTER_REQUIREMENTS.txt. Implemented refers to shipped source and SQL. Local test results do not imply live deployment or browser acceptance.

| Request | Implementation | Validation / boundary |
|---|---|---|
| 1: consistent premium UI | main.tsx, style.css, shared components, Dashboard, management pages | Compiles; responsive rules and reduced motion implemented; native browser acceptance pending |
| 2: remove Fleet Companies | Sidebar/page chooser/reports hide companies | Backing company records and foreign keys preserved |
| 3: labels and Address | form-contract, select controls, persistent vehicles.address | Address save/reload tested; business keys retained |
| 4: driver cards | Default cards, contact/address/licence/assignment/status, private photo | HTTP save/edit/search/reload/print; photos scoped to documents permission |
| 5: vehicle/trip cards | Saved-record cards, detail/edit/print, recent saved record, table toggle | Actual HTTP and SQL persistence tests |
| 6: admin custom fields | Definitions/values, nine types, flags/defaults/order/archive | All types, defaults, required input, retained values and atomic rollback tested |
| 7: calculations | Decimal input calculations; SQL-derived totals; bounded formula engine | Decimal, missing/zero/division, dependency, cycles, security and reload tests |
| 8: printing | Top print controls, card actions, saved-record previews, report exports | Actual selected-record HTML; PDF/XLSX/CSV checks; browser dialog pending |
| 9: five print images | Office, oil, monthly, combined, supplementary driver layouts | Structural adaptation; unknown financial mappings explicitly marked |
| 10: signatures | Administrator document-specific labels | Blank signature/name/date lines; template version conflicts tested |
| 11: A4 output | Portrait/landscape, monochrome, wrapping, repeated headers, page continuation | Seven PDFs / 23 pages; boundary checks and visual inspection |
| 12: animation | Short CSS opacity/transform transitions and reduced-motion rules | No animation dependency added |
| 13: workflows | Existing APIs retained; improved cards, editors, search, print, archive | Existing ledger/assignment/loan/period tests plus new HTTP flows pass |
| 14: admin permissions | API checks plus SQL permission guards, RLS and audit | Restricted callers blocked; sensitive formula permissions inherited |
| 15: dashboard | Driver/vehicle/trip/pending/expiry summaries and performance data | Real database aggregations; no production mock statistics |
| 16: efficiency | Debounced paginated registers, shared components, bounded custom fields | Build succeeds; very large live-data and browser profiling pending |
| 17: preserve architecture/data | Original framework, BFF, Supabase, two additive migrations | Thirteen ordered migrations execute in isolated PostgreSQL |
| 18: functional testing | 51 unit/HTTP/PostgreSQL tests, static checks, print checks | Live Supabase, native browser/mobile and printer testing outstanding |
| 19: delivery | Updated source/build ZIP, migration/setup/manuals/test evidence | Existing credentials excluded; rollout documented |
