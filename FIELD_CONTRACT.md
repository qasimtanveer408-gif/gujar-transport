# Field contract

The canonical field contract controls these corrected captions and positions; legacy storage keys are retained. `shared/form-contract.ts` is the executable specification for the four forms and their registers/exports. All positions below are one-based after expanding only the requested groups. UI stars indicate required inputs; labels use consistent English spelling. Lookup IDs are technical payload values; business exports contain resolved names only.

## Add vehicle

| Position | Literal label | Key | Type | Editable / calculated | Permission | Source | Group | Reference-format mapping |
|---|---|---|---|---|---|---|---|---|
| 1 | Vehicle number | registration | text | Editable; approved transaction records are immutable | Module view | vehicles.registration | — | Oil Vehicle Number; monthly VEHICLE #; combined Vehicle |
| 2 | Company / manufacturer | manufacturer | text | Editable; approved transaction records are immutable | Module view | manufacturer | — | Not printed; full-field register only |
| 3 | Model | model | text | Editable; approved transaction records are immutable | Module view | model | — | Full-field export only |
| 4 | Vehicle status | status | select | Editable; approved transaction records are immutable | Module view | status | — | Full-field export only |
| 5 | Address | address | textarea | Editable; approved transaction records are immutable | Module view | vehicles.address | — | Full-field export only, restricted |
| 6 | Opening odometer (km) | opening_odometer | decimal | Editable; approved transaction records are immutable | Module view | opening_odometer | — | Full-field export only |
| 7 | Service interval (km) | service_interval_km | decimal | Editable; approved transaction records are immutable | Module view | service_interval_km | — | Full-field export only |
| 8 | Document expiry | document_expiry | date | Editable; approved transaction records are immutable | Module view | document_expiry | — | Full-field export only |
| 9 | Permit expiry | permit_expiry | date | Editable; approved transaction records are immutable | Module view | permit_expiry | — | Full-field export only |
| 10 | Insurance expiry | insurance_expiry | date | Editable; approved transaction records are immutable | Module view | insurance_expiry | — | Full-field export only |
| 11 | Purchase year | purchase_year | year | Editable; approved transaction records are immutable | Module view | purchase_year | — | Not printed; full-field register only |
| 12 | Purchase price (PKR) | purchase_price | decimal | Editable; approved transaction records are immutable | reports.financial.view / write: reports.financial.view | vehicle_financials.purchase_price | — | Not printed; full-field register only |
| 13 | Revenue (PKR) | income | decimal | Calculated, read-only | reports.financial.view | Approved ledger revenue | Calculated totals | Monthly canonical gross recognized fare reconciliation; printed INCOME is unresolved |
| 14 | Tolls (PKR) | tolls | decimal | Calculated, read-only | reports.financial.view | Approved expenses | Calculated totals | Monthly TOLL PLAZA; cycle Toll Plaza; driver tool |
| 15 | Punjab Police (PKR) | fines_permits | decimal | Calculated, read-only | reports.financial.view | Approved expenses | Calculated totals | Monthly CHALLAN; cycle Chln; driver punjab police challan |
| 16 | Start odometer (km) | start_km | decimal | Calculated, read-only | Module view | First approved trip | Calculated totals | Combined Start Meter |
| 17 | End odometer (km) | end_km | decimal | Calculated, read-only | Module view | Last approved trip | Calculated totals | Combined Close Meter |
| 18 | Total distance (km) | total_km | decimal | Calculated, read-only | Module view | Sum of approved trip distances | Calculated totals | Cycle Travel (km); monthly KM (measured matched basis); driver distance context |
| 19 | Matched fuel (litres) | litres | decimal | Calculated, read-only | Module view | Positive fuel for matched approved trips | Calculated totals | Monthly second DIESEL (measured matched basis); driver efficiency context |
| 20 | Average (km/L) | average | decimal | Calculated, read-only | Module view | Matched distance / fuel | Calculated totals | Cycle Avg Km/L (2 decimals); monthly AVE (4 decimals); driver ave |
| 21 | Major maintenance work | major_maintenance_work | textarea | Editable; approved transaction records are immutable | Module view | major_maintenance_work | — | Not printed as an invoice; full-field register only |
| 22 | Remarks | remarks | textarea | Editable; approved transaction records are immutable | Module view | remarks | — | Driver supplementary remarks where applicable; full-field register |

## Add driver

