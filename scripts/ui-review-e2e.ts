// Visual/interaction regressions use only deterministic API fixtures; no live data.
import express from 'express';
import {resolve} from 'node:path';
import {mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {chromium,type Locator} from 'playwright';
import {modules} from '../shared/modules.js';
import {formContract,isFormResource} from '../shared/form-contract.js';
import type {DataRow} from '../shared/report-contract.js';

const app=express();app.use(express.static(resolve('dist/client')));
app.get('/{*path}',(_req,res)=>res.sendFile(resolve('dist/client/index.html')));
const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));
const address=server.address();if(!address||typeof address==='string')throw new Error('No test address');
const base=`http://127.0.0.1:${address.port}`;
const browser=await chromium.launch({...(process.env.PLAYWRIGHT_EXECUTABLE_PATH?{executablePath:process.env.PLAYWRIGHT_EXECUTABLE_PATH}:{}),args:['--no-sandbox','--disable-dev-shm-usage','--disable-gpu','--single-process']});
const context=await browser.newContext({viewport:{width:1440,height:900},reducedMotion:'reduce'}),page=await context.newPage();
page.setDefaultTimeout(15000);
const errors:string[]=[],missing:string[]=[],checks:string[]=[];page.on('pageerror',e=>errors.push(e.message));
page.on('console',message=>{if(message.type()==='error')errors.push(message.text());});
await mkdir('verification/ui-review',{recursive:true});
const vehicle='11111111-1111-4111-8111-111111111111',driver='22222222-2222-4222-8222-222222222222',trip='33333333-3333-4333-8333-333333333333',role='44444444-4444-4444-8444-444444444444';
const permissions=[...new Set(Object.values(modules).flatMap(m=>[m.permission,m.createPermission,m.editPermission].filter(Boolean) as string[])), 'reports.export','reports.financial.view','trips.finance.view','imports.manage','settings.manage','users.view','users.create','users.disable','users.roles','roles.view','roles.manage','audit.view','assignments.manage','drivers.identity.view','drivers.identity.manage'];
const date='2026-10-11',settings={business_name:'Gujjar Brother Transport',contact_email:'owner@example.test',phone_1:'03000000001',phone_2:'',phone_3:'',address:'Transport office',currency:'PKR',timezone:'Asia/Karachi',period_start_day:1,period_confirmed:true,refresh_seconds:60,version:1};
const records:Record<string,DataRow>={
 vehicles:{id:vehicle,registration:'601',manufacturer:'Hino',model:'500',status:'Active',address:'Toba Tek Singh',opening_odometer:'1000',current_odometer:'2000',income:'80000',average:'8',version:1},
 drivers:{id:driver,full_name:'Ahmed',mobile:'03000000001',vehicle_id:vehicle,vehicle_id_label:'601',employment_status:'Active',joining_date:date,address:'Lahore',cycles:'1',average:'8',loan_left:'0',version:1},
 trips:{id:trip,cycle_number:'UI-TRIP-001',business_date:date,vehicle_id:vehicle,vehicle_id_label:'601',driver_id:driver,driver_id_label:'Ahmed',origin:'Toba Tek Singh',destination:'Lahore',fare:'80000',diesel:'29000',commission:'2000',total_expense:'31000',profit:'49000',start_odometer:'1000',end_odometer:'1538',total_km:'538',fuel_litres:'68',fuel_basis:'purchase_estimate',weight_unit:'metric tonnes',average:'7.91',operational_state:'Planned',financial_state:'Draft',version:1},
 maintenance:{id:'maintenance',vehicle_id:vehicle,vehicle_id_label:'601',driver_id:driver,driver_id_label:'Ahmed',engine:'Oil check',gearbox:'Inspected',body:'General service',state:'Draft',version:1}
};
const generic:DataRow={id:'sample',version:1,business_date:date,driver_id:driver,driver_id_label:'Ahmed',vehicle_id:vehicle,vehicle_id_label:'601',description:'Sample transport expense',amount:'2000',category:'Office',payment_method:'Cash',reference:'TEST-001',origin:'Toba Tek Singh',destination:'Lahore',quoted_freight:'80000',commission:'2000',kind:'Salary',rule_snapshot:'Monthly agreement',name:'October',start_date:'2026-10-01',end_date:'2026-10-31',status:'Open',state:'Draft'};
const users=Array.from({length:28},(_,i)=>({id:'staff-'+i,display_name:i===0?'Ahmed':i===1?'Babar':'Staff '+String(i+1).padStart(2,'0'),email:'staff'+i+'@example.test',active:true,version:1,created_at:'2026-10-01T12:00:00Z',user_roles:[{role_id:role}]}));
await context.route('**/api/**',async route=>{
 const url=new URL(route.request().url()),p=url.pathname;let body:unknown={},status=200;
 if(p==='/api/auth/me')body={user:{id:'owner',display_name:'Owner',email:'owner@example.test'},permissions,roles:['Super Admin'],environment:'development',csrf:'TEST-CSRF'};
 else if(p==='/api/auth/csrf')body={csrf:'TEST-CSRF'};
 else if(p==='/api/settings')body=settings;
 else if(p==='/api/dashboard')body={today:date,refreshed_at:date+'T08:00:00Z',vehicles:1,total_drivers:1,active_drivers:1,available_vehicles:1,active_trips:1,completed_trips:0,on_duty:1,today_trips:1,vehicle_status:{Active:1},trip_series:[{date,trips:1}],fuel_ranking:[{registration:'601',distance:'538',litres:'68',efficiency:'7.91',eligible_trips:1}],finance:{revenue:'80000',expenses:'31000',operating_profit:'49000',pending_trips:1,series:[{date,revenue:'80000',expenses:'31000',profit:'49000'}],vehicle_ranking:[{registration:'601',trips:1,revenue:'80000',profit:'49000'}],unallocated_overhead:'0'}};
 else if(p==='/api/users'){
  const search=url.searchParams.get('search')??'',number=Number(url.searchParams.get('page')??1);
  if(search==='Ahmed'||search==='Babar')await new Promise(r=>setTimeout(r,search==='Ahmed'?100:500));
  const filtered=users.filter(user=>user.display_name.toLowerCase().includes(search.toLowerCase()));
  body={rows:filtered.slice((number-1)*25,number*25),count:filtered.length,page:number};
 }
 else if(p==='/api/roles')body=[{id:role,name:'Viewer',reserved:false,version:1}];
 else if(p==='/api/permissions')body=[{code:'vehicles.view',description:'Read vehicles'},{code:'drivers.view',description:'Read drivers'}];
 else if(p.startsWith('/api/roles/')&&p.endsWith('/grants'))body=[{permission_code:'vehicles.view',scope:'all'}];
 else if(p==='/api/audit')body={rows:[{id:'audit',created_at:date+'T08:00:00Z',action:'save_vehicle',record_type:'Vehicle',summary:'Saved vehicle 601'}],count:1,page:1};
 else if(p==='/api/notifications')body={rows:[{id:'reminder',type:'Service Reminder',message:'Vehicle 601 oil change due',created_at:date+'T08:00:00Z',read_at:null,action_link:'/vehicles'}],count:1,page:1,unread_count:1};
 else if(p==='/api/routes')body={rows:[{id:'route',origin:'Toba Tek Singh',destination:'Lahore',version:1}],count:1,page:1};
 else if(p==='/api/lookup'){
  const resource=url.searchParams.get('resource')??'',search=(url.searchParams.get('search')??'').toLowerCase();
  const options=resource==='vehicles'?[{value:vehicle,label:'601'}]:resource==='drivers'?[{value:driver,label:'Ahmed'}]:resource==='trips'?[{value:trip,label:'UI-TRIP-001'}]:[];
  body=options.filter(option=>(!url.searchParams.get('id')||option.value===url.searchParams.get('id'))&&option.label.toLowerCase().includes(search));
 }
 else if(p.startsWith('/api/custom-fields/')||['/api/imports','/api/alerts','/api/alert-rules','/api/documents'].includes(p))body=[];
 else if(p==='/api/print-settings')body=['vehicles','drivers','trips','maintenance','office','oil','monthly','combined'].map(kind=>({kind,orientation:'portrait',signatures:['Signature'],version:1}));
 else if(p.startsWith('/api/forms/')){const resource=p.split('/')[3];body=url.searchParams.has('id')?records[resource]:{rows:[records[resource]],count:1,page:1};}
 else if(p.startsWith('/api/records/'))body={rows:[{...generic,...records[p.split('/')[3]]}],count:1,page:1};
 else if(p==='/api/reports')body={rows:[{registration:'601',revenue:'80000',profit:'49000'}],columns:[{key:'registration',label:'Vehicle'},{key:'revenue',label:'Revenue'},{key:'profit',label:'Profit'}],metadata:{business_name:'TEST Transport',from:date,to:date}};
 else{missing.push(p);status=404;body={error:{message:'Missing fixture: '+p}};}
 await route.fulfill({status,contentType:'application/json',body:JSON.stringify(body)});
});

