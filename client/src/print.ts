import type {Row} from './components';
import {labels,modules,expenseLabel} from '../../shared/modules';
import {api} from './api';
export type FlatReport={rows:Row[];metadata:Row;columns?:{key:string;label:string}[]};
export const escapeHtml=(value:unknown)=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
export function registerHtml(report:FlatReport,title:string){
 const cols=report.columns??(report.rows.length?Object.keys(report.rows[0]).map(key=>({key,label:labels[key]??key.replaceAll('_',' ')})):[]),m=report.metadata;
 return `<!doctype html><html lang="en"><head><meta charset="UTF-8"><title>${escapeHtml(title)}</title><style>@page{size:A4 landscape;margin:10mm}*{box-sizing:border-box}body{font:10px Arial,sans-serif;color:#111;margin:20px}header{display:flex;align-items:center;gap:15px;margin-bottom:18px}img{width:55px}h1{font-size:22px;margin:0 0 6px}p{margin:4px 0}table{width:100%;border-collapse:collapse;table-layout:fixed}th,td{border:1px solid #888;padding:6px 4px;overflow-wrap:anywhere;vertical-align:top}th{background:#ddd}thead{display:table-header-group}tr{break-inside:avoid}.signature{margin-top:40px;padding-top:25px;break-inside:avoid}footer{margin-top:15px;color:#555}@media print{body{margin:0}}@media screen{body{min-width:1000px}}</style></head><body><header><img src="/brand/logo.png" alt=""><div><h1>${escapeHtml(m.business_name??'Gujjar Brother Transport')}</h1><strong>${escapeHtml(title)}</strong><p>${escapeHtml(m.from??'')} to ${escapeHtml(m.to??'')} · PKR · ${report.rows.length} records</p></div></header><table><thead><tr>${cols.map(c=>`<th>${escapeHtml(c.label)}</th>`).join('')}</tr></thead><tbody>${report.rows.length?report.rows.map(r=>`<tr>${cols.map(c=>`<td>${escapeHtml(['category','kind'].includes(c.key)?expenseLabel(r[c.key]):r[c.key]??'—')}</td>`).join('')}</tr>`).join(''):`<tr><td colspan="${Math.max(1,cols.length)}">No records in the selected period.</td></tr>`}</tbody></table><section class="signature"><strong>Signature:</strong><p>________________________</p></section><footer>Generated ${escapeHtml(new Date().toLocaleString('en-GB',{timeZone:'Asia/Karachi'}))} PKT · Authorized records in the selected period.</footer></body></html>`;
}
export async function printHtml(html:string):Promise<void>{
 document.querySelectorAll('iframe[data-gbt-print]').forEach(frame=>frame.remove());
 const frame=document.createElement('iframe');frame.dataset.gbtPrint='true';frame.title='Print document';frame.setAttribute('sandbox','allow-same-origin allow-modals');frame.style.cssText='position:fixed;left:-10000px;top:0;width:1400px;height:900px;border:0';
 await new Promise<void>((resolve,reject)=>{
  frame.onload=async()=>{try{const win=frame.contentWindow;if(!win)throw new Error('Print window could not be opened.');await frame.contentDocument?.fonts.ready;await Promise.all(Array.from(frame.contentDocument?.images??[]).map(img=>img.complete?Promise.resolve():new Promise<void>(r=>{img.onload=()=>r();img.onerror=()=>r();})));win.addEventListener('afterprint',()=>setTimeout(()=>frame.remove(),1000),{once:true});win.focus();win.print();resolve();}catch(e){frame.remove();reject(e);}};
  frame.srcdoc=html;document.body.appendChild(frame);
 });
}
export async function registerPreview(resource:string,from:string,to:string){const q=new URLSearchParams({kind:resource,from,to});const report=await api<FlatReport>(`/reports?${q}`);return registerHtml(report,modules[resource]?.title??resource);}
export async function printRegister(resource:string,from:string,to:string){await printHtml(await registerPreview(resource,from,to));}
