import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {createApp} from '../server/app.js';
import {parseConfig} from '../server/config.js';
import type {SessionService,AuthContext} from '../server/session.js';
import type {Client} from '../server/supabase.js';
import {formFixture} from './helpers/form-fixture.js';
import type {DataRow} from '../shared/report-contract.js';

test('Redesigned HTTP workflows persist in PostgreSQL and enforce authenticated permissions',async t=>{
 const f=await formFixture();t.after(()=>f.db.close());let restricted=false;
 const db={
  async rpc(name:string,params:DataRow={}){try{assert.match(name,/^[a-z_]+$/);const entries=Object.entries(params),args=entries.map(([,v])=>v&&typeof v==='object'&&!Array.isArray(v)?JSON.stringify(v):v);const sql=`select public.${name}(${entries.map(([k],i)=>`${k} => $${i+1}`).join(',')})`;return {data:await f.scalar(sql,args),error:null};}catch(error){return {data:null,error:{code:(error as {code:string}).code??'P0001',message:(error as Error).message}};}},
  from(table:string){assert.ok(['business_settings','drivers','attachments'].includes(table));const clauses:{key:string;value:unknown}[]=[];let columns='*';const chain={select(value:string){columns=value;return chain;},eq(key:string,value:unknown){clauses.push({key,value});return chain;},async maybeSingle(){assert.match(columns,/^[a-z_,*]+$/);for(const c of clauses)assert.match(c.key,/^[a-z_]+$/);const result=await f.db.query(`select ${columns} from public.${table}${clauses.length?' where '+clauses.map((c,i)=>`${c.key}=$${i+1}`).join(' and '):''}`,clauses.map(c=>c.value));return {data:result.rows[0]??null,error:null};},async single(){return chain.maybeSingle();}};return chain;},
  storage:{from:()=>({download:async()=>({data:new Blob([Buffer.from([137,80,78,71,13,10,26,10])]),error:null})})}
 } as unknown as Client;
 const config=parseConfig({APP_ENV:'development',APP_URL:'http://localhost:5173',ALLOWED_ORIGINS:'http://localhost:5173',SUPABASE_URL:'https://example.supabase.co',SUPABASE_PUBLISHABLE_KEY:'test-publishable-not-valid',SUPABASE_SECRET_KEY:'test-privileged-not-valid',SESSION_ENCRYPTION_KEY:randomBytes(32).toString('hex')});
 const sessions={authenticate:async()=>({db,csrf:'TEST-csrf',access:{user:{id:'TEST-user',email:'test@example.test',display_name:'TEST'},roles:['TEST'],permissions:restricted?['drivers.view','vehicles.view','trips.view']:f.permissions}} as AuthContext)} as SessionService;
 const admin={rpc:async()=>({data:true,error:null})} as unknown as Client;
 const server=createApp(config,{sessions,admin}).listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));t.after(()=>new Promise<void>(r=>server.close(()=>r())));const address=server.address();assert.ok(address&&typeof address!=='string');
 async function request(path:string,body?:unknown){const response=await fetch(`http://127.0.0.1:${address.port}/api${path}`,{method:body===undefined?'GET':'POST',headers:{Cookie:'gbt_dev_session=TEST',Origin:config.APP_URL,'Content-Type':'application/json','X-CSRF-Token':'TEST-csrf'},body:body===undefined?undefined:JSON.stringify(body)});return {status:response.status,data:await response.json() as DataRow};}
 const range=`from=${f.from}&to=${f.to}`;let vehicle='',driver='',trip='';
 await t.test('vehicle address and driver identity save, reload, update, search and print',async()=>{
  let result=await request('/forms/vehicles',{id:null,version:null,data:{registration:'TEST-HTTP-002',manufacturer:'TEST Make',model:'TEST Model',address:'TEST Yard\nSecond line'}});assert.equal(result.status,200,JSON.stringify(result.data));vehicle=String(result.data.id);
  result=await request(`/forms/vehicles?id=${vehicle}&${range}`);assert.equal(result.data.address,'TEST Yard\nSecond line');
  result=await request('/forms/drivers',{id:null,version:null,data:{vehicle_id:vehicle,full_name:'TEST HTTP Driver',licence_number:'0000123',licence_expiry:f.to,mobile:'03000000005',joining_date:f.from,address:'TEST Driver address'}});assert.equal(result.status,200,JSON.stringify(result.data));driver=String(result.data.id);
  result=await request(`/forms/drivers?id=${driver}&${range}`);assert.equal(result.data.vehicle_id,vehicle);assert.equal(result.data.licence_number,'0000123');const row=result.data;
  result=await request('/forms/drivers',{id:driver,version:row.version,identity_version:row.identity_version,assignment_id:row.assignment_id,data:{full_name:'TEST Updated Driver',mobile:'03000000006',address:'TEST Updated address'}});assert.equal(result.status,200,JSON.stringify(result.data));
  result=await request(`/forms/drivers?${range}&search=Updated&status=Active&sort=date&direction=desc`);assert.equal(result.data.count,1);assert.equal((result.data.rows as DataRow[])[0].mobile,'03000000006');
  result=await request(`/print/record/drivers/${driver}?${range}`);assert.equal(result.status,200);assert.match(String(result.data.html),/TEST Updated address/);assert.match(String(result.data.html),/A4 portrait/);assert.match(String(result.data.html),/Name: ____________________/);
 });
 await t.test('custom fields and server-compiled formulas persist and recalculate after edits',async()=>{
  for(const data of [{key:'cf_units',label:'Units',type:'number',required:true},{key:'cf_rate',label:'Rate',type:'currency',default_value:'2.5'},{key:'cf_amount',label:'Amount',type:'formula',formula:'cf_units × cf_rate'}]){const result=await request('/custom-fields',{id:null,version:null,data:{resource:'trips',...data}});assert.equal(result.status,200,JSON.stringify(result.data));}
  const base={...f.tripData,cycle_number:'TEST HTTP trip',vehicle_id:vehicle,driver_id:driver};let result=await request('/forms/trips',{id:null,version:null,data:{...base,custom_values:{cf_units:'4'}}});assert.equal(result.status,200,JSON.stringify(result.data));trip=String(result.data.id);
  result=await request(`/forms/trips?id=${trip}&${range}`);assert.equal((result.data.custom_values as DataRow).cf_amount,'10.000000');assert.equal(result.data.total_km,'538.000');assert.equal(result.data.profit,'44000.00');
  result=await request('/forms/trips',{id:trip,version:result.data.version,data:{...base,custom_values:{cf_units:'2',cf_rate:'3.75'}}});assert.equal(result.status,200,JSON.stringify(result.data));result=await request(`/forms/trips?id=${trip}&${range}`);assert.equal((result.data.custom_values as DataRow).cf_amount,'7.500000');
  result=await request(`/print/record/trips/${trip}?${range}`);assert.equal(result.status,200);assert.match(String(result.data.html),/7.5/);assert.match(String(result.data.html),/Amount/);
  result=await request('/custom-fields',{id:null,version:null,data:{resource:'trips',key:'cf_bad',label:'Bad',type:'formula',formula:'globalThis.process.exit()'}});assert.equal(result.status,422);
 });
 await t.test('profile photos use authorized ready image attachments and clear on deletion',async()=>{
  const reserved=await f.scalar<{id:string;bucket_id:string;object_path:string}>("select public.reserve_attachment('drivers',$1,'TEST.png','image/png',8)",[driver]);await f.db.query('insert into storage.objects(bucket_id,name) values($1,$2)',[reserved.bucket_id,reserved.object_path]);await f.db.query('select public.finalize_attachment($1)',[reserved.id]);let row=await f.read('drivers',driver);
  let result=await request(`/drivers/${driver}/photo`,{attachment_id:reserved.id,version:row.version});assert.equal(result.status,200,JSON.stringify(result.data));row=await f.read('drivers',driver);assert.equal(row.photo_attachment_id,reserved.id);
  const response=await fetch(`http://127.0.0.1:${address.port}/api/drivers/${driver}/photo-image`,{headers:{Cookie:'gbt_dev_session=TEST'}});assert.equal(response.status,200);assert.match(response.headers.get('content-type')??'',/image\/png/);assert.match(response.headers.get('cache-control')??'',/no-store/);assert.equal((await response.arrayBuffer()).byteLength,8);
  result=await request(`/drivers/${driver}/photo`,{attachment_id:reserved.id,version:Number(row.version)-1});assert.equal(result.status,409);
  await f.db.query('select public.delete_attachment_state($1,false)',[reserved.id]);assert.equal((await f.read('drivers',driver)).photo_attachment_id,null);
 });
 await t.test('API and database restrictions block global edits, sensitive values and protected deletion',async()=>{
  restricted=true;await f.asUser(true);let result=await request('/custom-fields',{id:null,version:null,data:{resource:'trips',key:'cf_denied',label:'Denied',type:'text'}});assert.equal(result.status,403);
  result=await request(`/forms/trips?id=${trip}&${range}`);assert.equal(result.status,200);assert.ok(!Object.hasOwn(result.data,'fare'));result=await request(`/drivers/${driver}/photo`,{attachment_id:null,version:1});assert.equal(result.status,403);
  result=await request(`/forms/trips/${trip}/delete`,{version:1,reason:'TEST deletion'});assert.equal(result.status,403);restricted=false;await f.asUser();
  const before=await f.read('trips',trip);result=await request(`/forms/trips/${trip}/delete`,{version:before.version,reason:'TEST draft removal'});assert.equal(result.status,200,JSON.stringify(result.data));assert.ok((await f.read('trips',trip)).archived_at);result=await request(`/forms/trips?${range}&archived=true&search=HTTP`);assert.equal(result.data.count,1);
  const d=await f.read('drivers',driver);result=await request(`/forms/drivers/${driver}/delete`,{version:d.version,reason:'TEST protected removal'});assert.equal(result.status,422);assert.equal((await f.read('drivers',driver)).employment_status,'Active');
 });
});
