import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,randomBytes} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {formFixture} from './helpers/form-fixture.js';
import {createApp} from '../server/app.js';
import {parseConfig} from '../server/config.js';
import {createSessionService,type SessionService,type AuthContext} from '../server/session.js';
import type {Client} from '../server/supabase.js';
import {decrypt,hash} from '../server/crypto.js';
import {AppError} from '../server/errors.js';
import {recordPrintHtml,applyPrintSettings} from '../server/record-print.js';
import {registerHtml} from '../client/src/print.js';
import {buildReference} from '../shared/report-contract.js';
import {reportHtml,reportWorkbook,reportPdf} from '../server/report-render.js';
import type {Row} from '../client/src/components.js';

test('Transport enhancements execute against the migrated PostgreSQL database',async t=>{
 const f=await formFixture();t.after(()=>f.db.close());
 const ago=(days:number)=>new Date(new Date(f.today+'T12:00:00Z').getTime()-days*86400000).toISOString().slice(0,10);
 const v2=await f.save('vehicles',{registration:'601',manufacturer:'TEST',permit_expiry:ago(-10),insurance_expiry:ago(-20),opening_odometer:'1000',service_interval_km:'100'});
 const v3=await f.save('vehicles',{registration:'702',manufacturer:'TEST'});
 const d=await f.save('drivers',{full_name:'Ahmed',mobile:'03000000099',joining_date:ago(90),vehicle_id:v2,assignment_date:ago(60)});
 const history=()=>f.scalar<{rows:Row[];count:number}>('select public.driver_vehicle_history($1)',[d]);
 await t.test('dated transfers close the old assignment, preserve the driver ID and retain all history',async()=>{
  const first=(await history()).rows[0];assert.equal(first.vehicle_number,'601');assert.equal(first.assigned_date,ago(60));
  await f.db.query('select public.transfer_driver($1,$2,$3,$4,$5)',[d,v3,ago(30),'Long route',first.id]);
  const h=await history();assert.equal(h.count,2);assert.equal(h.rows[0].previous_vehicle,'601');assert.equal(h.rows[0].transfer_date,ago(30));assert.equal(h.rows[1].new_vehicle,'702');assert.equal(h.rows[1].removed_date,ago(31));
  assert.equal(await f.scalar<number>('select count(*)::int from public.drivers where id=$1',[d]),1);
  assert.equal((await f.read('drivers',d)).vehicle_id,v3);assert.equal((await f.read('trips',f.trip)).vehicle_id,f.vehicle);
 });
 await t.test('stale, occupied, future and out-of-order transfers roll back without losing the active assignment',async()=>{
  const current=(await history()).rows[0];
  for(const args of [[d,v2,ago(0),'',randomUUID()],[d,f.vehicle,ago(0),'',current.id],[d,v2,ago(-1),'',current.id],[d,v2,ago(31),'',current.id]])await assert.rejects(()=>f.db.query('select public.transfer_driver($1,$2,$3,$4,$5)',args),/reload|active driver|today|precede/);
  assert.equal((await history()).count,2);assert.equal((await f.read('drivers',d)).vehicle_id,v3);
 });
 await t.test('repeated transfers and explicit removals retain paginated history and prevent duplicate active rows',async()=>{
  for(let i=0;i<28;i++){const current=(await history()).rows[0];await f.db.query('select public.transfer_driver($1,$2,$3,$4,$5)',[d,i%2?v3:v2,f.today,'',current.id]);}
  assert.equal((await history()).count,30);assert.equal((await history()).rows.length,25);
  const page2=await f.scalar<{rows:Row[]}>('select public.driver_vehicle_history($1,2)',[d]);assert.equal(page2.rows.length,5);
  assert.equal(await f.scalar<number>('select count(*)::int from public.vehicle_driver_assignments where driver_id=$1 and ended_at is null',[d]),1);
  const current=(await history()).rows.find(r=>r.is_current)!;await f.db.query('select public.transfer_driver($1,null,$2,$3,$4)',[d,f.today,'End assignment',current.id]);assert.equal((await f.read('drivers',d)).vehicle_id,null);
 });
 await t.test('driver form transfer is atomic with identity, custom fields and optimistic assignment checks',async()=>{
  const before=await f.read('drivers',d);
  await f.save('drivers',{full_name:'Ahmed edited',mobile:'03000000099',vehicle_id:v2,assignment_date:f.today,assignment_reason:'New assignment'},d,Number(before.version),null,null);
  const saved=await f.read('drivers',d);assert.equal(saved.vehicle_id,v2);assert.equal(saved.assignment_reason,'New assignment');
  await assert.rejects(()=>f.save('drivers',{full_name:'Must roll back',mobile:'03000000099',vehicle_id:v3},d,Number(saved.version),null,randomUUID()),/reload/);
  assert.equal((await f.read('drivers',d)).full_name,'Ahmed edited');
  await f.asUser(true);await assert.rejects(()=>f.db.query('select public.transfer_driver($1,$2,$3,$4,$5)',[d,v3,f.today,'',saved.assignment_id]),/Permission|permission/);await f.asUser();
 });
 await t.test('editing leave status keeps an unchanged vehicle assignment and restores duty safely',async()=>{const r=await f.read('drivers',d);await f.save('drivers',{employment_status:'On Leave',vehicle_id:v2},d,Number(r.version),null,String(r.assignment_id));const leave=await f.read('drivers',d);assert.equal(leave.employment_status,'On Leave');assert.equal(leave.assignment_id,r.assignment_id);await f.save('drivers',{employment_status:'Active',vehicle_id:v2},d,Number(leave.version),null,String(leave.assignment_id));});
 await t.test('routes accept any locations, support edit/archive, reject duplicates and enforce permissions',async()=>{
  const id=await f.scalar<string>('select public.save_route(null,null,$1,$2)',['Toba Tek Singh','Lahore']);
  await f.db.query('select public.save_route($1,1,$2,$3)',[id,'Karachi','Islamabad']);
  assert.equal(await f.scalar<string>('select origin from public.routes where id=$1',[id]),'Karachi');
  await assert.rejects(()=>f.db.query('select public.save_route(null,null,$1,$2)',[' karachi ','ISLAMABAD']),/duplicate/);
  await assert.rejects(()=>f.db.query('select public.save_route($1,1,$2,$3)',[id,'A','B']),/reload/);
  await assert.rejects(()=>f.db.query('select public.save_route(null,null,$1,$2)',['Lahore','lahore']),/different/);
  await f.asUser(true);await assert.rejects(()=>f.db.query('select public.save_route(null,null,$1,$2)',['A','B']),/permission/);await f.asUser();
  await f.db.query('select public.save_route($1,2,$2,$3,true)',[id,'Karachi','Islamabad']);assert.equal(await f.scalar<boolean>('select archived from public.routes where id=$1',[id]),true);
 });
 await t.test('permit, insurance, maintenance and oil reminders deduplicate and resolve after service',async()=>{
  const m=await f.scalar<string>('select public.save_maintenance(null,null,$1,$2,$3)',[JSON.stringify({vehicle_id:v2,business_date:f.today,odometer:'1000',category:'oil_change',description:'TEST Oil',next_service_odometer:'1100'}),JSON.stringify([{kind:'Parts',description:'Oil',amount:'100'}]),JSON.stringify({specification:'15W40',quantity_litres:'5',next_due_odometer:'1100'})]);
  await f.db.query('select public.approve_maintenance($1,1,$2)',[m,randomUUID()]);await f.db.exec('reset role');await f.db.query('update public.vehicles set current_odometer=1200 where id=$1',[v2]);await f.asUser();await f.db.query('select public.reconcile_alerts()');
  const rows=await f.scalar<Row[]>('select jsonb_agg(to_jsonb(n)) from public.notifications n where vehicle_id=$1 and resolved_at is null',[v2]);
  for(const kind of ['Permit expiry','Insurance reminder','Service Reminder','Maintenance required'])assert.ok(rows.some(r=>r.type===kind),kind);
  assert.ok(rows.every(r=>String(r.message).includes('601')));
  const count=await f.scalar<number>('select count(*)::int from public.notifications');await f.db.query('select public.reconcile_alerts()');assert.equal(await f.scalar<number>('select count(*)::int from public.notifications'),count);
  const newOil=await f.scalar<string>('select public.save_maintenance(null,null,$1,$2,$3)',[JSON.stringify({vehicle_id:v2,business_date:f.today,odometer:'1200',category:'oil_change',description:'New service',next_service_odometer:'2200'}),JSON.stringify([{kind:'Parts',description:'Oil',amount:'100'}]),JSON.stringify({specification:'15W40',quantity_litres:'5',next_due_odometer:'2200'})]);await f.db.query('select public.approve_maintenance($1,1,$2)',[newOil,randomUUID()]);await f.db.query('select public.reconcile_alerts()');
  assert.equal(await f.scalar<number>("select count(*)::int from public.notifications where vehicle_id=$1 and type in ('Service Reminder','Maintenance required') and resolved_at is null",[v2]),0);
 });
 await t.test('notification counts, read dates, filters and per-user read state remain correct',async()=>{
  await f.db.exec('reset role');await f.db.query("insert into public.notifications(dedup_key,type,message,vehicle_id,action_link) select 'TEST-paged-'||i,'TEST Reminder','TEST paged notification',$1,'/vehicles' from generate_series(1,30) i",[v2]);await f.asUser();
  const unread=await f.scalar<{rows:Row[];count:number;unread_count:number}>("select public.notification_center('unread')");assert.ok(unread.unread_count>=32);assert.equal(unread.rows.length,25);assert.equal(unread.count,unread.unread_count);
  await f.db.query('select public.mark_notification_read($1)',[unread.rows[0].id]);const read=await f.scalar<{rows:Row[];count:number}>("select public.notification_center('read')");assert.equal(read.count,1);assert.ok(read.rows[0].read_at);
  assert.equal((await f.scalar<{unread_count:number}>("select public.notification_center('unread')")).unread_count,unread.unread_count-1);
  await f.asUser(true);assert.equal((await f.scalar<{count:number}>("select public.notification_center('read')")).count,0);await f.asUser();
 });
 await t.test('signatures cannot be removed from print settings',async()=>{await assert.rejects(()=>f.db.query("select public.save_print_template('trips',1,'portrait',array[]::text[])"),/check|signature/);});
});

