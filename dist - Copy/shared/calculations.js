import { Decimal } from 'decimal.js';
import { normalizeDecimalInput } from './numeric-input.js';
Decimal.set({ precision: 32, rounding: Decimal.ROUND_HALF_UP });
function finiteDecimal(value) { const parsed = new Decimal(String(normalizeDecimalInput(value))); if (!parsed.isFinite())
    throw new Error('Enter a finite numeric value'); return parsed; }
export function tripPreview(fare, expenses, start, end, litres) {
    const distance = finiteDecimal(end).minus(finiteDecimal(start));
    if (distance.isNegative())
        throw new Error('End odometer must not be below start odometer');
    const total = expenses.reduce((a, b) => a.plus(finiteDecimal(b)), new Decimal(0));
    const fuel = litres ? finiteDecimal(litres) : null;
    return { distance: distance.toFixed(3), expenses: total.toFixed(2), profit: finiteDecimal(fare).minus(total).toFixed(2), efficiency: fuel?.gt(0) ? distance.div(fuel).toFixed(2) : null };
}
export function pooledEfficiency(rows, basis) {
    const matched = rows.filter(r => { try {
        return r.basis === basis && r.litres && finiteDecimal(r.litres).gt(0) && finiteDecimal(r.distance).gte(0);
    }
    catch {
        return false;
    } });
    const distance = matched.reduce((a, b) => a.plus(finiteDecimal(b.distance)), new Decimal(0)), litres = matched.reduce((a, b) => a.plus(finiteDecimal(b.litres)), new Decimal(0));
    return { distance: distance.toFixed(3), litres: litres.toFixed(3), efficiency: litres.gt(0) ? distance.div(litres).toFixed(2) : null, count: matched.length };
}
/** Select the highest existing pooled efficiency from the dashboard's filtered ranking. */
export function topAverageVehicle(rows) {
    let top = null, best = null;
    for (const row of rows) {
        if (row.efficiency === null || row.efficiency === undefined || row.efficiency === '')
            continue;
        try {
            const average = finiteDecimal(String(row.efficiency));
            if (average.gte(0) && (!best || average.gt(best))) {
                top = row;
                best = average;
            }
        }
        catch { /* Ignore unavailable averages. */ }
    }
    return top;
}
export function businessDate(timestamp = new Date()) { return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Karachi', year: 'numeric', month: '2-digit', day: '2-digit' }).format(timestamp); }
export function safeCell(value) { const s = value == null ? '' : String(value); return /^[\s]*[=+@-]/.test(s) ? `'${s}` : s; }
export function csv(rows, columns) { const quote = (s) => '"' + safeCell(s).replaceAll('"', '""') + '"'; return '\uFEFF' + [columns.map(quote).join(','), ...rows.map(row => columns.map(k => quote(row[k])).join(','))].join('\r\n'); }