| Position | Literal label | Key | Type | Editable / calculated | Permission | Source | Group | Reference-format mapping |
|---|---|---|---|---|---|---|---|---|
| 1 | Assigned vehicle | vehicle_id | lookup | Editable; approved transaction records are immutable | Module view / write: assignments.manage | Current assignment | — | Resolved vehicle registration in identification/oil/monthly/office |
| 2 | Vehicle assigned date | assignment_date | date | Editable; approved transaction records are immutable | Module view / write: assignments.manage | Assignment effective date | — | Full-field export only |
| 3 | Assignment reason (optional) | assignment_reason | text | Editable; approved transaction records are immutable | Module view / write: assignments.manage | Assignment reason | — | Full-field export only |
| 4 | Driver name | full_name | text | Editable; approved transaction records are immutable | Module view | drivers.full_name | — | Driver identification |
| 5 | Father’s name | father_name | text | Editable; approved transaction records are immutable | drivers.identity.view / write: drivers.identity.manage | driver_identity_details.father_name | — | Full-field export only, restricted |
| 6 | CNIC number | cnic | text | Editable; approved transaction records are immutable | drivers.identity.view / write: drivers.identity.manage | driver_identity_details.cnic | — | Full-field export only, restricted |
| 7 | Driving licence number | licence_number | text | Editable; approved transaction records are immutable | drivers.identity.view / write: drivers.identity.manage | driver_identity_details.licence_number | — | Full-field export only, restricted |
| 8 | Mobile number | mobile | text | Editable; approved transaction records are immutable | Module view | drivers.mobile | — | Full-field export only; office contact comes from booking.driver_contact |
| 9 | Next of kin number | emergency_contact | text | Editable; approved transaction records are immutable | drivers.identity.view / write: drivers.identity.manage | driver_identity_details.emergency_contact | — | Full-field export only, restricted |
| 10 | Joining date | joining_date | date | Editable; approved transaction records are immutable | Module view | joining_date | — | Combined Joining Date |
| 11 | Leaving date | leaving_date | date | Editable; approved transaction records are immutable | Module view | leaving_date | — | Full-field export only |
| 12 | Licence expiry | licence_expiry | date | Editable; approved transaction records are immutable | Module view | licence_expiry | — | Full-field export only |
| 13 | Employment status | employment_status | select | Editable; approved transaction records are immutable | Module view | employment_status | — | Full-field export only |
| 14 | Address | address | textarea | Editable; approved transaction records are immutable | drivers.identity.view / write: drivers.identity.manage | driver_identity_details.address | — | Full-field export only, restricted |
| 15 | Tolls (PKR) | tolls | decimal | Calculated, read-only | reports.financial.view | Approved expenses | Calculated totals | Monthly TOLL PLAZA; cycle Toll Plaza; driver tool |
| 16 | Punjab Police (PKR) | fines_permits | decimal | Calculated, read-only | reports.financial.view | Approved expenses | Calculated totals | Monthly CHALLAN; cycle Chln; driver punjab police challan |
| 17 | Matched fuel (litres) | litres | decimal | Calculated, read-only | Module view | Trips with usable fuel | Calculated totals | Monthly second DIESEL (measured matched basis); driver efficiency context |
| 18 | Total distance (km) | total_km | decimal | Calculated, read-only | Module view | Sum of all approved trip distances | Calculated totals | Cycle Travel (km); monthly KM (measured matched basis); driver distance context |
| 19 | Average (km/L) | average | decimal | Calculated, read-only | Module view | Matched distance / fuel | Calculated totals | Cycle Avg Km/L (2 decimals); monthly AVE (4 decimals); driver ave |
| 20 | Cargo weight (tonnes) | weight | decimal | Calculated, read-only | Module view | Approved trip weight | Calculated totals | Monthly WEIGHT; supplementary driver weight |
| 21 | Completed trips | cycles | decimal | Calculated, read-only | Module view | Count of approved completed trips | Calculated totals | Monthly CYCLES; supplementary driver cycle |
| 22 | Total loan (PKR) | loan_taken | decimal | Calculated, read-only | loans.view | Opening + disbursements | Loan balance | Combined Total Loan |
| 23 | Loan repaid (PKR) | loan_paid | decimal | Calculated, read-only | loans.view | Repayments | Loan balance | Combined Loan Return |
| 24 | Loan balance (PKR) | loan_left | decimal | Calculated, read-only | loans.view | Total loan - repaid | Loan balance | Combined Loan left |
| 25 | Remarks | remarks | textarea | Editable; approved transaction records are immutable | Module view | drivers.remarks | — | Driver supplementary remarks where applicable; full-field register |

