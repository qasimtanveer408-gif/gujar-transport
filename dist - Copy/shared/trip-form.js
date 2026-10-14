import { Decimal } from 'decimal.js';
import { expenseFields } from './form-contract.js';
import { money, numberString } from './validation.js';
import { tripPreview } from './calculations.js';
/** Keep editable strings intact and calculate independent results while typing. */
export function tripFormPreview(input) {
    const values = { ...input, total_expense: null, profit: null, total_km: null, average: null };
    const errors = {};
    function numeric(key, currency = false, emptyZero = false) {
        const raw = input[key];
        if (raw === undefined || raw === null || String(raw).trim() === '')
            return emptyZero ? '0' : null;
        const parsed = (currency ? money : numberString).safeParse(raw);
        if (!parsed.success) {
            errors[key] = parsed.error.issues[0].message;
            return null;
        }
        return parsed.data;
    }
    const expenses = expenseFields.map(([key]) => numeric(key, true, true));
    if (expenses.every((value) => value !== null))
        values.total_expense = tripPreview('0', expenses, '0', '0', null).expenses;
    const fare = numeric('fare', true);
    if (fare !== null && values.total_expense !== null)
        values.profit = new Decimal(fare).minus(String(values.total_expense)).toFixed(2);
    const start = numeric('start_odometer'), end = numeric('end_odometer'), litres = numeric('fuel_litres');
    numeric('weight');
    if (start !== null && end !== null) {
        try {
            values.total_km = tripPreview('0', [], start, end, null).distance;
        }
        catch (e) {
            errors.end_odometer = e.message;
        }
    }
    if (values.total_km !== null && litres !== null && new Decimal(litres).gt(0))
        values.average = new Decimal(String(values.total_km)).div(litres).toFixed(2);
    return { values, errors };
}
