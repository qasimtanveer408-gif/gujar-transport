import { applyPrintSettings } from './record-print.js';
import { Router } from 'express';
import { z } from 'zod';
import { buildReference } from '../shared/report-contract.js';
import { reportHtml, reportPdf, reportWorkbook } from './report-render.js';
import { formDate } from './form-validation.js';
import { AppError, dbError } from './errors.js';
export function referenceReportsRouter() { const r = Router(); r.get('/reference-reports', async (req, res) => { const q = z.object({ kind: z.enum(['office', 'oil', 'monthly', 'combined', 'driver-details']), from: formDate, to: formDate, vehicle: z.string().uuid().optional(), driver: z.string().uuid().optional(), format: z.enum(['json', 'html', 'pdf', 'xlsx']).default('json') }).parse(req.query); if (q.to < q.from)
    throw new AppError(422, 'INVALID_FILTER', 'Choose a valid date range.'); const auth = res.locals.auth; const result = await auth.db.rpc('reference_dataset', { p_kind: q.kind, p_from: q.from, p_to: q.to, p_vehicle: q.vehicle ?? null, p_driver: q.driver ?? null }); dbError(result.error); const templates = await auth.db.rpc('print_templates'); dbError(templates.error); const doc = applyPrintSettings(buildReference(q.kind, result.data, { vehicle: q.vehicle, driver: q.driver }), templates.data?.find((s) => s.kind === q.kind)); if (q.format === 'json') {
    res.json(doc);
    return;
} if (q.format === 'html') {
    res.type('html').send(reportHtml(doc));
    return;
} res.setHeader('Content-Disposition', `attachment; filename="gujjar-${q.kind}-${q.from}-${q.to}.${q.format}"`); if (q.format === 'pdf') {
    res.type('application/pdf').send(await reportPdf(doc));
    return;
} res.type('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'); await reportWorkbook(doc).xlsx.write(res); res.end(); }); return r; }
