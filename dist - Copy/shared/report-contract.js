import { Decimal } from 'decimal.js';
const c = (key, label, type = 'text', width = 1, decimals) => ({ key, label, type, width, decimals });
const sum = (rows, key) => rows.reduce((a, r) => a.plus(String(r[key] ?? 0)), new Decimal(0)).toFixed(2);
const diff = (a, b) => a == null || b == null ? null : new Decimal(String(a)).minus(String(b)).toFixed(2);
const arr = (s, k) => (s[k] ?? []);
const unavailable = 'Unavailable';
export const referenceTitles = { office: 'OFFICE', oil: 'VEHICLES OIL CHANGE RECORD', monthly: 'TRANSPORT MONTHLY ACCOUNT', combined: 'CYCLE INCOME DETAIL', 'driver-details': 'Driver Details' };
export const officeColumns = [c('date', 'Date', 'date', 1.1), c('vehicle', 'Vehicle', 'text', 1.2), c('driver', 'Driver', 'text', 1.1), c('mobile', 'Contact number', 'text', 1.35), c('cargo', 'Cargo'), c('origin', 'Origin'), c('destination', 'Destination', 'text', 1.25), c('freight', 'Freight', 'money'), c('commission', 'Commission', 'money', 1.25), c('total', 'Total', 'money'), c('description', 'Expense', 'text', 3), c('bill', 'Bill', 'money'), c('profit', 'P/L', 'money')];
export const oilColumns = [c('sn', 'S/N', 'number', .5, 0), c('registration', 'Vehicle Number'), c('previous_odometer', 'Previous Oil Change Meter (km)', 'number', 1.3, 0), c('previous_date', 'DATE', 'date'), c('odometer', 'Oil Change Meter (km)', 'number', 1.2, 0), c('date', 'DATE', 'date'), c('distance', 'Distance', 'number', 1, 0), c('closing', 'Closing Meter (km)', 'number', 1.2, 0), c('travel', 'Travel after oil change (km)', 'number', 1.5, 0), c('driver', 'DRIVER')];
export const monthlyColumns = [c('sn', 'S/N', 'number', .5, 0), c('registration', 'VEHICLE #'), c('driver', 'DRIVER'), c('income', 'INCOME', 'money'), c('fines', 'Punjab Police', 'money'), c('tolls', 'TOLL PLAZA', 'money'), c('diesel', 'DIESEL', 'money'), c('maintenance', 'MONTH MAINT.', 'money'), c('commission', 'DRIVER COMM.', 'money'), c('last_main', 'Last Main', 'money'), c('total_main', 'Total Main', 'money'), c('office', 'OFFICE EXPENSE', 'money'), c('main', 'MAIN', 'money'), c('mist', 'MIST', 'money'), c('expenses', 'TOTAL EXPENSE', 'money'), c('profit', 'PROFIT LOSS', 'money'), c('km', 'KM', 'number'), c('litres', 'DIESEL', 'number'), c('average', 'AVE', 'number', 1, 4), c('weight', 'WEIGHT', 'number'), c('cycles', 'CYCLES', 'number', 1, 0)];
export const cycleColumns = [c('business_date', 'Date', 'date'), c('route', 'Cycle', 'text', 2), c('fare', 'Fare', 'money'), c('diesel', 'Diesel (Price)', 'money'), c('fines_permits', 'Punjab Police', 'money'), c('tolls', 'Toll Plaza', 'money'), c('food', 'Food', 'money'), c('reward', 'Inam / reward', 'money'), c('other_expense', 'Other expense', 'money'), c('engine_oil', 'Engine oil', 'money'), c('commission', 'Driver cycle commission', 'money'), c('total_expense', 'Total expense', 'money'), c('profit', 'Profit / loss', 'money'), c('total_km', 'Travel (km)', 'number'), c('fuel_litres', 'Diesel (L)', 'number'), c('average', 'Average (km/L)', 'number', 1, 2)];
export const settlementColumns = [c('driver', 'Driver name'), c('driver_sale', 'Driver Sale', 'money'), c('commission', 'Driver cycle commission', 'money'), c('mobile', 'Mobile Load', 'money'), c('total', 'TOTAL', 'money'), c('absent', 'Absent', 'number'), c('call_fine', 'Call Fine', 'money'), c('advance', 'Salary Advance', 'money'), c('installment', 'Loan installment', 'money'), c('loss', 'Irresponsible Vehicle loss', 'money'), c('other', 'Other', 'money'), c('deductions', 'Total Deduction', 'money'), c('payable', 'Driver Net Payable', 'money'), c('taken', 'Total Loan', 'money'), c('paid', 'Loan repaid', 'money'), c('left', 'Loan balance', 'money')];
function totals(columns, rows) { const t = { [columns[0]?.key]: 'TOTAL' }; for (const c of columns)
    if (c.type === 'money' && rows.length && rows.every(r => r[c.key] != null))
        t[c.key] = sum(rows, c.key); return t; }
