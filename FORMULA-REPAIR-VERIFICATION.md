# Gujjar Transport — formula repair verification

Date: 11 October 2026, Asia/Karachi.

## Implemented repairs

| Problem reproduced | Repair | Status |
|---|---|---|
| Valid `.50`, grouped `80,000.25`, surrounding spaces and trailing decimal point rejected on save | Shared numeric normalization before the existing precision/range validation; no automatic rounding of source input | Implemented; tested; passed |
| Displayed Unicode minus `−` rejected by the formula parser | Accept the displayed minus operator in the existing bounded arithmetic grammar | Implemented; tested; passed |
| Database-supported vehicle/driver numeric keys absent from editor/API formula whitelist | Align the numeric key catalog with the existing PostgreSQL catalog, including current odometer, profit, expenses and matched kilometres | Implemented; tested; passed |
| Invalid/incomplete expense cleared otherwise valid distance and average | Separate independent trip preview results; preserve all editable input strings and show validation errors against the affected fields | Implemented; tested; passed |
| Dropdowns/checkboxes had ambiguous accessible labels | Give controls explicit field labels; all requested editable base controls exercised in browser tests | Implemented; tested; passed |
| New formula/default numeric values could retain display grouping on submission | Normalize permitted numeric custom values/defaults before the existing database validators; preserve text values | Implemented; tested; passed |
| Numeric helpers could output nonfinite results for invalid programmatic input | Reject nonfinite trip values, skip unusable pooled/ranking values, render unavailable values safely | Implemented; tested; passed |
| Overview with populated tables overflowed on mobile | Constrain the mobile workspace to its available width | Implemented; tested; passed |

The existing calculated vehicle/driver summaries remain derived from approved records. Their readonly status preserves the application's intended accounting rules. Every writable base field was entered in the browser; existing permission and immutable-record restrictions remain in place.

## Requested overview and text changes

- **TOP AVERAGE VEHICLE** selects the highest existing pooled fuel-efficiency value from the dashboard's filtered fuel ranking. It displays registration and km/L, uses the current date range, fuel basis and minimum distance, and refreshes on the existing change event and refresh timer. No separate business metric or demo data was introduced.
- The reserved administrator's visible account name is **Attiq gujjar**. Authorization still uses the original **Super Admin** role. The sidebar descriptor is **Administrator**.
- The welcome heading is exactly **WELCOME SIR ATTIQ**, with a restrained entrance animation. Reduced motion disables that animation. Desktop, mobile and dark theme were checked.

## Identified formula inventory

| Existing calculation | Mathematical rule / source |
|---|---|
| Trip distance | End odometer − start odometer; a reversed reading is invalid |
| Trip expenses | Sum of diesel, tolls, fines/permits, food, reward, service, parking, engine oil, other and commission |
| Trip operating profit | Fare − total trip expenses; losses are valid calculated results |
| Trip average | Distance ÷ positive fuel litres; missing/zero fuel returns unavailable |
| Vehicle/driver distance | Sum of approved completed trip distances in the selected period |
| Matched distance and fuel | Sum distance and positive litres from the same eligible source trips |
| Vehicle/driver average | Matched kilometres ÷ matched litres; mixed bases remain unavailable according to the existing database rule |
| Start/end period readings | Existing minimum start / maximum end readings from approved completed trips |
| Vehicle/driver revenue and expense categories | Sum recognized ledger entries for the selected vehicle/driver and period |
| Vehicle/driver operating profit | Recognized revenue − recognized operating expenses |
| Dashboard revenue, expenses and profit | Existing recognized totals and time-series aggregates; reversal entries remain included |
| Top Average Vehicle | Highest filtered pooled km/L from the existing dashboard ranking |
| Cargo weight in tonnes | Kilogram weights ÷ 1000; tonne weights unchanged; aggregate eligible trips |
| Cycles | Count eligible completed trips under each existing report's filters |
| Loan taken | Opening principal + disbursements through the cutoff |
| Loan paid | Repayments through the cutoff |
| Loan left | Loan taken − loan paid |
| Driver unpaid earnings | Existing accrual amounts − allocated payments |
| Office report daily/period result | Recorded brokerage commission − office expense bills |
| Monthly/canonical operating result | Recognized revenue − recognized expenses; carried principal is not fabricated as an expense |
| Oil distance | Current oil-change reading − previous verified oil-change reading |
| Travel after oil change | Closing reading − last oil-change reading; inconsistent readings remain unavailable |
| Vehicle summary travel | Maximum closing reading − minimum starting reading under the existing report's scope |
| Report money totals | Sum mapped monetary columns; preserve intentionally unmapped columns |
| Custom formulas | Existing `+`, `−`, `*`, `×`, `/`, `÷`, remainder `%`, parentheses, unary signs, `SUM`, `MIN`, `MAX`, `ABS`, `ROUND` and dependency chains |

Money displays two decimals, physical quantities three, ordinary fuel averages two, and the existing monthly report average four. Custom calculated results retain the existing six-decimal rule. The new normalization does not expand the existing range or precision limits.

## Formula examples: expected versus actual