async function open(path:string){await page.goto(base+path);await page.locator('.workspace-content h1').waitFor();await page.locator('.loading').waitFor({state:'hidden'});}
async function fits(label:string){
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),label+' page overflow');
 const outside=await page.evaluate(()=>Array.from(document.querySelectorAll<HTMLElement>('.workspace-content button,.workspace-content input,.workspace-content select,.workspace-content textarea')).filter(el=>{
  if(el.closest('.table-wrap')||el.closest('dialog'))return false;
  const rect=el.getBoundingClientRect();return rect.width>0&&rect.height>0&&(rect.left< -1||rect.right>innerWidth+1);
 }).map(el=>el.getAttribute('aria-label')??el.textContent?.slice(0,60)));
 assert.deepEqual(outside,[],label+' controls clipped');
 if((await page.viewportSize())!.width<=900)assert.equal(await page.locator('.main-shell').evaluate(el=>Math.round(el.getBoundingClientRect().left)),0,label+' reserves hidden sidebar space');
 assert.equal(await page.locator('.workspace-content [role="alert"]').count(),0,label+' error notice');
}
function luminance(color:string){const channels=(color.match(/[0-9.]+/g)??[]).slice(0,3).map(Number).map(v=>{const n=v/255;return n<=.04045?n/12.92:((n+.055)/1.055)**2.4;});return .2126*channels[0]+.7152*channels[1]+.0722*channels[2];}
function contrast(a:string,b:string){const x=luminance(a),y=luminance(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05);}
async function readable(locator:Locator,placeholder=false){
 for(let i=0;i<await locator.count();i++){
  const colors=await locator.nth(i).evaluate((element,isPlaceholder)=>{const style=getComputedStyle(element),text=isPlaceholder?getComputedStyle(element,'::placeholder'):style;let background=style.backgroundColor,parent=element.parentElement;while((background==='rgba(0, 0, 0, 0)'||background==='transparent')&&parent){background=getComputedStyle(parent).backgroundColor;parent=parent.parentElement;}return {foreground:text.color,fill:text.webkitTextFillColor,background};},placeholder);
  assert.ok(contrast(colors.foreground,colors.background)>=4.5,JSON.stringify(colors));
  if(colors.fill!=='currentcolor')assert.ok(contrast(colors.fill,colors.background)>=4.5,'WebKit fill: '+JSON.stringify(colors));
 }
}
try{
 await open('/users');await page.getByRole('cell',{name:'Ahmed',exact:true}).waitFor();
 await page.evaluate(()=>document.fonts.ready);
 const search=page.getByLabel('Search users'),icon=page.locator('.search-field .bi-search');
 assert.equal(await icon.count(),1);
 const bounds=await search.boundingBox(),iconBounds=await icon.boundingBox();assert.ok(bounds&&iconBounds);
 const padding=await search.evaluate(el=>parseFloat(getComputedStyle(el).paddingLeft));
 assert.ok(bounds.x+padding>iconBounds.x+iconBounds.width+4,'User-search icon overlaps typed text');
 assert.ok(Math.abs(iconBounds.y+iconBounds.height/2-(bounds.y+bounds.height/2))<=2,'Search icon is not vertically centered');
 await page.getByRole('button',{name:'Next',exact:true}).click();await page.getByRole('cell',{name:'Staff 28',exact:true}).waitFor();
 const first=page.waitForRequest(request=>new URL(request.url()).pathname==='/api/users'&&new URL(request.url()).searchParams.get('search')==='Ahmed');
 const oldResponse=page.waitForResponse(response=>new URL(response.url()).pathname==='/api/users'&&new URL(response.url()).searchParams.get('search')==='Ahmed');
 await search.fill('Ahmed');await first;
 const latest=page.waitForRequest(request=>new URL(request.url()).pathname==='/api/users'&&new URL(request.url()).searchParams.get('search')==='Babar');
 await search.fill('Babar');await latest;await oldResponse;
 assert.equal(await page.locator('.loading').count(),1,'A superseded search clears the latest loading state');
 await page.getByRole('cell',{name:'Babar',exact:true}).waitFor();assert.equal(await page.locator('tbody tr').count(),1);
 await search.fill('No such staff');await page.getByRole('heading',{name:'No users found'}).waitFor();
 await search.fill('');await page.getByRole('cell',{name:'Ahmed',exact:true}).waitFor();
 checks.push('Existing user search: visible centered icon, typed-text padding, page reset, filtered results, empty state and stale-request protection');
 console.log('PASS UI: existing user-search controls and overlapping requests');

 const routes:[string,string][]=[['/','WELCOME SIR ATTIQ'],...Object.entries(modules).filter(([key])=>key!=='companies').map(([key,m])=>['/'+key,m.title] as [string,string]),['/reports','Reports & exports'],['/users','Users'],['/roles','Roles & permissions'],['/settings','Business settings'],['/audit','Audit history'],['/fields','Fields & print settings'],['/imports','CSV imports'],['/routes','Routes'],['/notifications','Notification center']];
 for(const width of [1440,1024,768,390,360]){
  await page.setViewportSize({width,height:width===768?1024:900});
  for(const [path,heading] of routes){await open(path);await page.getByRole('heading',{name:heading,exact:true}).waitFor();await fits(width+' '+path);}
  await open('/trips');await page.getByRole('button',{name:'Table view'}).click();await page.locator('.table-wrap tbody tr').waitFor();
  const table=page.locator('.table-wrap').first();
  if(width<=768){assert.ok(await table.evaluate(el=>el.scrollWidth>el.clientWidth),'Wide trip table should scroll');await table.evaluate(el=>el.scrollLeft=el.scrollWidth);assert.ok(await table.evaluate(el=>el.scrollLeft>0),'Trip table scroll did not move');}
  await fits(width+' trip table');await page.getByRole('button',{name:'Cards view'}).click();
  for(const resource of Object.keys(modules).filter(key=>key!=='companies')){
   await open('/'+resource);const button=page.getByRole('button',{name:isFormResource(resource)?formContract[resource].title:'Add '+modules[resource].singular.toLowerCase(),exact:true});
   if(!await button.count())continue;await button.click();const dialog=page.getByRole('dialog');await dialog.waitFor();
   const box=await dialog.boundingBox();assert.ok(box&&box.x>=0&&box.x+box.width<=width+1&&box.height<=page.viewportSize()!.height*.96,'Dialog fits '+width+' '+resource);
   assert.ok(await dialog.locator('.dialog-body').evaluate(el=>el.scrollWidth<=el.clientWidth+1),'Dialog horizontal overflow '+resource);
   if(resource==='trips'&&width===1440){for(const [label,id] of [['Vehicle',vehicle],['Driver',driver]]){await dialog.getByLabel(label,{exact:true}).locator('option[value="'+id+'"]').waitFor({state:'attached'});await dialog.getByLabel(label,{exact:true}).selectOption(id);}await dialog.getByRole('status').filter({hasText:'Selected: Ahmed'}).waitFor();await readable(dialog.locator('.lookup-selected'));}
   await dialog.getByRole('button',{name:'Cancel',exact:true}).click();
  }
  await open('/users');await page.screenshot({path:'verification/ui-review/users-'+width+'.png',fullPage:true});
  checks.push('Light theme: all '+routes.length+' screens, module create dialogs and trip-table scroll at '+width+'px');
  console.log('PASS UI viewport:',width,'all',routes.length,'screens, form dialogs and table scroll');
 }

 await page.setViewportSize({width:1440,height:900});await page.getByRole('button',{name:'Switch to dark theme'}).click();
 for(const width of [1440,390]){
  await page.setViewportSize({width,height:900});
  for(const [path] of routes){await open(path);await fits('dark '+width+' '+path);await readable(page.locator('.workspace-content input:not([type="checkbox"]):not([type="radio"]):not([type="file"]),.workspace-content textarea,.workspace-content select'));}
  await open('/trips');await page.getByRole('button',{name:'Add trip',exact:true}).click();const dialog=page.getByRole('dialog');
  await dialog.getByLabel('Vehicle',{exact:true}).locator('option[value="'+vehicle+'"]').waitFor({state:'attached'});await dialog.getByLabel('Vehicle',{exact:true}).selectOption(vehicle);
  await dialog.getByLabel('Driver',{exact:true}).locator('option[value="'+driver+'"]').waitFor({state:'attached'});await dialog.getByLabel('Driver',{exact:true}).selectOption(driver);
  await dialog.getByRole('status').filter({hasText:'Selected: 601'}).waitFor();await dialog.getByRole('status').filter({hasText:'Selected: Ahmed'}).waitFor();
  const lookupResponse=page.waitForResponse(response=>new URL(response.url()).pathname==='/api/lookup'&&new URL(response.url()).searchParams.get('search')==='No match');
  await dialog.getByLabel('Search Vehicle',{exact:true}).fill('No match');await lookupResponse;
  assert.equal(await dialog.getByLabel('Vehicle',{exact:true}).inputValue(),vehicle);assert.equal(await dialog.getByLabel('Vehicle',{exact:true}).locator('option:checked').textContent(),'601');
  await dialog.getByLabel('Cycle number',{exact:true}).pressSequentially('DARK-001');
  await dialog.getByLabel('Remarks',{exact:true}).pressSequentially('Readable notes in dark mode');
  await dialog.getByLabel('Fare (PKR)',{exact:true}).fill('80000');await dialog.getByLabel('Driver cycle commission (PKR)',{exact:true}).fill('2000');
  assert.equal(await dialog.getByLabel('Profit (PKR)',{exact:true}).inputValue(),'78000.00');
  await readable(dialog.locator('input:not([type="checkbox"]),textarea,select,.lookup-selected'));
  await readable(dialog.locator('input[placeholder],textarea[placeholder]'),true);
  await dialog.locator('.dialog-body').evaluate(el=>el.scrollTop=0);
  await page.screenshot({path:'verification/ui-review/trip-dark-'+width+'.png',fullPage:true});
  await dialog.getByLabel('Remarks',{exact:true}).scrollIntoViewIfNeeded();assert.ok(await dialog.locator('.dialog-body').evaluate(el=>el.scrollTop>0),'Long trip dialog scrolls');
  assert.ok(await dialog.getByRole('button',{name:'Save changes',exact:true}).isVisible(),'Save stays visible');
  await dialog.getByRole('button',{name:'Cancel',exact:true}).click();
  await open('/trips');await page.locator('.record-card').getByRole('button',{name:'Edit',exact:true}).click();
  await page.getByRole('dialog').getByRole('status').filter({hasText:'Selected: 601'}).waitFor();await page.getByRole('dialog').getByRole('status').filter({hasText:'Selected: Ahmed'}).waitFor();
  assert.equal(await page.getByRole('dialog').getByLabel('Vehicle',{exact:true}).isDisabled(),true);
  await readable(page.getByRole('dialog').locator('select:disabled,input[readonly]'));
  await page.getByRole('dialog').getByRole('button',{name:'Cancel',exact:true}).click();
  checks.push('Dark theme '+width+'px: all screens fit, inputs/selects/notes/placeholders/read-only totals meet 4.5:1 contrast, selected vehicle/driver stay visible after search and reload, long dialog scrolls');
  console.log('PASS dark UI:',width,'text, placeholders, notes, selected values, formulas and saved selections');
 }
 await page.reload();await page.locator('.workspace-content h1').waitFor();assert.equal(await page.locator('html').getAttribute('data-theme'),'dark');
 await page.getByRole('button',{name:'Open navigation'}).click();await page.getByRole('button',{name:'Users',exact:true}).click();assert.equal(await page.locator('.sidebar.is-open').count(),0);
 // Session end clears the protected workspace without an unsafe automatic form retry.
 await page.evaluate(()=>window.dispatchEvent(new Event('gbt:session-ended')));
 await page.getByRole('button',{name:'Sign in',exact:true}).waitFor();
 assert.equal(await page.locator('.workspace-content').count(),0);
 await page.getByRole('alert').filter({hasText:'Your session ended'}).waitFor();
 checks.push('Session expiry clears the protected workspace and returns to sign-in');
 assert.deepEqual(missing,[]);assert.deepEqual(errors,[]);
 await writeFile('verification/ui-review/results.json',JSON.stringify({date:'2026-10-11',status:'passed',checks,viewports:[1440,1024,768,390,360],browserErrors:errors,unmatchedApiFixtures:missing,scope:'Deterministic UI fixtures only; no hosted Supabase or business data.'},null,2));
 console.log('PASS full UI review: balanced sizing, user search, mobile/tablet/desktop, dark inputs, selections, scrolling and zero browser/console errors');
}catch(error){await page.screenshot({path:'verification/ui-review/error.png',fullPage:true});console.error({missing,errors});throw error;}
finally{await browser.close();await new Promise<void>(r=>server.close(()=>r()));}
