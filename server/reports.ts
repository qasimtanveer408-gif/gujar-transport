import {Router} from 'express';
import {z} from 'zod';
import ExcelJS from 'exceljs';
import {existsSync} from 'node:fs';
import {resolve} from 'node:path';
import type {AuthContext} from './session.js';
import {AppError,dbError} from './errors.js';
import {csv,safeCell} from '../shared/calculations.js';
import {modules} from '../shared/modules.js';
const query=z.object({kind:z.string().max(40),from:z.string().regex(/^\d{4}-\d{2}-\d{2}$/),to:z.string().regex(/^\d{4}-\d{2}-\d{2}$/),vehicle:z.string().uuid().optional(),driver:z.string().uuid().optional(),format:z.enum(['json','csv','xlsx']).default('json')});
export function reportsRouter(){const router=Router();router.get('/reports',async(req,res)=>{
 const q=query.parse(req.query),auth=res.locals.auth as AuthContext;
 const permission=q.kind==='monthly-accounts'||['revenue','expenses','cash'].includes(q.kind)?'reports.financial.view':q.kind==='loan-transactions'?'loans.view':modules[q.kind]?.permission;
 if(!permission||!auth.access.permissions.includes(permission))throw new AppError(403,'FORBIDDEN','This report is not available to your account.');
 if(!auth.access.permissions.includes('reports.export'))throw new AppError(403,'FORBIDDEN','Report export permission is required.');
 const result=q.kind==='monthly-accounts'?await auth.db.rpc('monthly_accounts',{p_from:q.from,p_to:q.to,p_basis:'measured'}):await auth.db.rpc('export_records',{p_resource:q.kind,p_from:q.from,p_to:q.to,p_vehicle:q.vehicle??null,p_driver:q.driver??null});dbError(result.error);
 const rows=(q.kind==='monthly-accounts'?result.data.rows:result.data) as Record<string,unknown>[];
 const settings=await auth.db.from('business_settings').select('business_name,contact_email,phone_1,phone_2,phone_3,currency,timezone').single();dbError(settings.error);
 const metadata={...settings.data,from:q.from,to:q.to,kind:q.kind,generated_at:new Date().toISOString(),basis:q.kind==='monthly-accounts'?'measured':undefined,unallocated_overhead:q.kind==='monthly-accounts'?result.data.unallocated_overhead:undefined};
 if(q.format==='json'){res.json({rows,metadata});return;}
 const columns=rows.length?Object.keys(rows[0]):['No records'];const name=`gujjar-${q.kind}-${q.from}-${q.to}.${q.format}`;
 res.setHeader('Content-Disposition',`attachment; filename="${name}"`);
 if(q.format==='csv'){res.type('text/csv; charset=utf-8');const intro=csv([{...metadata}],Object.keys(metadata));res.send(intro+'\r\n\r\n'+csv(rows,columns).replace(/^\uFEFF/,''));return;}
 const workbook=new ExcelJS.Workbook();workbook.creator='Gujjar Brother Transport';workbook.created=new Date();const sheet=workbook.addWorksheet('Report');
 sheet.addRow([String(metadata.business_name)]);sheet.addRow([String(metadata.contact_email),String(metadata.phone_1),String(metadata.phone_2),String(metadata.phone_3)]);sheet.addRow([q.kind,q.from,q.to,'PKR',metadata.generated_at]);if(metadata.unallocated_overhead!==undefined)sheet.addRow(['Unallocated overhead (PKR)',String(metadata.unallocated_overhead)]);sheet.addRow([]);
 const header=sheet.addRow(columns);header.font={bold:true};header.fill={type:'pattern',pattern:'solid',fgColor:{argb:'FFECEFF2'}};
 for(const row of rows)sheet.addRow(columns.map(key=>safeCell(row[key])));
 sheet.columns.forEach(column=>{column.width=23;});sheet.getRow(1).font={bold:true,size:16};
 const logo=workbook.addImage({filename:resolve(existsSync('dist/client/brand/logo.png')?'dist/client/brand/logo.png':'client/public/brand/logo.png'),extension:'png'});sheet.addImage(logo,{tl:{col:Math.max(columns.length,5),row:0},ext:{width:95,height:95}});
 sheet.views=[{state:'frozen',ySplit:header.number}];sheet.autoFilter={from:{row:header.number,column:1},to:{row:header.number,column:columns.length}};
 res.type('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');await workbook.xlsx.write(res);res.end();
});return router;}
