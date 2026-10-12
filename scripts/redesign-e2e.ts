// UI-only sample records. This test never connects to the configured live database.
import express from 'express';
import {resolve} from 'node:path';
import {mkdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {chromium} from 'playwright';
import {modules} from '../shared/modules.js';
import {buildReference,type DataRow} from '../shared/report-contract.js';
import {reportHtml} from '../server/report-render.js';
const app=express();app.use(express.static(resolve('dist/client')));app.get('/{*path}',(_req,res)=>res.sendFile(resolve('dist/client/index.html')));
const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));const addr=server.address();if(!addr||typeof addr==='string')throw new Error('Missing test address');
const browser=await chromium.launch({...(process.env.PLAYWRIGHT_EXECUTABLE_PATH?{executablePath:process.env.PLAYWRIGHT_EXECUTABLE_PATH}:{}),args:['--no-sandbox','--disable-dev-shm-usage','--disable-gpu','--single-process']});
const context=await browser.newContext({viewport:{width:1440,height:1000},reducedMotion:'reduce'}),page=await context.newPage(),errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));await mkdir('verification/redesign',{recursive:true});
const vehicle='11111111-1111-4111-8111-111111111111',driver='22222222-2222-4222-8222-222222222222';
const permissions=[...new Set(Object.values(modules).flatMap(m=>[m.permission,m.createPermission,m.editPermission].filter(Boolean) as string[])),'reports.export','reports.financial.view','trips.finance.view','imports.manage','settings.manage','users.view','roles.view','audit.view'];
let restricted=false;
await context.addInitScript(()=>{window.print=()=>{document.body.dataset.printCalled='yes';};});
await context.route('**/api/**',async route=>{
 const url=new URL(route.request().url()),p=url.pathname,from=url.searchParams.get('from')??'2026-10-01',to=url.searchParams.get('to')??'2026-10-09';let body:unknown={},contentType='application/json';
 if(p==='/api/auth/me')body={user:{id:'test',display_name:'System Owner',email:'test@example.test'},permissions:restricted?['vehicles.view']:permissions,roles:[restricted?'Viewer':'Super Admin'],environment:'development',csrf:'test'};
 else if(p==='/api/settings')body={refresh_seconds:60};
 else if(p==='/api/dashboard'){
  const length=Math.min(40,Math.max(1,Math.round((Date.parse(to)-Date.parse(from))/86400000)+1));
  const series=Array.from({length},(_,i)=>{const revenue=[87000,128000,102000,147000,135000,112000,174000,139000,183000][i%9],expenses=i===2?114000:Math.round(revenue*(.45+(i%3)*.08));return {date:new Date(Date.parse(from)+i*86400000).toISOString().slice(0,10),revenue:String(revenue),expenses:String(expenses),profit:String(revenue-expenses)};});
  body={today:to,from,to,refreshed_at:new Date().toISOString(),vehicles:24,...(!restricted?{total_drivers:20,active_drivers:18,available_vehicles:19,active_trips:12,completed_trips:30}:{}),vehicle_status:{Active:19,Maintenance:3,Inactive:2},...(!restricted?{trip_series:series.filter((_,i)=>i%3!==1).map((s,i)=>({date:s.date,trips:[7,11,5,14,9,12][i%6]})),fuel_ranking:[{registration:'JAG-641',distance:'1984',litres:'248',efficiency:'8.00',eligible_trips:8},{registration:'LES-5360',distance:'1540',litres:'201',efficiency:'7.66',eligible_trips:6}],finance:{revenue:'183000',expenses:'109800',operating_profit:'73200',transport:'170000',brokerage:'13000',pending_trips:4,series,vehicle_ranking:[{registration:'JAG-641',trips:8,revenue:'438000',profit:'143500'},{registration:'LES-5360',trips:7,revenue:'392000',profit:'127800'},{registration:'LR-3627',trips:6,revenue:'347000',profit:'105200'},{registration:'LZJ-5866',trips:5,revenue:'299000',profit:'94600'}],unallocated_overhead:'12500'}}:{})};
 }else if(p==='/api/lookup')body=[{value:url.searchParams.get('resource')==='vehicles'?vehicle:driver,label:url.searchParams.get('resource')==='vehicles'?'JAG-641':'Ali Raza'}];
 else if(p==='/api/reference-reports'){
  const kind=url.searchParams.get('kind')??'oil';const source:DataRow={metadata:{business_name:'Gujjar Brother Transport — TEST DATA',contact_email:'test@example.test',phone_1:'TEST',phone_2:'',phone_3:'',from,to,period_label:'OCT-2026',generated_at:new Date().toISOString()},vehicles:[{id:vehicle,registration:'JAG-641'}],drivers:[{id:driver,full_name:'Ali Raza',joining_date:'2024-01-01',loan_taken:'50000',loan_paid:'15000',loan_left:'35000'}],trips:[{id:'trip',vehicle_id:vehicle,driver_id:driver,driver_id_label:'Ali Raza',financial_state:'Approved',operational_state:'Completed',business_date:to,route_description:'Lahore / Karachi',fare:'80000',total_expense:'36000',profit:'44000',diesel:'29000',tolls:'3000',food:'1200',other:'800',commission:'2000',start_odometer:'144844',end_odometer:'145382',total_km:'538',fuel_litres:'68',fuel_basis:'measured',average:'7.91',weight:'12',weight_unit:'metric tonnes'}],oil:[{vehicle_id:vehicle,driver_id:driver,date:from,odometer:'144700',previous_date:'2026-09-01',previous_odometer:'138000'}],closing_readings:[{vehicle_id:vehicle,date:to,odometer:'145382'}],revenue:[{kind:'Transport',amount:'80000',vehicle_id:vehicle}],expenses:[{category:'diesel',amount:'29000',vehicle_id:vehicle},{category:'commission',amount:'2000',vehicle_id:vehicle}],bookings:[{state:'Approved',business_date:to,external_vehicle:'JAG-641',driver_contact:'03000000000',cargo:'General cargo',origin:'Lahore',destination:'Karachi',quoted_freight:'80000',commission:'2000'}],office:[{state:'Approved',business_date:to,description:'Office supplies',amount:'500'}]};
  const doc=buildReference(kind,source,{vehicle,driver});body=url.searchParams.get('format')==='html'?reportHtml(doc):doc;if(typeof body==='string')contentType='text/html';
 }else if(p==='/api/forms/vehicles')body={rows:[{id:vehicle,version:1,registration:'JAG-641',manufacturer:'Hino',model:'500',status:'Active',income:'438000',average:'8'}],count:1};
 else if(p==='/api/notifications')body={rows:[],count:0,page:1,unread_count:0};
 else if(p==='/api/routes')body={rows:[],count:0,page:1};
 else if(p==='/api/print-settings'||p.startsWith('/api/custom-fields/'))body=[];
 else if(p.startsWith('/api/forms/')||p.startsWith('/api/records/'))body={rows:[],count:0};
 else if(p==='/api/reports')body={rows:[{registration:'JAG-641'}],columns:[{key:'registration',label:'Vehicle'}],metadata:{from,to,business_name:'TEST DATA'}};
 else if(['/api/users','/api/audit'].includes(p))body={rows:[],count:0,page:1};
 else if(['/api/alerts','/api/alert-rules','/api/imports','/api/roles'].includes(p))body=[];
 await route.fulfill({contentType,body:typeof body==='string'?body:JSON.stringify(body)});
});
const base=`http://127.0.0.1:${addr.port}`,financial=page.locator('.performance-chart').filter({has:page.getByRole('button',{name:'Revenue',exact:true})});
try{
 await page.goto(base);await page.getByRole('button',{name:'Print overview',exact:true}).waitFor();await page.waitForFunction(()=>!document.querySelector<HTMLButtonElement>('.page-actions .primary')?.disabled);await page.evaluate(()=>document.fonts.ready);
 assert.equal(await page.locator('.stat-card').count(),7);assert.equal(await financial.locator('.chart-line').count(),3);
 await page.screenshot({path:'verification/redesign/dashboard-desktop.png',fullPage:true,animations:'disabled'});
 await financial.locator('.chart-hit').nth(2).hover();await page.getByRole('status').filter({hasText:'Profit'}).waitFor();assert.match(await page.locator('.chart-tooltip').innerText(),/-12,000/);
 await financial.getByRole('button',{name:'Expenses',exact:true}).click();assert.equal(await financial.locator('.chart-line').count(),2);
 await financial.getByRole('button',{name:'Expenses',exact:true}).click();await financial.getByRole('button',{name:'View chart data'}).click();assert.ok(await page.locator('.chart-data tbody tr').count()>0);await financial.getByRole('button',{name:'Hide chart data'}).click();
 await page.getByRole('button',{name:'Today',exact:true}).click();await page.waitForFunction(()=>document.querySelector('.dashboard-grid')?.getAttribute('aria-busy')==='false');assert.equal(await financial.locator('.chart-hit').count(),1);assert.ok(await financial.locator('.chart-series circle').count()>0);
 await page.getByRole('button',{name:'Month',exact:true}).click();await page.waitForFunction(()=>document.querySelector('.dashboard-grid')?.getAttribute('aria-busy')==='false');
 await page.getByRole('button',{name:'Print overview',exact:true}).click();assert.equal(await page.locator('body').getAttribute('data-print-called'),'yes');
 await page.getByRole('button',{name:'Switch to dark theme'}).click();assert.equal(await page.locator('html').getAttribute('data-theme'),'dark');await page.screenshot({path:'verification/redesign/dashboard-dark.png',fullPage:true,animations:'disabled'});await page.reload();await page.locator('.stat-card').first().waitFor();assert.equal(await page.locator('html').getAttribute('data-theme'),'dark');await page.getByRole('button',{name:'Switch to light theme'}).click();
 await page.getByLabel('Find a page').fill('vehicles');assert.equal(await page.locator('nav button').count(),1);await page.getByRole('button',{name:'Vehicles',exact:true}).click();await page.locator('.record-card').waitFor();await page.getByRole('button',{name:'Table view'}).click();await page.locator('tbody tr').waitFor();await page.screenshot({path:'verification/redesign/vehicles-desktop.png',fullPage:true,animations:'disabled'});
 await page.getByRole('button',{name:'Print full register'}).click();await page.getByRole('dialog').waitFor();assert.match(await page.frameLocator('dialog iframe').locator('body').innerText(),/Signature:/);await page.getByRole('dialog').getByRole('button',{name:'Print / Save as PDF',exact:true}).click();await page.waitForFunction(()=>document.querySelector<HTMLIFrameElement>('iframe[data-gbt-print]')?.contentDocument?.body.dataset.printCalled==='yes');await page.locator('iframe[data-gbt-print]').evaluateAll(frames=>frames.forEach(frame=>frame.remove()));await page.getByRole('dialog').getByRole('button',{name:'Close',exact:true}).click();
 await page.getByRole('button',{name:'Reports & exports',exact:true}).click();await page.getByRole('button',{name:'Preview',exact:true}).click();await page.locator('.workspace-content .table-wrap tbody tr').waitFor();await page.screenshot({path:'verification/redesign/reports-desktop.png',fullPage:true,animations:'disabled'});
 for(const kind of ['office','oil','monthly','combined','driver-details']){
  await page.getByLabel('Output',{exact:true}).selectOption('reference:'+kind);
  if(kind==='combined'){await page.getByLabel('Vehicle filter',{exact:true}).selectOption(vehicle);await page.getByLabel('Driver filter',{exact:true}).selectOption(driver);}
  await page.getByRole('button',{name:'Preview',exact:true}).click();await page.locator('iframe.report-preview').waitFor();await page.getByRole('button',{name:'Print report',exact:true}).click();await page.waitForFunction(()=>document.querySelector<HTMLIFrameElement>('iframe[data-gbt-print]')?.contentDocument?.body.dataset.printCalled==='yes');
  const frame=page.frameLocator('iframe.report-preview');assert.ok(await frame.locator('thead').count()>0);assert.match(await frame.locator('body').innerText(),/Signature:/);await page.locator('iframe[data-gbt-print]').evaluateAll(frames=>frames.forEach(item=>item.remove()));
 }
 await page.setViewportSize({width:390,height:844});await page.goto(base);await page.locator('.stat-card').first().waitFor();assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));await page.screenshot({path:'verification/redesign/dashboard-mobile.png',fullPage:true,animations:'disabled'});
 await page.getByRole('button',{name:'Open navigation'}).click();await page.keyboard.press('Escape');assert.equal(await page.locator('.sidebar.is-open').count(),0);
 await page.getByRole('button',{name:'Open navigation'}).click();await page.getByRole('button',{name:'Reports & exports',exact:true}).click();assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));await page.screenshot({path:'verification/redesign/reports-mobile.png',fullPage:true,animations:'disabled'});
 restricted=true;await page.setViewportSize({width:1440,height:1000});await page.goto(base);await page.locator('.stat-card').first().waitFor();assert.equal(await page.locator('.stat-card').count(),1);assert.equal(await financial.count(),0);await page.goto(base+'/reports');await page.getByRole('alert').waitFor();assert.equal(await page.getByRole('button',{name:'Preview',exact:true}).count(),0);
 assert.deepEqual(errors,[]);console.log('PASS: populated charts, negative and single-day values, legend filters, chart data table, dark-theme persistence, page search, all five reference print buttons, complete register printing, mobile layout, Escape navigation and permission-gated screens. UI data are fixtures; no hosted Supabase calls.');
}catch(error){console.error({errors,body:(await page.locator('body').innerText()).slice(0,1800)});throw error;}finally{await browser.close();await new Promise<void>(r=>server.close(()=>r()));}