test('Password-only upgrade preserves existing profiles, roles and sessions and is idempotent',async t=>{
 const f=await formFixture({throughMigration:'20261011100000_transport_enhancements.sql'});t.after(()=>f.db.close());
 const uid=randomUUID();await f.db.exec('reset role');
 await f.db.query('insert into auth.users(id,email,raw_app_meta_data) values($1,$2,$3)',[uid,'existing-profile@example.test',JSON.stringify({providers:['google']})]);
 await f.db.query('select public.server_google_user_sync($1,$2,$3)',[uid,'Existing Profile','https://example.test/avatar.png']);
 await f.db.query("update public.user_roles set role_id=(select id from public.roles where name='Viewer') where user_id=$1",[uid]);
 const profiles=()=>f.scalar("select jsonb_agg(to_jsonb(u) order by id) from public.app_users u");
 const roles=()=>f.scalar("select jsonb_agg(to_jsonb(r) order by user_id,role_id) from public.user_roles r");
 const sessions=()=>f.scalar("select jsonb_agg(to_jsonb(s) order by token_hash) from private.app_sessions s");
 const before=await Promise.all([profiles(),roles(),sessions()]);
 const migration=await readFile('supabase/migrations/20261011120000_password_login_only.sql','utf8');
 await f.db.exec(migration);await f.db.exec(migration);
 assert.deepEqual(await Promise.all([profiles(),roles(),sessions()]),before);
 assert.equal(await f.scalar("select to_regprocedure('public.server_google_user_sync(uuid,text,text)')"),null);
 await f.asUser();assert.equal((await f.read('drivers',f.driver)).vehicle_id,f.vehicle);
 assert.equal((await f.read('trips',f.trip)).profit,'44000.00');
});