| Inputs / case | Expected | Actual | Evidence |
|---|---|---|---|
| Fare 80000; costs 29000+3000+1200+2000+800 | Expense 36000; profit 44000 | 36000.00; 44000.00 | Unit and PostgreSQL tests: PASS |
| Odometers 144844→145382; fuel 68 | 538 km; 7.91 km/L | 538.000; 7.91 | Unit/PostgreSQL: PASS |
| Edit diesel to 28000; end to 145524 | Expense 35000; profit 45000; 680 km; 10 km/L | 35000.00; 45000.00; 680.000; 10.00 | Unit: PASS |
| Browser fare `80,000.25`; costs 36000; odometers 150000→150680; fuel 68 | Profit 44000.25; 680 km; 10 km/L | 44000.25; 680.000; 10.00, including save/reload | Actual HTTP/PostgreSQL browser flow: PASS |
| Browser fare `.50`; costs 36000 | Profit −35999.50 | −35999.50 | Live browser recalculation: PASS |
| Fuel zero or empty | Average unavailable; other valid results retained | Unavailable; profit/distance retained | Unit/browser: PASS |
| Expense input `abc` or unfinished `.` | Clear field error; other inputs and distance/average retained | Correct error and unaffected distance/average | Unit/browser: PASS |
| Quantity 3; rate 2.50; balance = total − 1.25 | Total 7.50; balance 6.25 | 7.5; 6.25 | Browser: PASS |
| Quantity `4.`; rate 3.25 | Total 13; balance 11.75 | 13; 11.75; canonical quantity 4 after reload | Browser and SQL: PASS |
| Pool 538+680 km over 68+68 litres | 8.96 km/L | 8.96 | Unit: PASS |
| Two dashboard vehicles at 10 and 5 km/L | Select the 10 km/L vehicle | TEST-001, 10.00 km/L | Actual PostgreSQL browser flow: PASS |
| Void the 10 km/L source in the isolated fixture | Select the remaining 5 km/L vehicle | UI-001, 5.00 km/L after change event | PostgreSQL/browser: PASS |
| Basis/date/minimum distance exclude all records | Empty result | No eligible fuel records | Browser: PASS |
| Loan opening 10000 + disbursement 40000 − repayment 15000 | Taken 50000; paid 15000; left 35000 | 50000.00; 15000.00; 35000.00 | Existing PostgreSQL regression: PASS |

## Checks run

| Check | Result |
|---|---|
| Uploaded ZIP integrity | PASS; 11591 archive entries; original archive 232.72 MB |
| Production build | PASS |
| Type checking | PASS |
| ESLint | PASS |
| Automated unit/database/security/report tests | **57 passed, 0 failed** |
| All migration SQL executed in isolated PostgreSQL | PASS |
| Browser login/logout and navigation fixtures | PASS |
| Vehicle/driver/trip/maintenance create, edit, save, reload and print | PASS, real form HTTP handlers and isolated PostgreSQL |
| Custom field creation and chained formula typing | PASS, actual custom-field HTTP handlers and isolated PostgreSQL |
| Overview date/basis/distance filters and source update | PASS |
| PDF preview/download and mobile register | PASS |
| Mobile overview, dark theme and reduced motion | PASS |
| Browser runtime exceptions in acceptance suite | None |
| Local configuration validation | PASS |
| Configured hosted database read-only connectivity | PASS; all five inspected tables returned HTTP 200 |
| Actual hosted admin login, authenticated reload and logout | PASS; real Supabase Auth, HTTP 200, correct visible name and no runtime exceptions |

Browser business workflows use isolated PostgreSQL, with Auth/Storage fixtures. The configured hosted account was separately used for a real login, authenticated page reload and logout; all passed. This check did not modify business records. Detailed evidence is in `verification/formula-repair-20261011/live-auth-check.json`.

Read-only checks found one existing application user and one vehicle, with zero drivers, trips and custom-field definitions in the configured database. Consequently, the live overview initially has no eligible average to rank. Saving an approved completed trip with matching fuel/date/distance filters supplies the source data.

## Files modified / added

Modified source:

- `client/src/components.tsx`
- `client/src/CustomFieldsPage.tsx`
- `client/src/Dashboard.tsx`
- `client/src/ExactFormsPage.tsx`
- `client/src/main.tsx`
- `client/src/style.css`
- `server/custom-fields.ts`
- `server/forms.ts`
- `shared/calculations.ts`
- `shared/custom-fields.ts`
- `shared/validation.ts`

Modified acceptance tests: `scripts/e2e.mjs`, `scripts/forms-e2e.ts`.

Added: `shared/numeric-input.ts`, `shared/trip-form.ts`, `tests/formula-repairs.test.ts`, this report, the Roman Urdu startup guide and current verification logs. The production `dist` files and release manifest were regenerated.

Original private `.env`, `package.json`, lockfile and database migration files are preserved. No new database migration is required by this code repair. Existing records and authorization roles remain intact. Reproducible `node_modules` are installed by the existing Windows starter instead of being bundled in the repaired ZIP.

## Remaining / unverified items

- Existing printed business slots marked unconfirmed in the source remain unresolved: monthly `INCOME`, `Last Main`, `Total Main`, `MAIN`, `MIST`, printed `Total Sale`, printed final profit/loss, carried balances, percentage/share distributions and beneficiaries. Canonical recognized revenue/expenses/profit are available. These slots need confirmed business rules; arbitrary formulas were not inserted.
- Uploaded attachments/storage and every possible hosted account/permission combination were not exercised against live production. The isolated security and permission regressions passed.
- Business CRUD and approval/void tests ran in the isolated database. Live business records were preserved.
- The Windows batch file was not executed on a Windows computer here. Node 24 startup, browser behavior and build checks ran in the test environment; Windows instructions use the project's existing starter.
- Pre-existing historical screenshots and verification folders are retained as historical material. Current results are in `verification/formula-repair-20261011/`.
