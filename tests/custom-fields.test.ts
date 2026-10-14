import test from 'node:test';
import assert from 'node:assert/strict';
import {parseFormula,evaluateNode,type CustomField} from '../shared/custom-fields.js';
import {formFixture} from './helpers/form-fixture.js';
import {recordPrintHtml,applyPrintSettings} from '../server/record-print.js';
import {registerExport,registerCsv,registerWorkbook} from '../server/register-export.js';
import type {DataRow} from '../shared/report-contract.js';

test('Bounded formula grammar handles decimals, functions and rejects executable syntax',()=>{
 for(const [formula,expected] of [['2+3*4','14'],['(2+3)*4','20'],['ROUND(-1.235,2)','-1.24'],['SUM(1,2,3)+MAX(2,4)','10'],['ABS(-3)%2','1'],['=.5 × 4','2']])assert.equal(evaluateNode(parseFormula(formula,[]).ast,{}).toString(),expected);
 assert.deepEqual(parseFormula('fare - total_expense',['fare','total_expense']).dependencies,['fare','total_expense']);
 for(const s of ['globalThis.process.exit()','constructor.constructor(1)','1;alert(1)','unknown+1','Math.random()','2**8','1e9'])assert.throws(()=>parseFormula(s,[]));
 assert.throws(()=>evaluateNode(parseFormula('2/0',[]).ast,{}),/zero/);
 assert.throws(()=>evaluateNode(parseFormula('ROUND(2,1.5)',[]).ast,{}),/precision/);
 assert.throws(()=>evaluateNode(parseFormula('quantity*2',['quantity']).ast,{quantity:null}),/quantity/);
});

