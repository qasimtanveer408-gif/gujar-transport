import ExcelJS from 'exceljs';
import PDFDocument from 'pdfkit';
import { Decimal } from 'decimal.js';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
export const logoPath = () => resolve(existsSync('dist/client/brand/logo.png') ? 'dist/client/brand/logo.png' : 'client/public/brand/logo.png');
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
function formatted(v, c, blank = false) { if (v == null || v === '')
    return blank ? '' : '—'; if (c.type === 'date' && /^\d{4}-\d{2}-\d{2}/.test(String(v)))
    return String(v).slice(0, 10).split('-').reverse().join('/'); if ((c.type === 'money' || c.type === 'number') && /^-?\d+(\.\d+)?$/.test(String(v)))
    return new Decimal(String(v)).toFixed(c.decimals ?? (c.type === 'money' ? 2 : 3)); return String(v); }
function decorate(doc) { if (!doc.sections.some(s => s.role === 'signature'))
    doc = { ...doc, sections: [...doc.sections, { title: '', role: 'signature', columns: [{ key: 'signature', label: 'Signature' }], rows: [{}] }] }; if (doc.kind !== 'monthly')
    return doc; const first = doc.sections[0], columns = [...first.columns]; columns.splice(7, 0, { key: '_brand', label: 'GBT', type: 'text', width: .6 }); return { ...doc, sections: [{ ...first, columns, rows: first.rows.map((r, i) => ({ ...r, _brand: i === 0 ? 'G\nB\nT' : '' })) }, ...doc.sections.slice(1)] }; }
function htmlTable(s) { const daily = ['date', 'total', 'description', 'bill', 'profit']; return `<section class="section ${s.role ?? ''} ${s.columns.length > 16 ? 'dense' : ''}"><h3>${esc(s.title)}</h3><table><colgroup>${s.columns.map(c => `<col style="width:${100 * (c.width ?? 1) / s.columns.reduce((n, x) => n + (x.width ?? 1), 0)}%">`).join('')}</colgroup><thead><tr>${s.columns.map(c => `<th>${esc(c.label)}</th>`).join('')}</tr></thead><tbody>${(s.rows.length ? s.rows : [{}]).map((r, i) => `<tr>${s.columns.map(c => { const grouped = r._day && daily.includes(c.key); if (grouped && i && s.rows[i - 1]._day === r._day)
    return ''; let span = 1; if (grouped)
    while (s.rows[i + span]?._day === r._day)
        span++; return `<td rowspan="${span}" class="${c.type === 'money' || c.type === 'number' ? 'numeric' : ''}">${s.role === 'signature' ? '<div class="sign-space"></div><p>Signature: __________________</p><p>Name: ____________________</p><p>Date: _____________________</p>' : esc(formatted(r[c.key], c, false))}</td>`; }).join('')}</tr>`).join('')}</tbody>${s.total ? `<tfoot><tr>${s.columns.map(c => `<td>${esc(formatted(s.total[c.key], c, true))}</td>`).join('')}</tr></tfoot>` : ''}</table>${s.role === 'chart' ? htmlGraph(s) : ''}${!s.rows.length ? '<p class="empty">No matching records</p>' : ''}</section>`; }
