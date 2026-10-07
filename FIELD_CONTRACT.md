# Field contract

The typed request controls these exact captions and positions. `shared/form-contract.ts` is the executable specification for the four forms and their registers/exports. All positions below are one-based after expanding only the requested groups. UI stars indicate required inputs; stored labels remain literal. Lookup IDs are technical payload values; business exports contain resolved names only.

## Add vehical

| Position | Literal label | Key | Type | Editable / calculated | Permission | Source | Group | Reference-format mapping |
|---|---|---|---|---|---|---|---|---|
| 1 | vehical no | registration | text | Editable; approved transaction records are immutable | Module view | vehicles.registration | — | Oil Vehicle Number; monthly VEHICLE #; combined Vehicle |
| 2 | company | manufacturer | text | Editable; approved transaction records are immutable | Module view | vehicles.manufacturer | — | Not printed; full-field register only |
| 3 | purchase year | purchase_year | year | Editable; approved transaction records are immutable | Module view | vehicles.purchase_year | — | Not printed; full-field register only |
| 4 | purchase price | purchase_price | decimal | Editable; approved transaction records are immutable | reports.financial.view / write: reports.financial.view | vehicle_financials.purchase_price | — | Not printed; full-field register only |
| 5 | income | income | decimal | Calculated, read-only | reports.financial.view | approved revenue_entries | — | Monthly canonical gross recognized fare reconciliation; printed INCOME is unresolved |
| 6 | tool | tolls | decimal | Calculated, read-only | reports.financial.view | approved expense_entries: tolls | — | Monthly TOLL PLAZA; cycle Toll Plaza; driver tool |
| 7 | punjab police | fines_permits | decimal | Calculated, read-only | reports.financial.view | approved expense_entries: fines_permits | — | Monthly CHALLAN; cycle Chln; driver punjab police challan |
| 8 | start km | start_km | decimal | Calculated, read-only | Module view | period first approved trip | start km - end km=total km | Combined Start Meter |
| 9 | end km | end_km | decimal | Calculated, read-only | Module view | period last approved trip | start km - end km=total km | Combined Close Meter |
| 10 | total km | total_km | decimal | Calculated, read-only | Module view | end km - start km | start km - end km=total km | Cycle Travl (km); monthly KM (measured matched basis); driver distance context |
| 11 | liter | litres | decimal | Calculated, read-only | Module view | matched period fuel litres | liter / km=ave | Monthly second DESEL (measured matched basis); driver efficiency context |
| 12 | km | total_km | decimal | Calculated, read-only | Module view | same distance as above | liter / km=ave | Cycle Travl (km); monthly KM (measured matched basis); driver distance context |
| 13 | ave | average | decimal | Calculated, read-only | Module view | matched distance / litres (one basis) | liter / km=ave | Cycle Avg Km/L (2 decimals); monthly AVE (4 decimals); driver ave |
| 14 | major maintenence work | major_maintenance_work | textarea | Editable; approved transaction records are immutable | Module view | vehicles.major_maintenance_work | — | Not printed as an invoice; full-field register only |
| 15 | remarks | remarks | textarea | Editable; approved transaction records are immutable | Module view | vehicles.remarks | — | Driver supplementary remarks where applicable; full-field register |

## Driver