test('Custom fields, calculations, permissions, printing and safe deletion use actual PostgreSQL',async t=>{
 const f=await formFixture();t.after(()=>f.db.close());
 const definitions:Record<string,CustomField>={};
 async function field(key:string,type:string,changes:DataRow={},previous?:CustomField){
  const data={resource:'trips',key,label:key.replace('cf_',''),type,default_value:null,required:false,display_order:0,show_form:true,show_card:true,show_table:true,show_print:true,hidden:false,archived:false,restricted:false,options:[],formula:'',ast:null,...changes};
  if(type==='formula'&&data.formula)data.ast=parseFormula(String(data.formula),['fare','total_expense','total_km','fuel_litres',...Object.keys(definitions),key]).ast as unknown as null;
  const id=await f.scalar<string>('select public.save_custom_field($1,$2,$3)',[previous?.id??null,previous?.version??null,JSON.stringify(data)]);
  const rows=await f.scalar<CustomField[]>('select public.custom_field_catalog($1,true)',['trips']);const saved=rows.find(x=>x.id===id)!;definitions[key]=saved;return saved;
 }
 await t.test('all input types, defaults and live formula dependencies persist after record reload',async()=>{
  await field('cf_quantity','number',{required:true});await field('cf_rate','currency',{default_value:'2.5'});
  await field('cf_total','formula',{formula:'cf_quantity * cf_rate'});await field('cf_balance','formula',{formula:'cf_total - 1.25'});
  await field('cf_note','text');await field('cf_date','date');await field('cf_checked','checkbox',{default_value:false});await field('cf_option','dropdown',{options:['One','Two']});await field('cf_percent','percentage',{default_value:'5'});
  await assert.rejects(()=>f.save('trips',f.tripData,f.trip,1),/quantity is required/);assert.equal((await f.read('trips',f.trip)).version,1);
  const values={cf_quantity:'3',cf_note:'<script>alert(1)</script>',cf_date:f.today,cf_checked:true,cf_option:'Two'};
  await f.save('trips',{...f.tripData,custom_values:values},f.trip,1);let r=await f.read('trips',f.trip);assert.equal((r.custom_values as DataRow).cf_total,'7.500000');assert.equal((r.custom_values as DataRow).cf_balance,'6.250000');assert.equal((r.custom_values as DataRow).cf_checked,true);
  await f.save('trips',{...f.tripData,custom_values:{cf_quantity:'4',cf_rate:'3.25'}},f.trip,2);r=await f.read('trips',f.trip);assert.equal((r.custom_values as DataRow).cf_total,'13.000000');assert.equal((r.custom_values as DataRow).cf_balance,'11.750000');assert.equal((r.custom_values as DataRow).cf_note,values.cf_note);
  const before=r.version;await assert.rejects(()=>f.save('trips',{...f.tripData,custom_values:{cf_option:'Not configured'}},f.trip,Number(before)),/dropdown/);assert.equal((await f.read('trips',f.trip)).version,before);
  await assert.rejects(()=>f.save('trips',{...f.tripData,custom_values:{cf_date:'2026-02-30'}},f.trip,Number(before)),/date|range/);
  await assert.rejects(()=>f.save('trips',{...f.tripData,custom_values:{cf_total:'999'}},f.trip,Number(before)),/calculated/);
  await assert.rejects(()=>f.save('trips',{...f.tripData,custom_values:{cf_fake:'999'}},f.trip,Number(before)),/Unknown/);
 });
 await t.test('zero values, divide-by-zero messages and absent values never corrupt records',async()=>{
  await field('cf_ratio','formula',{formula:'cf_total / cf_quantity'});
  let r=await f.read('trips',f.trip);await f.save('trips',{...f.tripData,custom_values:{cf_quantity:'0'}},f.trip,Number(r.version));r=await f.read('trips',f.trip);
  assert.equal((r.custom_values as DataRow).cf_total,'0.000000');assert.equal((r.custom_values as DataRow).cf_ratio,null);assert.match(String((r.custom_errors as DataRow).cf_ratio),/zero/);
  await f.save('trips',{...f.tripData,custom_values:{cf_quantity:'2'}},f.trip,Number(r.version));
 });
 await t.test('circular references, archived dependencies and nonnumeric references roll back field edits',async()=>{
  const before=definitions.cf_total;await assert.rejects(()=>field('cf_total','formula',{formula:'cf_balance + 1'},before),/Circular/);
  const rows=await f.scalar<CustomField[]>('select public.custom_field_catalog($1,true)',['trips']);assert.equal(rows.find(x=>x.key==='cf_total')!.formula,'cf_quantity * cf_rate');
  await assert.rejects(()=>field('cf_quantity','number',{archived:true},definitions.cf_quantity),/Unknown numeric field/);
  const ast={kind:'field',key:'cf_note'};await assert.rejects(()=>f.scalar('select public.save_custom_field(null,null,$1)',[JSON.stringify({resource:'trips',key:'cf_bad',label:'Bad',type:'formula',default_value:null,required:false,display_order:0,show_form:true,show_card:true,show_table:true,show_print:true,hidden:false,archived:false,restricted:false,options:[],formula:'cf_note',ast})]),/numeric field/);
 });
 await t.test('financial restrictions propagate to dependent formulas and RLS prevents disclosure',async()=>{
  await field('cf_net','formula',{formula:'fare-total_expense'});await field('cf_half','formula',{formula:'cf_net/2'});
  assert.deepEqual(definitions.cf_half.required_permissions,['trips.finance.view']);
  await f.asUser(true);const r=await f.read('trips',f.trip);assert.ok(!Object.hasOwn(r.custom_values as DataRow,'cf_net'));assert.ok(!Object.hasOwn(r.custom_values as DataRow,'cf_half'));
  const catalogue=await f.scalar<CustomField[]>('select public.custom_field_catalog($1)',['trips']);assert.ok(!catalogue.some(x=>x.key==='cf_net'));
  await assert.rejects(()=>f.scalar('select public.save_custom_field(null,null,$1)',['{}']),/Permission/);
  await assert.rejects(()=>f.db.query("select public.save_print_template('trips',1,'portrait',array['Forged'])"),/Permission/);
  await f.asUser();
 });
 await t.test('printing and typed exports include permitted custom values, escape markup and leave signatures blank',async()=>{
  const r=await f.read('trips',f.trip),meta={business_name:'TEST transport',from:f.from,to:f.to};
  const html=recordPrintHtml('trips',r,meta,{kind:'trips',orientation:'portrait',signatures:['Driver signature','Officer signature'],version:1});
  assert.ok(html.includes('A4 portrait'));assert.ok(html.includes('Driver signature'));assert.ok(html.includes('Officer signature'));assert.ok(html.includes('Name: ____________________'));assert.ok(!html.includes('<script>'));assert.ok(html.includes('&lt;script&gt;'));assert.ok(html.includes('6.5'));
  const report=registerExport('trips',f.permissions,[r],meta);assert.ok(report.columns.some(c=>c.key==='cf_total'));assert.ok(registerCsv(report).includes('6.500000'));const workbook=registerWorkbook(report),col=report.columns.findIndex(c=>c.key==='cf_total')+1;assert.equal(workbook.worksheets[0].getCell(5,col).value,6.5);
  const note=definitions.cf_note;await field('cf_note','text',{hidden:true},note);const hidden=recordPrintHtml('trips',await f.read('trips',f.trip),meta);assert.ok(!hidden.includes('&lt;script&gt;'));
  await f.db.query("select public.save_print_template('trips',1,'landscape',array['Receiving party'])");const templates=await f.scalar<{kind:string;version:number;signatures:string[]}[]>('select public.print_templates()');assert.deepEqual(templates.find(x=>x.kind==='trips')!.signatures,['Receiving party']);
  await assert.rejects(()=>f.db.query("select public.save_print_template('trips',1,'portrait',array['Stale'])"),/reload/);
  const doc=applyPrintSettings({kind:'oil',title:'TEST',metadata:{},notes:[],sections:[],paper:'A3',incomplete:false},{kind:'oil',orientation:'landscape',signatures:['Driver signature'],version:1});assert.equal(doc.paper,'A4');assert.equal(doc.sections[0].role,'signature');assert.deepEqual(doc.sections[0].rows,[{}]);
 });
 await t.test('sorting, status filters, safe deletion and archived history work without losing data',async()=>{
  const list=await f.scalar<{rows:DataRow[];count:number}>('select public.form_register($1,$2,$3,1,25,$4,null,null,$5,$6,$7)', ['trips',f.from,f.to,'TEST','Planned','date','desc']);assert.equal(list.count,1);
  await assert.rejects(()=>f.db.query('select public.archive_form_record($1,$2,1,$3)',['drivers',f.driver,'TEST deletion']),/assignment/);
  const stored=(await f.db.query('select field_id,value from public.custom_field_values where record_id=$1 order by field_id',[f.trip])).rows;const r=await f.read('trips',f.trip);await f.db.query('select public.archive_form_record($1,$2,$3,$4)',['trips',f.trip,r.version,'TEST draft removal']);assert.ok((await f.read('trips',f.trip)).archived_at);
  const current=await f.scalar<{count:number}>('select public.form_register($1,$2,$3)',['trips',f.from,f.to]);assert.equal(current.count,0);
  const history=await f.scalar<{count:number}>('select public.form_register($1,$2,$3,1,25,\'\',null,null,\'\',\'name\',\'asc\',true)',['trips',f.from,f.to]);assert.equal(history.count,1);
  assert.deepEqual((await f.db.query('select field_id,value from public.custom_field_values where record_id=$1 order by field_id',[f.trip])).rows,stored);
  await assert.rejects(()=>f.save('trips',f.tripData,f.trip,Number(r.version)+1),/Deleted/);
 });
});