function htmlGraph(s) { const max = Math.max(1, ...s.rows.map(r => Math.abs(Number(r.profit ?? 0)))); return `<div class="graph" aria-label="Recorded profit by trip">${s.rows.map(r => `<div style="display:flex;gap:10px;margin:6px"><span>${esc(r.date)}</span><span style="display:block;background:${Number(r.profit) < 0 ? '#555' : '#999'};width:${Math.abs(Number(r.profit ?? 0)) / max * 70}%;min-width:1px">${esc(r.profit)} PKR</span></div>`).join('')}</div>`; }
export function reportHtml(doc) {
    doc = decorate(doc);
    const m = doc.metadata;
    const first = doc.sections.findIndex(s => s.role === 'maintenance'), cycle = doc.sections.findIndex(s => s.role === 'cycles');
    let sections = '';
    for (let i = 0; i < doc.sections.length; i++) {
        if (i === cycle)
            continue;
        if (doc.sections[i].role === 'component') {
            const group = doc.sections.slice(i, i + 4);
            sections += `<div class="component-grid">${group.map(htmlTable).join('')}</div>`;
            i += group.length - 1;
            continue;
        }
        if (i === first && cycle >= 0)
            sections += `<div class="combined-top">${htmlTable(doc.sections[first])}${htmlTable(doc.sections[cycle])}</div>`;
        else
            sections += htmlTable(doc.sections[i]);
    }
    return `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>${esc(doc.title)}</title><style>@page{size:${doc.paper} ${doc.orientation ?? 'landscape'};margin:10mm}*{box-sizing:border-box}body{font-family:Arial,sans-serif;font-size:${doc.paper === 'A3' ? 10 : 11}px;color:#111;margin:16px}header{display:flex;align-items:center;gap:16px;margin-bottom:10px}header img{width:60px;height:60px;object-fit:contain}h1{background:#333;color:white;text-align:center;font-family:Georgia,serif;font-size:25px;padding:12px;margin:0}.period{text-align:center;background:#ddd;font-weight:bold;padding:9px;font-size:16px}.meta{font-size:10px}.warning{border:2px solid #444;padding:8px}.section{margin:12px 0;break-inside:auto}.section h3{font-size:12px;text-align:center;background:#ddd;margin:0;padding:6px}.section h3:empty{display:none}table{width:100%;border-collapse:collapse;table-layout:fixed}th,td{border:1px solid #555;padding:5px 4px;overflow-wrap:anywhere;vertical-align:top}th{background:#d2d2d2;text-align:center}thead{display:table-header-group}tfoot{display:table-row-group;font-weight:bold;background:#eee}tr{break-inside:avoid}.numeric{text-align:right;font-variant-numeric:tabular-nums}.signature{break-inside:avoid}.signature td{height:105px}.signature p{margin:7px 0;font-size:9px}.sign-space{height:24px}.dense th,.dense td{font-size:9px;padding:4px 2px}.dense .numeric{white-space:normal;overflow-wrap:anywhere}.component-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:4px}.combined-top{display:grid;grid-template-columns:minmax(0,27fr) minmax(0,73fr);gap:4px}.combined-top th,.combined-top td{font-size:9px;padding:4px 2px}.empty{font-style:italic}.notes{font-size:10px;line-height:1.5}.report-footer{border-top:1px solid #999;padding-top:7px;margin-top:16px;color:#555;font-size:9px;text-align:right;break-inside:avoid}.summary{break-inside:avoid}.component{break-inside:auto}@media screen{body{min-width:${doc.paper === 'A3' ? 1300 : 950}px;max-width:1800px;margin:20px auto}}@media print{body{margin:0;-webkit-print-color-adjust:exact;print-color-adjust:exact}.no-print{display:none}}</style></head><body><header><img src="/brand/logo.png" width="60" height="60" alt="Business logo"><div><strong>${esc(m.business_name)}</strong><br>${esc(m.contact_email)} · ${esc(m.phone_1)} · ${esc(m.phone_2)} · ${esc(m.phone_3)}<br><span class="meta">PKR · Asia/Karachi · Generated ${esc(m.generated_at)}</span></div></header><h1>${esc(doc.title)}</h1><div class="period">${esc(m.period_label)} · ${esc(m.from)} to ${esc(m.to)}</div>${doc.incomplete ? '<p class="warning"><strong>INCOMPLETE — review missing sources before finalizing.</strong></p>' : ''}${sections}<div class="notes">${doc.notes.map(n => `<p>${esc(n)}</p>`).join('')}</div><footer class="report-footer">${esc(m.business_name)} · Generated ${esc(m.generated_at)} · PKR · Asia/Karachi</footer></body></html>`;
}
export function excelValue(v, c) { if (v == null || v === '')
    return null; if (c.type === 'date' && /^\d{4}-\d{2}-\d{2}/.test(String(v)))
    return new Date(String(v).slice(0, 10) + 'T00:00:00Z'); if ((c.type === 'money' || c.type === 'number') && /^-?\d+(\.\d+)?$/.test(String(v))) {
    const d = new Decimal(String(v)), n = d.toNumber();
    if (!new Decimal(String(n)).eq(d))
        throw new Error('A value exceeds lossless Excel numeric precision; use CSV for this dataset.');
    return n;
} const s = String(v); return /^\s*[=+@-]/.test(s) ? "'" + s : s; }
const border = { top: { style: 'thin', color: { argb: 'FF555555' } }, bottom: { style: 'thin', color: { argb: 'FF555555' } }, left: { style: 'thin', color: { argb: 'FF555555' } }, right: { style: 'thin', color: { argb: 'FF555555' } } };
export function reportWorkbook(doc) {
    doc = decorate(doc);
    const book = new ExcelJS.Workbook();
    book.creator = 'Gujjar Brother Transport';
    const s = book.addWorksheet('Report', { pageSetup: { paperSize: (doc.paper === 'A3' ? 8 : 9), orientation: doc.orientation ?? 'landscape', fitToPage: true, fitToWidth: 1, fitToHeight: 0, horizontalCentered: true, margins: { left: .25, right: .25, top: .3, bottom: .3, header: .1, footer: .1 } } });
    for (let i = 1; i <= 84; i++)
        s.getColumn(i).width = doc.paper === 'A3' ? 1.9 : 1.35;
    const write = (row, col, end, value, fill, bold = false) => { if (end > col)
        s.mergeCells(row, col, row, end); const cell = s.getCell(row, col); cell.value = value; cell.font = { name: 'Arial', size: 10, bold, color: { argb: fill === 'FF333333' ? 'FFFFFFFF' : 'FF111111' } }; cell.alignment = { vertical: 'middle', wrapText: true }; for (let k = col; k <= end; k++) {
        s.getCell(row, k).border = border;
        if (fill)
            s.getCell(row, k).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: fill } };
    } return cell; };
    write(1, 1, 84, String(doc.metadata.business_name), 'FF333333', true);
    s.getRow(1).height = 30;
    write(2, 1, 84, `${doc.metadata.contact_email} · ${doc.metadata.phone_1} · ${doc.metadata.phone_2} · ${doc.metadata.phone_3}`);
    write(3, 1, 84, doc.kind === 'office' ? doc.title : `${doc.title} · ${doc.metadata.period_label}`, 'FFD2D2D2', true);
    s.getRow(3).height = 28;
    write(4, 1, 84, `${doc.metadata.from} to ${doc.metadata.to} · PKR · ${doc.metadata.generated_at}`);
    write(5, 1, 84, doc.incomplete ? 'INCOMPLETE — missing mappings/sources; review notes.' : 'Selected authorized records', 'FFEEEEEE');
    s.getRow(5).height = 26;
    let row = 7;
    const table = (section, start, left = 1, span = 84) => { let r = start; write(r, left, left + span - 1, section.title, 'FFD2D2D2', true); s.getRow(r++).height = 22; const total = section.columns.reduce((a, c) => a + (c.width ?? 1), 0); let cum = 0; const slots = section.columns.map((c, i) => { const a = left + Math.round(cum / total * span); cum += c.width ?? 1; return { c, a, b: i === section.columns.length - 1 ? left + span - 1 : left + Math.round(cum / total * span) - 1 }; }); for (const { c, a, b } of slots)
        write(r, a, b, c.label, 'FFD2D2D2', true); s.getRow(r++).height = 45; const bodyStart = r; const values = section.rows.length ? section.rows : [{}]; for (const data of [...values, ...(section.total ? [section.total] : [])]) {
        let height = section.role === 'signature' ? 85 : 24;
        for (const { c, a, b } of slots) {
            const val = section.role === 'signature' ? 'Signature: __________________\nName: ____________________\nDate: _____________________' : excelValue(data[c.key], c), cell = write(r, a, b, val, data === section.total ? 'FFEEEEEE' : undefined, data === section.total);
            cell.numFmt = c.type === 'date' ? 'dd/mm/yyyy' : c.type === 'money' ? '#,##0.00;[Red]-#,##0.00' : c.type === 'number' ? '0' + ((c.decimals ?? 3) ? '.' + '0'.repeat(c.decimals ?? 3) : '') : '@';
            height = Math.max(height, Math.ceil(formatted(data[c.key], c, true).length / Math.max(8, (b - a + 1) * 2)) * 13);
        }
        s.getRow(r).height = Math.max(s.getRow(r).height ?? 0, Math.min(400, height));
        r++;
    } if (section.rows.some(x => x._day)) {
        let i = 0;
        while (i < section.rows.length) {
            let j = i + 1;
            while (section.rows[j]?._day === section.rows[i]._day)
                j++;
            if (j - i > 1)
                for (const { c, a, b } of slots)
                    if (['date', 'total', 'description', 'bill', 'profit'].includes(c.key)) {
                        for (let k = i; k < j; k++)
                            if (b > a)
                                s.unMergeCells(bodyStart + k, a, bodyStart + k, b);
                        s.mergeCells(bodyStart + i, a, bodyStart + j - 1, b);
                    }
            i = j;
        }
    } if (section.role === 'chart' && section.rows.length) {
        const slot = slots[1];
        s.addConditionalFormatting({ ref: `${s.getColumn(slot.a).letter}${bodyStart}:${s.getColumn(slot.b).letter}${r - 1}`, rules: [{ type: 'dataBar', priority: 1, cfvo: [{ type: 'min' }, { type: 'max' }], showValue: true, axisPosition: 'middle', gradient: false }] });
    } return r + 1; };
    for (let i = 0; i < doc.sections.length; i++) {
        const section = doc.sections[i];
        if (section.role === 'component') {
            const top = row;
            let end = row;
            for (let k = 0; k < 4 && doc.sections[i + k]?.role === 'component'; k++)
                end = Math.max(end, table(doc.sections[i + k], top, 1 + 21 * k, 21));
            row = end;
            i += 3;
        }
        else if (section.role === 'maintenance' && doc.sections[i + 1]?.role === 'cycles') {
            row = Math.max(table(section, row, 1, 24), table(doc.sections[++i], row, 25, 60));
        }
        else
            row = table(section, row);
    }
    for (const n of doc.notes) {
        write(row, 1, 84, n);
        s.getRow(row++).height = 30;
    }
    s.pageSetup.printArea = `A1:CF${row - 1}`;
    s.pageSetup.printTitlesRow = ['office', 'oil', 'monthly'].includes(doc.kind) ? '1:8' : '1:12';
    s.headerFooter.oddFooter = '&LGu jjar Brother Transport&RPAGE &P / &N'.replace('Gu jjar', 'Gujjar');
    s.views = [{ state: 'frozen', ySplit: 5 }];
    const logo = book.addImage({ filename: logoPath(), extension: 'png' });
    s.addImage(logo, { tl: { col: 80, row: 0 }, ext: { width: 40, height: 40 } });
    return book;
}
export async function reportPdf(doc) {
    doc = decorate(doc);
    return new Promise((resolveBuffer, reject) => {
        const pdf = new PDFDocument({ size: doc.paper, layout: doc.orientation ?? 'landscape', margin: 28, bufferPages: true, info: { Title: doc.title, Author: 'Gujjar Brother Transport' } }), chunks = [];
        pdf.on('data', b => chunks.push(b));
        pdf.on('end', () => resolveBuffer(Buffer.concat(chunks)));
        pdf.on('error', reject);
        const margin = 28, width = pdf.page.width - 56, bottom = () => pdf.page.height - 45;
        let y = 28;
        const fontDir = resolve(existsSync('dist/client/fonts/OpenSans-Regular.ttf') ? 'dist/client/fonts' : 'client/public/fonts');
        pdf.registerFont('Body', resolve(fontDir, 'OpenSans-Regular.ttf'));
        pdf.registerFont('Bold', resolve(fontDir, 'OpenSans-Bold.ttf'));
        const header = () => { pdf.image(logoPath(), margin, y, { fit: [44, 44] }); pdf.font('Bold').fontSize(12).fillColor('#111').text(String(doc.metadata.business_name), margin + 55, y, { width: width - 55 }); pdf.font('Body').fontSize(8).text(`${doc.metadata.contact_email} · ${doc.metadata.phone_1} · ${doc.metadata.phone_2} · ${doc.metadata.phone_3}`, margin + 55, y + 17, { width: width - 55 }); y += 51; pdf.rect(margin, y, width, 27).fill('#333'); pdf.fillColor('white').font('Bold').fontSize(17).text(doc.title, margin + 5, y + 6, { width: width - 10, align: 'center' }); y += 27; pdf.rect(margin, y, width, 22).fill('#ddd'); pdf.fillColor('#111').fontSize(10).text(`${doc.metadata.period_label} · ${doc.metadata.from} to ${doc.metadata.to} · PKR`, margin + 5, y + 6, { width: width - 10, align: 'center' }); y += 30; if (doc.incomplete) {
            pdf.fontSize(9).text('INCOMPLETE — review missing sources before finalizing.', margin, y);
            y += 18;
        } };
        header();
        const newPage = () => { pdf.addPage(); y = 28; header(); };
        const table = (section, x, w, start) => {
            let yy = start;
            const fontSize = section.columns.length > 15 ? 6.5 : 8, weight = section.columns.reduce((a, c) => a + (c.width ?? 1), 0), widths = section.columns.map(c => (c.width ?? 1) / weight * w);
            const paint = (vals, h, head = false, total = false) => { pdf.font(head || total ? 'Bold' : 'Body').fontSize(fontSize); let xx = x; for (let i = 0; i < widths.length; i++) {
                pdf.rect(xx, yy, widths[i], h).fillAndStroke(head ? '#d2d2d2' : total ? '#eee' : 'white', '#666');
                pdf.fillColor('#111');
                if (!head && ['money', 'number'].includes(section.columns[i].type ?? '')) {
                    pdf.fontSize(Math.min(fontSize, Math.max(5.5, fontSize * (widths[i] - 6) / Math.max(1, pdf.widthOfString(vals[i])))));
                }
                else
                    pdf.fontSize(fontSize);
                pdf.text(vals[i], xx + 3, yy + 4, { width: widths[i] - 6, height: h - 6, align: !head && ['money', 'number'].includes(section.columns[i].type ?? '') ? 'right' : 'left' });
                xx += widths[i];
            } yy += h; };
            const heading = () => { if (section.title) {
                pdf.rect(x, yy, w, 19).fill('#ddd');
                pdf.fillColor('#111').font('Bold').fontSize(9).text(section.title, x + 3, yy + 5, { width: w - 6, align: 'center' });
                yy += 19;
            } pdf.font('Bold').fontSize(fontSize); const labels = section.columns.map(c => c.label); paint(labels, Math.max(20, ...labels.map((v, i) => pdf.heightOfString(v, { width: widths[i] - 6 }) + 8)), true); };
            const next = () => { newPage(); yy = y; heading(); };
            heading();
            const pageCapacity = bottom() - yy;
            const positions = [];
            const prefix = (text, i, h) => { let lo = 0, hi = text.length; while (lo < hi) {
                const mid = Math.ceil((lo + hi) / 2);
                if (pdf.heightOfString(text.slice(0, mid), { width: widths[i] - 6 }) <= h)
                    lo = mid;
                else
                    hi = mid - 1;
            } const space = text.lastIndexOf(' ', lo); const cut = space > lo * .7 ? space : Math.max(1, lo); return [text.slice(0, cut), text.slice(cut).trimStart()]; };
            const draw = (r, total = false) => { let vals = section.columns.map(c => section.role === 'signature' ? '\n\nSignature: __________________\nName: ____________________\nDate: _____________________' : formatted(r[c.key], c, Boolean(r._day && r[c.key] == null))), split = false; for (;;) {
                pdf.font(total ? 'Bold' : 'Body').fontSize(fontSize);
                let h = Math.max(section.role === 'signature' ? 88 : 20, ...vals.map((v, i) => pdf.heightOfString(v, { width: widths[i] - 6 }) + 8));
                if (yy + h > bottom() && h <= pageCapacity) {
                    next();
                    pdf.font(total ? 'Bold' : 'Body').fontSize(fontSize);
                }
                let rest = [];
                if (h > bottom() - yy) {
                    if (bottom() - yy < 50) {
                        next();
                        pdf.font(total ? 'Bold' : 'Body').fontSize(fontSize);
                    }
                    const available = bottom() - yy - 10;
                    const pieces = vals.map((v, i) => prefix(v, i, available));
                    vals = pieces.map(p => p[0]);
                    rest = pieces.map(p => p[1]);
                    h = Math.max(20, ...vals.map((v, i) => pdf.heightOfString(v, { width: widths[i] - 6 }) + 8));
                    split = true;
                }
                positions.push({ row: r, y: yy, h, page: pdf.bufferedPageRange().count - 1, split });
                paint(vals, h, false, total);
                if (!rest.some(Boolean))
                    break;
                vals = rest;
                next();
            } };
            for (const r of section.rows.length ? section.rows : [{}])
                draw(r);
            if (section.total)
                draw(section.total, true);
            // Daily cells span booking rows once. Oversized days retain continuation rows.
            const last = pdf.bufferedPageRange().count - 1;
            for (let i = 0; i < positions.length;) {
                const first = positions[i];
                if (!first.row._day) {
                    i++;
                    continue;
                }
                let j = i + 1;
                while (j < positions.length && positions[j].row._day === first.row._day)
                    j++;
                const group = positions.slice(i, j);
                if (group.length > 1 && group.every(p => p.page === first.page && !p.split)) {
                    pdf.switchToPage(first.page);
                    let xx = x;
                    const h = group.reduce((a, p) => a + p.h, 0);
                    for (let k = 0; k < section.columns.length; k++) {
                        const c = section.columns[k];
                        if (['date', 'total', 'description', 'bill', 'profit'].includes(c.key)) {
                            pdf.rect(xx, first.y, widths[k], h).fillAndStroke('white', '#666');
                            pdf.font('Body').fontSize(fontSize).fillColor('#111').text(formatted(first.row[c.key], c, true), xx + 3, first.y + 4, { width: widths[k] - 6, height: h - 6, align: ['money', 'number'].includes(c.type ?? '') ? 'right' : 'left' });
                        }
                        xx += widths[k];
                    }
                }
                i = j;
            }
            pdf.switchToPage(last);
            return yy + 12;
        };
        const fits = (s, w) => { const total = s.columns.reduce((a, c) => a + (c.width ?? 1), 0), widths = s.columns.map(c => (c.width ?? 1) / total * w); pdf.font('Bold').fontSize(8); let h = (s.title ? 19 : 0) + Math.max(20, ...s.columns.map((c, i) => pdf.heightOfString(c.label, { width: widths[i] - 6 }) + 8)); pdf.font('Body').fontSize(8); for (const r of [...(s.rows.length ? s.rows : [{}]), ...(s.total ? [s.total] : [])])
            h += Math.max(20, ...s.columns.map((c, i) => pdf.heightOfString(formatted(r[c.key], c), { width: widths[i] - 6 }) + 8)); return y + h + 12 < bottom(); };
        for (let i = 0; i < doc.sections.length; i++) {
            const s = doc.sections[i];
            if (y > bottom() - (s.role === 'signature' ? 110 : 100))
                newPage();
            if (s.role === 'component' && doc.sections.slice(i, i + 4).every(x => x.role === 'component' && x.rows.length < 5 && x.rows.every(r => String(r.detail ?? '').length < 250))) {
                if (y > bottom() - 230)
                    newPage();
                const top = y;
                let end = y;
                for (let k = 0; k < 4; k++)
                    end = Math.max(end, table(doc.sections[i + k], margin + k * width / 4, width / 4 - 3, top));
                y = end;
                i += 3;
            }
            else if (s.role === 'maintenance' && doc.sections[i + 1]?.role === 'cycles' && s.rows.length <= 10 && doc.sections[i + 1].rows.length <= 10 && fits(s, width * .27 - 3) && fits(doc.sections[i + 1], width * .73)) {
                const a = table(s, margin, width * .27 - 3, y), b = table(doc.sections[++i], margin + width * .27, width * .73, y);
                y = Math.max(a, b);
            }
            else
                y = table(s, margin, width, y);
            if (s.role === 'chart' && s.rows.length) {
                const max = Math.max(1, ...s.rows.map(r => Math.abs(Number(r.profit ?? 0))));
                for (const r of s.rows) {
                    if (y > bottom() - 25)
                        newPage();
                    pdf.font('Body').fontSize(8).fillColor('#111').text(String(r.date), margin, y, { width: 85 });
                    const bar = Math.abs(Number(r.profit ?? 0)) / max * (width - 230);
                    pdf.rect(margin + 90, y, Math.max(1, bar), 13).fill(Number(r.profit) < 0 ? '#555' : '#aaa');
                    pdf.fillColor('#111').text(`${r.profit} PKR`, margin + 95 + bar, y, { width: 120 });
                    y += 20;
                }
            }
        }
        for (const note of doc.notes) {
            pdf.font('Body').fontSize(8);
            const h = pdf.heightOfString(note, { width });
            if (y + h > bottom())
                newPage();
            pdf.fillColor('#222').text(note, margin, y, { width });
            y += h + 8;
        }
        const range = pdf.bufferedPageRange();
        for (let i = 0; i < range.count; i++) {
            pdf.switchToPage(i);
            pdf.page.margins.bottom = 0;
            pdf.font('Body').fontSize(7).fillColor('#555').text(`Gujjar Brother Transport · Generated ${doc.metadata.generated_at} · Page ${i + 1} / ${range.count}`, margin, pdf.page.height - 27, { width, align: 'right', lineBreak: false });
        }
        pdf.end();
    });
}