| Position | Literal label | Key | Type | Editable / calculated | Permission | Source | Group | Reference-format mapping |
|---|---|---|---|---|---|---|---|---|
| 1 | vehical no | vehicle_id | lookup | Editable; approved transaction records are immutable | Module view / write: assignments.manage | current assignment history | — | Resolved vehicle registration in identification/oil/monthly/office |
| 2 | driver name | full_name | text | Editable; approved transaction records are immutable | Module view | drivers.full_name | — | Driver identification |
| 3 | father name | father_name | text | Editable; approved transaction records are immutable | drivers.identity.view / write: drivers.identity.manage | driver_identity_details.father_name | — | Full-field export only, restricted |
| 4 | cnic no | cnic | text | Editable; approved transaction records are immutable | drivers.identity.view / write: drivers.identity.manage | driver_identity_details.cnic | — | Full-field export only, restricted |
| 5 | driving license no | licence_number | text | Editable; approved transaction records are immutable | drivers.identity.view / write: drivers.identity.manage | driver_identity_details.licence_number | — | Full-field export only, restricted |
| 6 | mobile no | mobile | text | Editable; approved transaction records are immutable | Module view | drivers.mobile | — | Full-field export only; office contact comes from booking.driver_contact |
| 7 | next of kin no | emergency_contact | text | Editable; approved transaction records are immutable | drivers.identity.view / write: drivers.identity.manage | driver_identity_details.emergency_contact | — | Full-field export only, restricted |
| 8 | joining date | joining_date | date | Editable; approved transaction records are immutable | Module view | drivers.joining_date | — | Combined Joining Date |
| 9 | leaving date | leaving_date | date | Editable; approved transaction records are immutable | Module view | drivers.leaving_date | — | Full-field export only |
| 10 | adress | address | textarea | Editable; approved transaction records are immutable | drivers.identity.view / write: drivers.identity.manage | driver_identity_details.address | — | Full-field export only, restricted |
| 11 | tool | tolls | decimal | Calculated, read-only | reports.financial.view | period approved expense_entries | — | Monthly TOLL PLAZA; cycle Toll Plaza; driver tool |
| 12 | pp | fines_permits | decimal | Calculated, read-only | reports.financial.view | period approved expense_entries | — | Monthly CHALLAN; cycle Chln; driver punjab police challan |
| 13 | liter | litres | decimal | Calculated, read-only | Module view | matched period fuel litres | liter /km=ave | Monthly second DESEL (measured matched basis); driver efficiency context |
| 14 | km | total_km | decimal | Calculated, read-only | Module view | matched period distance | liter /km=ave | Cycle Travl (km); monthly KM (measured matched basis); driver distance context |
| 15 | ave | average | decimal | Calculated, read-only | Module view | matched distance / litres (one basis) | liter /km=ave | Cycle Avg Km/L (2 decimals); monthly AVE (4 decimals); driver ave |
| 16 | weight | weight | decimal | Calculated, read-only | Module view | approved trip weight in metric tonnes | — | Monthly WEGHT; supplementary driver weight |
| 17 | cycle | cycles | decimal | Calculated, read-only | Module view | count approved completed trips | — | Monthly chaker; supplementary driver cycle |
| 18 | loan taken | loan_taken | decimal | Calculated, read-only | loans.view | opening + disbursements through cutoff | loan taken. . . loan paid ....loan left | Combined Total Loan |
| 19 | loan paid | loan_paid | decimal | Calculated, read-only | loans.view | repayments through cutoff | loan taken. . . loan paid ....loan left | Combined Loan Return |
| 20 | loan left | loan_left | decimal | Calculated, read-only | loans.view | taken - paid through cutoff | loan taken. . . loan paid ....loan left | Combined Loan left |

## Trip

