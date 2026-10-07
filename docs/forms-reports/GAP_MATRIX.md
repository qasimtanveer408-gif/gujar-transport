# Targeted gap matrix

| Module | Requested field/section | Supplied implementation | Correction | Source | Verification |
|---|---|---|---|---|---|
| Vehicle | Exact sequence, year, purchase price, work text | Generic form; full date/model required; purchase-price validation blocked | Dedicated ordered form; restricted price store retained; additive year/work fields | vehicles + vehicle_financials + canonical period totals | Browser save/reload/edit; SQL; CSV/XLSX |
| Driver | Integrated identity, vehicle first, loan group | Identity action separate; requested values omitted | Atomic profile/identity/assignment form; cumulative loan context | drivers, identity, assignment history, loan ledger | Atomic rollback, leading-zero, history and RLS tests; browser |
| Trip | Ten visible expenses, exact labels, calculations | Dropdown line editor; unrelated required routes/status | Ordered category controls with non-destructive amount reconciliation; optional route/draft workflow | trips, trip_financials, trip_expense_lines | 80,000/36,000/44,000; 538/68/7.91; multiple-line identity preservation |
| Maintenance | Ten text components, cabin/body separate | Single category and invoice form | Separate component text rows; unposted unknown-date notes; retained invoice/oil workflow | maintenance_components + existing invoices/oil | All components edited/reloaded; old item IDs and costs preserved |
| Registers | All requested fields and permitted order | Generic selected-column table | Ordered horizontally scrolling tables and explicit export schemas | form_record/form_register/form_export | Empty headers; >25-row export; permission filtering |
| Office | Grouped daily paper grid | Generic row export | Daily merged cells, commissions vs quoted freight, itemized expense and period totals | approved bookings/office expenses | Two-booking one-bill test; PDF and saved XLSX rendering |
| Oil | Two DATE columns, historical closing meter | Generic maintenance export | Ten-column landscape template with cutoff-based readings | approved oil/dated trip observations | Duplicate DATE headings; future readings excluded |
| Monthly | Wide grid, repeated DESEL, lower boxes/signatures | Generic monthly account rows | A3 template, brand separator, reconciled current expenses, unresolved carried values blank | authorized canonical ledgers and approved trips | Measured 4-decimal efficiency; header/section tests and rendering |
| Combined | Maintenance/cycle split, settlement, four detail panels | No matching multi-section template | Complete template with signatures, structured-cost detail, continued pages | trip, invoice/component and loan snapshots | Section/loan/cycle tests; 90-row negative-profit stress PDF |
| Driver details | Supplemental summary and graph | No dedicated template | Authorized summary and recorded-result graph/data bars | approved trips and retained report-only driver remarks | Contract and rendered output checks |

The supplied old tests were not evidence for the new controls. New SQL, HTTP, browser and renderer checks are separately recorded in TEST_RESULTS.md. Hosted services remain untested.