## Add trip

| Position | Literal label | Key | Type | Editable / calculated | Permission | Source | Group | Reference-format mapping |
|---|---|---|---|---|---|---|---|---|
| 1 | Date | business_date | date | Editable; approved transaction records are immutable | Module view | trips.business_date | — | Cycle Date |
| 2 | Vehicle | vehicle_id | lookup | Editable; approved transaction records are immutable | Module view | trips.vehicle_id | — | Resolved vehicle registration in identification/oil/monthly/office |
| 3 | Driver | driver_id | lookup | Editable; approved transaction records are immutable | Module view | trips.driver_id | — | Resolved name in cycle/report identification |
| 4 | Cycle number | cycle_number | text | Editable; approved transaction records are immutable | Module view | trips.cycle_number | — | Full-field export only; printed Cycle uses historical route descriptions |
| 5 | From | origin | text | Editable; approved transaction records are immutable | Module view | trips.origin | Journey details | Full-field export only |
| 6 | To | destination | text | Editable; approved transaction records are immutable | Module view | trips.destination | Journey details | Full-field export only |
| 7 | Route notes | route_description | text | Editable; approved transaction records are immutable | Module view | trips.route_description | Journey details | Full-field export only |
| 8 | Cargo | cargo | text | Editable; approved transaction records are immutable | Module view | cargo | — | Full-field export only |
| 9 | Fuel measurement basis | fuel_basis | select | Editable; approved transaction records are immutable | Module view | fuel_basis | — | Full-field export only |
| 10 | Weight unit | weight_unit | select | Editable; approved transaction records are immutable | Module view | weight_unit | — | Full-field export only |
| 11 | Fare (PKR) | fare | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_financials.fare | Trip income & expenses · PKR | Cycle Fare; supplementary Sale; canonical gross-fare reconciliation |
| 12 | Diesel (PKR) | diesel | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.diesel | Trip income & expenses · PKR | Cycle Diesel (Price); monthly first DIESEL (cost) |
| 13 | Tolls (PKR) | tolls | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.tolls | Trip income & expenses · PKR | Monthly TOLL PLAZA; cycle Toll Plaza; driver tool |
| 14 | Punjab Police (PKR) | fines_permits | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.fines_permits | Trip income & expenses · PKR | Monthly CHALLAN; cycle Chln; driver punjab police challan |
| 15 | Food (PKR) | food | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.food | Trip income & expenses · PKR | Cycle Food |
| 16 | Inam / reward (PKR) | reward | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.reward | Trip income & expenses · PKR | Cycle inm |
| 17 | Service (PKR) | service | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.service | Trip income & expenses · PKR | Included in cycle Other Exp. |
| 18 | Parking (PKR) | parking | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.parking | Trip income & expenses · PKR | Included in cycle Other Exp. |
| 19 | Engine oil (PKR) | engine_oil | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.engine_oil | Trip income & expenses · PKR | Cycle Mobil Oil |
| 20 | Other expenses (PKR) | other | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.other | Trip income & expenses · PKR | Included in cycle Other Exp. |
| 21 | Driver cycle commission (PKR) | commission | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.commission | Trip income & expenses · PKR | Cycle Driver commission; monthly DRIVER. COMM.; settlement Driver Commission |
| 22 | Total expenses (PKR) | total_expense | decimal | Calculated, read-only | trips.finance.view | Sum of all expense lines | Trip income & expenses · PKR | Cycle Total Exp.; supplementary expense |
| 23 | Profit (PKR) | profit | decimal | Calculated, read-only | trips.finance.view | Fare - all expenses | Trip income & expenses · PKR | Cycle Profit Loss; supplementary profit; not assumed equivalent to monthly INCOME |
| 24 | Start odometer (km) | start_odometer | decimal | Editable; approved transaction records are immutable | Module view | trips.start_odometer | Distance & fuel | Combined Start Meter source |
| 25 | End odometer (km) | end_odometer | decimal | Editable; approved transaction records are immutable | Module view | trips.end_odometer | Distance & fuel | Combined Close Meter source; historical closing-meter observations |
| 26 | Total distance (km) | total_km | decimal | Calculated, read-only | Module view | End - start | Distance & fuel | Cycle Travel (km); monthly KM (measured matched basis); driver distance context |
| 27 | Fuel (litres) | fuel_litres | decimal | Editable; approved transaction records are immutable | Module view | trips.fuel_litres | Distance & fuel | Cycle Diesel (Ltr); monthly matched measured litres |
| 28 | Average (km/L) | average | decimal | Calculated, read-only | Module view | Distance / litres | Distance & fuel | Cycle Avg Km/L (2 decimals); monthly AVE (4 decimals); driver ave |
| 29 | Cargo weight | weight | decimal | Editable; approved transaction records are immutable | Module view | weight | — | Monthly WEIGHT; supplementary driver weight |
| 30 | Remarks | remarks | textarea | Editable; approved transaction records are immutable | Module view | remarks | — | Driver supplementary remarks where applicable; full-field register |