export function buildReference(kind, source, filter = {}) {
    const metadata = (source.metadata ?? {}), from = String(metadata.from), to = String(metadata.to), notes = [], sections = [];
    const doc = { kind, title: referenceTitles[kind] + (kind === 'office' ? ' -' + String(metadata.period_label ?? '') : ''), metadata, notes, sections, paper: ['monthly', 'combined'].includes(kind) ? 'A3' : 'A4', incomplete: false };
    const vehicles = arr(source, 'vehicles').filter(v => !filter.vehicle || v.id === filter.vehicle), drivers = arr(source, 'drivers'), trips = arr(source, 'trips').filter(t => t.financial_state === 'Approved' && (!filter.vehicle || t.vehicle_id === filter.vehicle) && (!filter.driver || t.driver_id === filter.driver));
    const maintenance = arr(source, 'maintenance').filter(m => !filter.vehicle || m.vehicle_id === filter.vehicle), inPeriod = (r, key = 'business_date') => r[key] != null && String(r[key]) >= from && String(r[key]) <= to;
    const note = (s) => { if (!notes.includes(s))
        notes.push(s); doc.incomplete = true; };
    if (kind === 'office') {
        const bookings = arr(source, 'bookings').filter(b => b.state === 'Approved'), expenses = arr(source, 'office').filter(e => e.state === 'Approved' && e.vehicle_id == null), allTrips = arr(source, 'trips');
        const dates = [...new Set([...bookings, ...expenses].map(r => String(r.business_date)))].sort(), rows = [];
        for (const date of dates) {
            const b = bookings.filter(x => x.business_date === date), e = expenses.filter(x => x.business_date === date), total = sum(b, 'commission'), bill = sum(e, 'amount');
            const list = b.length ? b : [{}];
            list.forEach((x, i) => { const trip = allTrips.find(t => t.id === x.trip_id); rows.push({ date: i === 0 ? date : null, vehicle: x.external_vehicle ?? trip?.vehicle_id_label, driver: trip?.driver_id_label ?? null, mobile: x.driver_contact, cargo: x.cargo, origin: x.origin, destination: x.destination, freight: x.quoted_freight, commission: x.commission, total: i === 0 ? total : null, description: i === 0 ? e.map(x => `${x.description} (${x.amount})`).join('; ') : null, bill: i === 0 ? bill : null, profit: i === 0 ? diff(total, bill) : null, _day: date }); });
        }
        sections.push({ title: '', columns: officeColumns, rows, total: { date: 'PERIOD TOTAL', commission: sum(bookings, 'commission'), total: sum(bookings, 'commission'), bill: sum(expenses, 'amount'), profit: diff(sum(bookings, 'commission'), sum(expenses, 'amount')) } });
        notes.push('com = approved brokerage commission; total = daily commission; Bill = unallocated approved office expenses once per day; P/L = total − Bill. Quoted freight is not recognized brokerage revenue.');
        if (bookings.some(b => !b.trip_id))
            note('External driver names have no separate verified source; left unavailable. Existing driver_contact is displayed under Mobile-no pending confirmation of its contents.');
    }
    else if (kind === 'oil') {
        const rows = vehicles.map((v, i) => { const changes = arr(source, 'oil').filter(o => o.vehicle_id === v.id && o.date != null && String(o.date) <= to).sort((a, b) => String(a.date).localeCompare(String(b.date))), last = changes.at(-1), previous = changes.at(-2); const readings = [...arr(source, 'closing_readings'), ...changes.map(o => ({ ...o }))].filter(r => r.vehicle_id === v.id && r.odometer != null && String(r.date) <= to).sort((a, b) => String(a.date).localeCompare(String(b.date)) || new Decimal(String(a.odometer)).cmp(String(b.odometer))), closing = readings.at(-1)?.odometer; const prev = last?.previous_odometer ?? previous?.odometer, prevDate = last?.previous_date ?? previous?.date; let distance = diff(last?.odometer, prev), travel = diff(closing, last?.odometer); if (distance != null && new Decimal(distance).lt(0) || prevDate != null && last?.date != null && String(prevDate) > String(last.date)) {
            distance = null;
            note('Invalid previous oil-change date/reading found; difference withheld for review.');
        } if (travel != null && new Decimal(travel).lt(0)) {
            travel = null;
            note('Closing meter precedes oil-change meter; travel withheld for review.');
        } if (!last || closing == null || prev == null)
            note('Some vehicles lack verified oil history or closing readings as of the cutoff.'); return { sn: i + 1, registration: v.registration, previous_odometer: prev, previous_date: prevDate, odometer: last?.odometer, date: last?.date, distance, closing, travel, driver: drivers.find(d => d.id === last?.driver_id)?.full_name }; });
        sections.push({ title: '', columns: oilColumns, rows });
        notes.push('One row per vehicle: latest approved oil change through period end; previous stored reading or preceding approved change. Closing meter uses dated approved trip/maintenance observations through the cutoff, never today’s vehicle meter.');
    }
    else if (kind === 'monthly') {
        const rows = vehicles.map((v, i) => { const ts = trips.filter(t => t.vehicle_id === v.id), es = arr(source, 'expenses').filter(e => e.vehicle_id === v.id), fuel = ts.filter(t => t.fuel_basis === 'measured' && Number(t.fuel_litres) > 0 && t.operational_state === 'Completed'), distance = sum(fuel, 'total_km'), litres = sum(fuel, 'fuel_litres'); return { sn: i + 1, registration: v.registration, driver: [...new Set(ts.map(t => t.driver_id_label).filter(Boolean))].join(', '), income: null, fines: sum(es.filter(e => e.category === 'fines_permits'), 'amount'), tolls: sum(es.filter(e => e.category === 'tolls'), 'amount'), diesel: sum(es.filter(e => e.category === 'diesel'), 'amount'), maintenance: sum(es.filter(e => e.maintenance_item_id), 'amount'), commission: sum(es.filter(e => e.category === 'commission' && !e.maintenance_item_id), 'amount'), last_main: null, total_main: null, office: sum(es.filter(e => e.office_expense_id), 'amount'), main: null, mist: null, expenses: sum(es, 'amount'), profit: null, km: distance, litres, average: new Decimal(litres).gt(0) ? new Decimal(distance).div(litres).toFixed(4) : null, weight: ts.reduce((a, t) => a.plus(new Decimal(String(t.weight ?? 0)).div(t.weight_unit === 'kg' ? 1000 : 1)), new Decimal(0)).toFixed(3), cycles: ts.filter(t => t.operational_state === 'Completed').length }; });
        sections.push({ title: '', columns: monthlyColumns, rows, total: totals(monthlyColumns, rows) });
        const mc = [c('total', 'Total Sale', 'money'), c('percent', 'In the Name of Allah', 'number'), c('amount', 'Amount', 'money'), c('net', 'Net Sale', 'money')];
        sections.push({ title: 'Total / net sale and percentage adjustment', role: 'summary', columns: mc, rows: [{}] });
        sections.push({ title: 'Profit / share allocation', columns: [c('profit', 'TOTAL PROFIT/LOSS', 'money'), c('shares', 'SHARES', 'number'), c('share', '1 SHARE =', 'money'), c('allocation', 'Allocation')], rows: [{}] });
        sections.push({ title: 'MONTH WISE INCOME COMPARISON', role: 'comparison', columns: [c('period', 'Period'), c('sale', 'Sale', 'money'), c('expense', 'Expense', 'money'), c('result', 'Result', 'money')], rows: [{ period: unavailable }] });
        sections.push({ title: '', role: 'signature', columns: [c('manager', 'MANAGER SIGN'), c('ceo', 'C.E.O SIGN')], rows: [{}] });
        const rev = arr(source, 'revenue'), exp = arr(source, 'expenses');
        sections.push({ title: 'Canonical reconciliation (separate from unconfirmed printed subtotals)', columns: [c('fare', 'Gross recognized fare', 'money'), c('broker', 'Brokerage', 'money'), c('trip', 'Trip expense', 'money'), c('monthly', 'Other current costs', 'money'), c('overhead', 'Unallocated overhead', 'money'), c('profit', 'Operating profit', 'money'), c('trip_result', 'Trip result', 'money'), c('carried', 'Carried balances', 'money'), c('final', 'Printed final result', 'money')], rows: [{ trip_result: diff(sum(trips, 'fare'), sum(trips, 'total_expense')), carried: null, final: null, fare: sum(rev.filter(x => x.kind === 'Transport'), 'amount'), broker: sum(rev.filter(x => x.kind === 'Brokerage'), 'amount'), trip: sum(exp.filter(x => x.trip_line_id), 'amount'), monthly: sum(exp.filter(x => !x.trip_line_id && x.vehicle_id), 'amount'), overhead: sum(exp.filter(x => !x.vehicle_id), 'amount'), profit: diff(sum(rev, 'amount'), sum(exp, 'amount')) }] });
        note('INCOME, Last Main, Total Main, MAIN, MIST, Total Sale and printed final PROFIT LOSS need confirmed business mappings. Percentages, shares, beneficiaries and comparison history are not configured; their slots remain blank.');
        notes.push('DIESEL before MONTH MAINT. is PKR cost; DIESEL after KM is matched measured litres. AVE uses four decimals. Carried balances are not current expenses.');
    }
    else if (kind === 'combined' || kind === 'driver-details') {
        const driver = drivers.find(d => d.id === filter.driver), vehicle = vehicles.find(v => v.id === filter.vehicle);
        if (!driver)
            note('Select one authorized driver.');
        if (!vehicle)
            note('Select one authorized vehicle.');
        const chosen = trips.filter(t => (!driver || t.driver_id === driver.id) && (!vehicle || t.vehicle_id === vehicle.id));
        sections.push({ title: 'Identification', role: 'summary', columns: [c('driver', 'Driver'), c('joining', 'Joining Date', 'date'), c('period', 'Report period'), c('vehicle', 'Vehicle'), c('advance', 'Vehicle Advance', 'money')], rows: [{ driver: driver?.full_name, joining: driver?.joining_date, period: `${metadata.period_label} (${from} to ${to})`, vehicle: vehicle?.registration }] });
        const periodMaint = maintenance.filter(m => m.state === 'Approved' && inPeriod(m) && (!vehicle || m.vehicle_id === vehicle.id));
        const mr = periodMaint.flatMap(m => arr(m, 'items').map(x => ({ date: m.business_date, detail: x.description, cost: m.category !== 'oil_change' && m.category !== 'tyres' ? x.amount : null, oil: m.category === 'oil_change' ? x.amount : null, tyre: m.category === 'tyres' ? x.amount : null })));
        const mcols = [c('date', 'Date', 'date', 1.6), c('detail', 'Detail', 'text', 3), c('cost', 'Cost', 'money'), c('oil', 'OIL', 'money'), c('tyre', 'Tyre Exp.', 'money')];
        sections.push({ title: 'VEHICLE MAINTENANCE', role: 'maintenance', columns: mcols, rows: mr, total: { date: 'TOTAL', cost: sum(mr, 'cost'), oil: sum(mr, 'oil'), tyre: sum(mr, 'tyre') } });
        const cycles = chosen.map(t => ({ ...t, route: t.route_description || (t.origin && t.destination ? `${t.origin} / ${t.destination}` : null), other_expense: new Decimal(String(t.other ?? 0)).plus(String(t.service ?? 0)).plus(String(t.parking ?? 0)).toFixed(2) }));
        sections.push({ title: 'CYCLE INCOME DETAIL', role: 'cycles', columns: cycleColumns, rows: cycles, total: totals(cycleColumns, cycles) });
        if (cycles.some(r => !r.route))
            note('Cycle report cells require verified route descriptions; cycle no is retained separately in the full-field export.');
        const readings = chosen.filter(t => t.end_odometer != null), start = readings.length ? Decimal.min(...readings.map(t => String(t.start_odometer))).toFixed(3) : null, end = readings.length ? Decimal.max(...readings.map(t => String(t.end_odometer))).toFixed(3) : null;
        sections.push({ title: 'VEHICLE SUMMARY', role: 'summary', columns: [c('start', 'Start Meter', 'number'), c('end', 'Close Meter', 'number'), c('travel', 'Total Travel', 'number'), c('maintenance', 'Monthly Maintenance', 'money'), c('commission', 'Driver cycle commission', 'money'), c('tracker', 'TRACKER', 'money'), c('expenses', 'Total Expenses', 'money'), c('sale', 'Total Sale', 'money'), c('profit', 'Profit/Loss', 'money')], rows: [{ start, end, travel: diff(end, start), maintenance: sum(mr, 'cost'), commission: sum(chosen, 'commission') }] });
        sections.push({ title: 'Driver settlement', columns: settlementColumns, rows: [{ driver: driver?.full_name, commission: sum(chosen, 'commission'), taken: driver?.loan_taken, paid: driver?.loan_paid, left: driver?.loan_left }] });
        sections.push({ title: '', role: 'signature', columns: [c('sign', 'DRIVER SIGN'), c('thumb', 'DRIVER THUMB'), c('by', 'PAID BY'), c('signed', 'SIGN'), c('date', 'PAID DATE', 'date')], rows: [{}] });
        for (const [title, categories] of [['ENGINE', ['engine']], ['GEAR', ['gearbox']], ['BODY / CABIN', ['body', 'cabin']], ['TYRES', ['tyres']]]) {
            const records = maintenance.filter(m => !vehicle || m.vehicle_id === vehicle.id);
            const rows = [];
            for (const m of records) {
                const components = (m.components ?? {});
                for (const category of categories) {
                    if (components[category])
                        rows.push({ date: m.business_date, detail: components[category], cost: null });
                    if (m.category === category && m.state === 'Approved')
                        for (const item of arr(m, 'items'))
                            rows.push({ date: m.business_date, detail: item.description, cost: item.amount });
                }
            }
            sections.push({ title, role: 'component', columns: [c('date', 'Date', 'date', 2.2), c('detail', 'Detail', 'text', 4), c('cost', 'Cost', 'money', 1.7)], rows, total: { detail: 'Total Bill', cost: rows.some(r => r.cost != null) ? sum(rows, 'cost') : null } });
        }
        sections.push({ title: '', role: 'signature', columns: [c('manager', 'GBT SIGN'), c('ceo', 'C.E.O. SIGN')], rows: [{}] });
        if (kind === 'driver-details') {
            sections.push({ title: 'Supplementary driver details', columns: [c('name', 'Driver name'), c('vehicle', 'Vehicle number'), c('sale', 'Sale', 'money'), c('expense', 'Expense', 'money'), c('profit', 'Profit', 'money'), c('tool', 'Tolls', 'money'), c('pp', 'Punjab Police', 'money'), c('average', 'Average (km/L)', 'number', 1, 2), c('weight', 'Weight (tonnes)', 'number'), c('cycles', 'Cycles', 'number', 1, 0), c('commission', 'Driver cycle commission', 'money'), c('remarks', 'Remarks')], rows: [{ name: driver?.full_name, vehicle: vehicle?.registration, sale: sum(chosen, 'fare'), expense: sum(chosen, 'total_expense'), profit: diff(sum(chosen, 'fare'), sum(chosen, 'total_expense')), tool: sum(chosen, 'tolls'), pp: sum(chosen, 'fines_permits'), average: chosen.some(t => t.fuel_basis !== chosen[0]?.fuel_basis) ? null : new Decimal(sum(chosen.filter(t => Number(t.fuel_litres) > 0), 'fuel_litres')).gt(0) ? new Decimal(sum(chosen.filter(t => Number(t.fuel_litres) > 0), 'total_km')).div(sum(chosen.filter(t => Number(t.fuel_litres) > 0), 'fuel_litres')).toFixed(2) : null, weight: chosen.reduce((a, t) => a.plus(new Decimal(String(t.weight ?? 0)).div(t.weight_unit === 'kg' ? 1000 : 1)), new Decimal(0)).toFixed(3), cycles: chosen.length, commission: sum(chosen, 'commission'), remarks: driver?.remarks }] });
            sections.push({ title: 'Recorded operating result by trip', role: 'chart', columns: [c('date', 'Date', 'date'), c('profit', 'Operating profit', 'money')], rows: chosen.map(t => ({ date: t.business_date, profit: t.profit })) });
            notes.push('Supplementary output: the handwritten sheet defines requested information, not a complete printed template.');
        }
        note('Vehicle Advance, Driver Sale, Mobile Load, deductions, tracker and printed settlement totals lack confirmed sources/calculations. Payment and signature spaces remain blank; this is not a finalized payment voucher.');
        notes.push('Other Exp. includes other + service + parking to reconcile the ten-category trip total. Loan figures are cumulative through cutoff, including opening principal. Undated component notes are current notes without an assumed historical date. Maintenance totals and component history are separate views of the same items, not additional expenses.');
    }
    else
        throw new Error('Unknown reference report');
    if (kind === 'driver-details') {
        const keep = sections.filter(s => s.title === 'Identification' || s.title === 'Supplementary driver details' || s.role === 'chart');
        sections.splice(0, sections.length, ...keep);
        sections[0].columns = sections[0].columns.filter(c => c.key !== 'advance');
        doc.incomplete = !sections[0].rows[0]?.driver || !sections[0].rows[0]?.vehicle;
        notes.splice(0, notes.length, 'Supplementary output: the handwritten sheet defines requested information, not a complete printed template.', 'Sale, expense and profit here mean recorded approved trip fare, category expense and their difference. Average divides matched distance by litres; mixed or missing fuel bases are unavailable. Fuel basis: ' + [...new Set(trips.map(t => t.fuel_basis).filter(Boolean))].join(', ') + '. Weight is in metric tonnes.');
    }
    return doc;
}