| Position | Literal label | Key | Type | Editable / calculated | Permission | Source | Group | Reference-format mapping |
|---|---|---|---|---|---|---|---|---|
| 1 | date | business_date | date | Editable; approved transaction records are immutable | Module view | trips.business_date | — | Cycle Date |
| 2 | vehical | vehicle_id | lookup | Editable; approved transaction records are immutable | Module view | trips.vehicle_id | — | Resolved vehicle registration in identification/oil/monthly/office |
| 3 | driver | driver_id | lookup | Editable; approved transaction records are immutable | Module view | trips.driver_id | — | Resolved name in cycle/report identification |
| 4 | cycle no | cycle_number | text | Editable; approved transaction records are immutable | Module view | trips.cycle_number | — | Full-field export only; printed Cycle uses historical route descriptions |
| 5 | fair | fare | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_financials.fare | — | Cycle Fare; supplementary Sale; canonical gross-fare reconciliation |
| 6 | desel | diesel | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.diesel | — | Cycle Diesel (Price); monthly first DESEL (cost) |
| 7 | tool | tolls | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.tolls | — | Monthly TOLL PLAZA; cycle Toll Plaza; driver tool |
| 8 | pp | fines_permits | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.fines_permits | — | Monthly CHALLAN; cycle Chln; driver punjab police challan |
| 9 | food | food | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.food | — | Cycle Food |
| 10 | inam | reward | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.reward | — | Cycle inm |
| 11 | servise | service | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.service | — | Included in cycle Other Exp. |
| 12 | parking | parking | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.parking | — | Included in cycle Other Exp. |
| 13 | mobil oil | engine_oil | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.engine_oil | — | Cycle Mobil Oil |
| 14 | other expense | other | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.other | — | Included in cycle Other Exp. |
| 15 | driver cycle com | commission | decimal | Editable; approved transaction records are immutable | trips.finance.view / write: trips.finance.view | trip_expense_lines.commission | — | Cycle Driver com; monthly DRIVER. COMM.; settlement Driver Commission |
| 16 | total expense | total_expense | decimal | Calculated, read-only | trips.finance.view | sum of ten categories | — | Cycle Total Exp.; supplementary expense |
| 17 | profit | profit | decimal | Calculated, read-only | trips.finance.view | fare - total expense | — | Cycle Profit Loss; supplementary profit; not assumed equivalent to monthly INCOME |
| 18 | start km | start_odometer | decimal | Editable; approved transaction records are immutable | Module view | trips.start_odometer | start km - end km=total km - liter=average | Combined Start Meter source |
| 19 | end km | end_odometer | decimal | Editable; approved transaction records are immutable | Module view | trips.end_odometer | start km - end km=total km - liter=average | Combined Close Meter source; historical closing-meter observations |
| 20 | total km | total_km | decimal | Calculated, read-only | Module view | end - start | start km - end km=total km - liter=average | Cycle Travl (km); monthly KM (measured matched basis); driver distance context |
| 21 | liter | fuel_litres | decimal | Editable; approved transaction records are immutable | Module view | trips.fuel_litres | start km - end km=total km - liter=average | Cycle Diesel (Ltr); monthly matched measured litres |
| 22 | average | average | decimal | Calculated, read-only | Module view | distance / litres | start km - end km=total km - liter=average | Cycle Avg Km/L (2 decimals); monthly AVE (4 decimals); driver ave |
| 23 | weight | weight | decimal | Editable; approved transaction records are immutable | Module view | trips.weight (existing unit retained; new: metric tonnes) | — | Monthly WEGHT; supplementary driver weight |
| 24 | remarks | remarks | textarea | Editable; approved transaction records are immutable | Module view | trips.remarks | — | Driver supplementary remarks where applicable; full-field register |

## Maintnence

| Position | Literal label | Key | Type | Editable / calculated | Permission | Source | Group | Reference-format mapping |
|---|---|---|---|---|---|---|---|---|
| 1 | vehical | vehicle_id | lookup | Editable; approved transaction records are immutable | Module view | maintenance_records.vehicle_id | — | Resolved vehicle registration in identification/oil/monthly/office |
| 2 | driver | driver_id | lookup | Editable; approved transaction records are immutable | Module view | maintenance_records.driver_id | — | Resolved name in cycle/report identification |
| 3 | engine | engine | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.engine | — | ENGINE descriptive panel; no price parsed from text |
| 4 | gear | gearbox | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.gearbox | — | GEAR descriptive panel |
| 5 | hissa | parts | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.parts | — | Full-field export only |
| 6 | tyre | tyres | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.tyres | — | TYRES descriptive panel |
| 7 | electrion wiring | wiring | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.wiring | — | Full-field export only |
| 8 | elec self | starter | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.starter | — | Full-field export only |
| 9 | elec genrater | alternator | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.alternator | — | Full-field export only |
| 10 | elec lighting | lighting | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.lighting | — | Full-field export only |
| 11 | cabin | cabin | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.cabin | — | BODY / CABIN descriptive panel, stored separately |
| 12 | body | body | textarea | Editable; approved transaction records are immutable | Module view | maintenance_components.body | — | BODY / CABIN descriptive panel, stored separately |

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