## Add maintenance

| Position | Literal label | Key | Type | Editable / calculated | Permission | Source | Group | Reference-format mapping |
|---|---|---|---|---|---|---|---|---|
| 1 | Vehicle | vehicle_id | lookup | Editable; approved transaction records are immutable | Module view | maintenance_records.vehicle_id | — | Resolved vehicle registration in identification/oil/monthly/office |
| 2 | Driver | driver_id | lookup | Editable; approved transaction records are immutable | Module view | maintenance_records.driver_id | — | Resolved name in cycle/report identification |
| 3 | Engine | engine | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.engine | Component work notes | ENGINE descriptive panel; no price parsed from text |
| 4 | Gear | gearbox | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.gearbox | Component work notes | GEAR descriptive panel |
| 5 | Hissa / parts | parts | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.parts | Component work notes | Full-field export only |
| 6 | Tyre | tyres | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.tyres | Component work notes | TYRES descriptive panel |
| 7 | Electrical wiring | wiring | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.wiring | Component work notes | Full-field export only |
| 8 | Electric self / starter | starter | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.starter | Component work notes | Full-field export only |
| 9 | Electric generator / alternator | alternator | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.alternator | Component work notes | Full-field export only |
| 10 | Electric lighting | lighting | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.lighting | Component work notes | Full-field export only |
| 11 | Cabin | cabin | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.cabin | Component work notes | BODY / CABIN descriptive panel, stored separately |
| 12 | Body | body | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.body | Component work notes | BODY / CABIN descriptive panel, stored separately |

## Calculation and context rules

- Trip distance = end − start; efficiency = distance ÷ fuel litres. No efficiency for missing/zero litres. New trips are Planned drafts with a visibly disclosed purchase-estimate fuel basis and metric-tonne weight unit. Existing fuel basis and weight unit survive edits. Mark Completed is a separate action before Submit/Approve.
- Vehicle income is recognized approved revenue, not profit. Tolls and fines use canonical expense entries, including reversals, for the selected inclusive dates. No duplicate aggregate inputs are written.
- Vehicle start/end describe its recorded meter span. Its two distance operands reuse that span. Efficiency is withheld if matched recorded distance does not equal that span (gaps/missing fuel), or if fuel bases are mixed. Driver distance is matched recorded distance. Both divide summed corresponding distance by summed litres, never mean trip ratios.
- Driver weight is normalized to metric tonnes; cycles count approved completed trips in range.
- Loan taken includes verified Opening plus Disbursement transactions through the cutoff. Loan paid includes repayments through cutoff. Loan left = taken − paid. Opening is separately identified in the form hint and never treated as period cash movement.
- Master records and current assignments are current-state data; selected dates apply to transaction-derived totals. Maintenance register includes all authorized component records, including undated notes; no historical service date is inferred.
- Company provisionally maps to `vehicles.manufacturer`; the form explicitly flags this. `owner_company_id`, model, purchase_date, service intervals and all other omitted historical fields remain untouched. Purchase year never creates a synthetic full date.
- Trip aggregate reconciliation changes only amounts: increases go to the highest UUID in the category; decreases consume amounts in descending UUID order. Zero rows remain. IDs, dates, descriptions and linked attachments remain. This deterministic order does not claim chronological recency. Only absent categories need new lines. Unchanged categories are untouched. Approved records require the existing void/correction workflow.
- Driver profile, identity details, identity version and current-assignment version are saved in one transaction. A conflict rolls back every part. Historical trips are unchanged.
- Maintenance component strings are unpriced work details. New notes have no assumed date/odometer/category/cost and cannot post. Existing invoice/oil details remain in the separate existing invoice workflow at `/maintenance/invoices`.
- Sensitive fields are permission-filtered in UI definitions, server validation, RLS-backed reads and exports. The same permitted ordered subset appears in full-field exports, including empty exports.