const config=()=>parseConfig({APP_ENV:'development',APP_URL:'http://localhost:5173',ALLOWED_ORIGINS:'http://localhost:5173',SUPABASE_URL:'https://example.supabase.co',SUPABASE_PUBLISHABLE_KEY:'test-publishable-key-only',SUPABASE_SECRET_KEY:'test-privileged-key-only',SESSION_ENCRYPTION_KEY:randomBytes(32).toString('hex')});
test('Password login rejects invalid credentials, protects CSRF, enforces pending access and revokes logout (Auth mocked)',async t=>{
 const c=config(),raw=randomBytes(32).toString('base64url');let active=false,pending=true;
 const sessions:SessionService={
  login:async(email,password)=>{if(email!=='user@example.test'||password!=='test-password-only')throw new AppError(401,'INVALID_LOGIN','Email or password is incorrect.');active=true;return {raw,csrf:'test-csrf'};},
  authenticate:async value=>{if(value!==raw||!active)throw new AppError(401,'SIGN_IN_REQUIRED','Sign in');return {access:{user:{id:'test',display_name:'Staff User',email:'user@example.test'},permissions:pending?[]:['vehicles.view'],roles:pending?['Pending Access']:['Viewer']},csrf:'test-csrf'} as AuthContext;},
  logout:async()=>{active=false;return {remoteSignOutVerified:true};}
 };
 const admin={rpc:async()=>({data:true,error:null})} as unknown as Client;
 const server=createApp(c,{sessions,admin}).listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));t.after(()=>new Promise<void>(r=>server.close(()=>r())));
 const addr=server.address();if(!addr||typeof addr==='string')throw new Error();const base=`http://127.0.0.1:${addr.port}`;
 const req=(path:string,options:RequestInit={})=>fetch(base+path,{redirect:'manual',...options});
 assert.equal((await req('/api/auth/me')).status,401);
 assert.equal((await req('/api/auth/login',{method:'POST',headers:{Origin:c.APP_URL,'Content-Type':'application/json'},body:JSON.stringify({email:'user@example.test',password:'test-password-only'})})).status,403);
 const pre=await req('/api/auth/csrf'),csrf=(await pre.json()).csrf,preCookie=pre.headers.getSetCookie()[0].split(';')[0];
 const signIn=(password:string)=>req('/api/auth/login',{method:'POST',headers:{Origin:c.APP_URL,Cookie:preCookie,'X-CSRF-Token':csrf,'Content-Type':'application/json'},body:JSON.stringify({email:'user@example.test',password})});
 assert.equal((await signIn('incorrect-password')).status,401);assert.equal(active,false);
 const login=await signIn('test-password-only');assert.equal(login.status,200);assert.deepEqual(await login.json(),{csrf:'test-csrf'});
 const sessionCookie=login.headers.getSetCookie().find(v=>v.startsWith('gbt_dev_session='))!;assert.match(sessionCookie,/HttpOnly/);assert.match(sessionCookie,/SameSite=Strict/);assert.ok(!sessionCookie.includes('test-password-only'));
 const cookie=sessionCookie.split(';')[0];
 assert.equal((await req('/api/settings',{headers:{Cookie:cookie}})).status,403);
 assert.equal((await req('/api/auth/me',{headers:{Cookie:cookie}})).status,200);
 pending=false;const me=await req('/api/auth/me',{headers:{Cookie:cookie}});assert.deepEqual((await me.json()).permissions,['vehicles.view']);
 for(const path of ['/api/auth/providers','/api/auth/google/start','/api/auth/google/callback']){
  const response=await req(path,{headers:{Cookie:cookie}});assert.equal(response.status,404);assert.equal((await response.json()).error.code,'NOT_FOUND');
 }
 assert.equal((await req('/api/auth/google/start',{method:'POST',headers:{Origin:c.APP_URL,Cookie:cookie,'X-CSRF-Token':'test-csrf'}})).status,404);
 assert.equal((await req('/api/users',{headers:{Cookie:cookie}})).status,403);
 assert.equal((await req('/api/auth/logout',{method:'POST',headers:{Origin:c.APP_URL,Cookie:cookie,'X-CSRF-Token':'test-csrf'}})).status,200);
 assert.equal((await req('/api/auth/me',{headers:{Cookie:cookie}})).status,401);
});
test('Verified password credentials use the encrypted session broker; mismatched identity creates no session (remote Auth mocked)',async t=>{
 const c=config(),uid=randomUUID(),sid=randomUUID(),access='eyJhbGciOiJIUzI1NiJ9.'+Buffer.from(JSON.stringify({sub:uid,session_id:sid})).toString('base64url')+'.test-signature';const calls:{name:string;body:Row}[]=[];let mismatch=false;
 const user={id:uid,email:'staff@example.test',user_metadata:{},app_metadata:{providers:['email']}};
 const oldFetch=globalThis.fetch;t.after(()=>{globalThis.fetch=oldFetch;});
 globalThis.fetch=async(input,init)=>{
  const url=new URL(String(input));
  if(url.pathname==='/auth/v1/token'){
   assert.equal(url.searchParams.get('grant_type'),'password');assert.deepEqual(JSON.parse(String(init?.body)),{email:'staff@example.test',password:'test-password-only',gotrue_meta_security:{}});
   return Response.json({access_token:access,refresh_token:'test-refresh',expires_in:3600,expires_at:Math.floor(Date.now()/1000)+3600,token_type:'bearer',user});
  }
  if(url.pathname==='/auth/v1/user')return Response.json({...user,id:mismatch?randomUUID():uid});
  const name=url.pathname.split('/').at(-1)!;calls.push({name,body:JSON.parse(String(init?.body))});return Response.json(null);
 };
 const result=await createSessionService(c).login('staff@example.test','test-password-only');
 assert.deepEqual(calls.map(v=>v.name),['server_session_create']);const saved=calls[0].body;assert.equal(saved.p_user,uid);assert.equal(saved.p_auth_session,sid);assert.equal(saved.p_hash,hash(result.raw));
 assert.equal(decrypt<{access_token:string}>(c.SESSION_ENCRYPTION_KEY,String(saved.p_credentials),String(saved.p_hash)).access_token,access);assert.ok(!String(saved.p_credentials).includes('test-refresh'));
 mismatch=true;await assert.rejects(()=>createSessionService(c).login('staff@example.test','test-password-only'),/could not be verified/);assert.equal(calls.length,1);
});
test('All print pipelines include a signature and driver print safely includes history',async()=>{
 for(const kind of ['office','oil','monthly','combined','driver-details']){const doc=buildReference(kind,{metadata:{business_name:'TEST',from:'2026-01-01',to:'2026-01-31'}});const without={...doc,sections:doc.sections.filter(s=>s.role!=='signature')};assert.match(reportHtml(without),/Signature:/);const w=reportWorkbook(without);assert.ok(w.worksheets[0].getSheetValues().some(row=>String(row).includes('Signature:')));assert.match((await reportPdf(without)).subarray(0,4).toString(),/%PDF/);assert.ok(applyPrintSettings(without).sections.some(s=>s.role==='signature'));}
 assert.match(registerHtml({rows:[],metadata:{}},'Payments'),/Signature:/);
 const html=recordPrintHtml('drivers',{id:'test',full_name:'Ahmed',assignment_history:[{vehicle_number:'601',assigned_date:'2026-01-01',removed_date:'2026-03-10',reason:'<script>bad</script>'}]},{},{kind:'drivers',orientation:'portrait',signatures:[],version:1});assert.match(html,/Vehicle Assignment History/);assert.match(html,/601/);assert.match(html,/Signature:/);assert.ok(!html.includes('<script>bad</script>'));
});
