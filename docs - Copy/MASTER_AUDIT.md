# Existing-project audit — 11 October 2026

Completed before source edits, against the uploaded ZIP and all five print references. Baseline: 71 tests passing; production dependency audit: zero reported vulnerabilities.

## Existing modules, preserved

Dashboard; vehicles; drivers; dated assignments/transfers; driver duty; trips; maintenance components/invoices/oil; office expenses; office bookings; driver loans; driver earnings/payments; accounting periods; routes; reports and CSV/PDF/XLSX exports; notifications/alert rules; imports; custom fields/formulas; users; roles/permissions; settings; audit history; documents/photos. Companies remains an existing database relationship with its hidden navigation preserved.

## Requested field coverage

| Module | Existing requested fields | Finding before changes |
|---|---|---|
| Vehicle | Number; manufacturer/company; purchase year/price; income; toll; Punjab Police; start/end/total km; litres/average; major maintenance; remarks | All exist. Company reuses manufacturer. Totals derive from approved records without duplicate inputs/ledger. |
| Driver | Vehicle; name; father; CNIC; licence; mobile; next-of-kin; join/leave dates; address; toll; police; average; weight; cycles; loan taken/paid/left | All exist. drivers.remarks exists in storage and generic editor but is missing in the exact form and rejected by its SQL allowlist. Dated transfers/history already exist. |
| Trip | Date; vehicle; driver; cycle; fare; diesel; toll; police; food; reward/Inam; service; parking; engine/Mobil oil; other; commission; expenses/profit; meter/distance; fuel/average; weight; remarks | All exist. Reward/commission display names are misleading; keys/accounting meanings must remain unchanged. |
| Maintenance | Vehicle; driver; engine; gear; parts/Hissa; tyre; wiring; starter/self; alternator/generator; lighting; cabin; body | All exist. Notes remain distinct from the existing dated invoice/oil workflow; never infer costs from text. |

## Formulas checked

| Formula | Existing implementation / decision |
|---|---|
| Trip KM | End odometer minus start odometer; negative distances rejected. |
| Average | Matched distance divided by positive litres, km/L. Missing/zero fuel is unavailable; pooled ratio is not a mean of ratios. Mixed bases are not combined. |
| Vehicle/driver distance | Sum of approved completed trip distances; start/end are meter span. Gaps are not inferred as trips. |
| Expenses | Sum of all ten categories, including reward and commission. |
| Profit | Fare minus total expense; losses are valid. |
| Loan left | Opening plus disbursements minus repayments through cutoff. Principal is not an operating expense. |

## Focused gaps

- Cookie and DB session expiry: 12 hours; change both to 3 hours using a forward migration, preserving sessions/users/business records.
- Existing CSS has partial hover/reduced-motion support; complete buttons/icons/cards/table feedback without animation libraries.
- Login downloads one approximately 416 KB JS bundle. Lazy-load page modules. Logo and favicon are each approximately 1.9 MB; optimize deployment assets from existing artwork.
- Existing security: HTTPS template; Helmet CSP/HSTS; HttpOnly/Strict cookies; signed CSRF/Origin checks; encrypted server-side credentials; throttling; role checks; parameterized RPCs; RLS; optimistic versions; immutable ledger posting/reversals; audit; protected documents. Improve choice validation, expiry UX and caching without replacing auth.
- Reference HTML lacks a generation footer, and dense money cells can overflow. Retain templates/signatures/PDF/XLSX routes and continuation headers.
- No robots/sitemap policy; add metadata and a privacy-aware crawler policy without exposing records.
- Existing indexes start with broad dates; add distinct approved-completed vehicle/driver-first aggregate indexes, no duplicate tables/fields.

## Supplied print references

| Attachment | Existing template |
|---|---|
| image(20261011-152723).png | Combined driver/cycle/maintenance/settlement/signatures |
| image(20261011-152735).png | Monthly transport account, allocation/comparison blocks |
| image(20261011-152744).png | Oil-change meter/date register |
| image(20261011-152752).png | Office daily bookings/expenses register |
| image(20261011-152759).png | Supplementary driver details, remarks and graph |

Unconfirmed settlement deductions, carried maintenance balances and profit-share rules stay unavailable. Canonical reconciliation remains available. Handwritten example amounts/percentages are not live data.

Work uses a copied ZIP and disposable SQL fixtures. Hosted data/customer credentials/real printers are not changed. Historical migrations are preserved; SQL changes use one new migration.
