import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,randomBytes} from 'node:crypto';
import {mkdtemp,mkdir,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {formFixture} from './helpers/form-fixture.js';
import {parseConfig} from '../server/config.js';
import {createApp,cookies} from '../server/app.js';
import {AppError} from '../server/errors.js';
import type {SessionService} from '../server/session.js';
import type {Client} from '../server/supabase.js';
import type {DataRow} from '../shared/report-contract.js';
import {formContract,registerColumns} from '../shared/form-contract.js';
import {validateForm} from '../server/form-validation.js';
import {SESSION_TTL_SECONDS} from '../shared/session-policy.js';

test('Forward review migration preserves business data, caps old/new sessions and retains driver remarks/history',async t=>{
 const f=await formFixture({throughMigration:'20261011120000_password_login_only.sql'});
 t.after(()=>f.db.close());
 await f.db.exec('reset role');
 const before=await f.scalar<DataRow>(`select jsonb_build_object(
  'vehicles',(select jsonb_agg(v) from public.vehicles v),
  'drivers',(select jsonb_agg(d) from public.drivers d),
  'trips',(select jsonb_agg(t) from public.trips t),
  'identity',(select jsonb_agg(i) from public.driver_identity_details i),
  'history',(select jsonb_agg(a) from public.vehicle_driver_assignments a),
  'settings',(select jsonb_agg(s) from public.business_settings s),
  'users',(select jsonb_agg(u) from public.app_users u),
  'roles',(select jsonb_agg(r) from public.user_roles r))`);
 await f.db.exec(`update private.app_sessions set
  created_at=now()-case when user_id=(select id from public.app_users where email='forms-viewer@example.test') then interval '4 hours' else interval '1 hour' end,
  expires_at=now()+interval '8 hours'`);
 await f.db.exec(await readFile('supabase/migrations/20261011160000_master_review.sql','utf8'));
 const after=await f.scalar<DataRow>(`select jsonb_build_object(
  'vehicles',(select jsonb_agg(v) from public.vehicles v),
  'drivers',(select jsonb_agg(d) from public.drivers d),
  'trips',(select jsonb_agg(t) from public.trips t),
  'identity',(select jsonb_agg(i) from public.driver_identity_details i),
  'history',(select jsonb_agg(a) from public.vehicle_driver_assignments a),
  'settings',(select jsonb_agg(s) from public.business_settings s),
  'users',(select jsonb_agg(u) from public.app_users u),
  'roles',(select jsonb_agg(r) from public.user_roles r))`);
 assert.deepEqual(after,before,'Migration must not alter business records or users');
 assert.equal(await f.scalar<number>(`select count(*)::int from private.app_sessions where expires_at=created_at+interval '3 hours'`),2);
 assert.equal(await f.scalar<number>(`select count(*)::int from private.app_sessions where expires_at>now()`),1);
 assert.equal(await f.scalar<unknown>(`select public.server_session_read(token_hash) from private.app_sessions where expires_at<now()`),null);
 const uid=await f.scalar<string>(`select id from public.app_users where email='forms-owner@example.test'`),sid=randomUUID(),hash='a'.repeat(64);
 await f.db.query('insert into auth.sessions(id,user_id) values($1,$2)',[sid,uid]);
 await f.db.query('select public.server_session_create($1,$2,$3,$4)',[hash,uid,sid,'ENCRYPTED TEST ONLY']);
 assert.equal(await f.scalar<number>(`select extract(epoch from (expires_at-created_at))::int from private.app_sessions where token_hash=$1`,[hash]),SESSION_TTL_SECONDS);
 await f.asUser();
 const original=await f.read('drivers',f.driver),remarks='Driver remarks\n<script>never execute</script>';
 await f.save('drivers',{remarks},f.driver,Number(original.version));
 const saved=await f.read('drivers',f.driver);
 assert.equal(saved.remarks,remarks);
 assert.equal(saved.full_name,original.full_name);
 assert.equal(saved.cnic,original.cnic);
 assert.equal(saved.assignment_id,original.assignment_id);
 assert.equal(await f.scalar<number>('select count(*)::int from public.vehicle_driver_assignments where driver_id=$1',[f.driver]),1);
 await assert.rejects(()=>f.save('drivers',{remarks:'Stale overwrite'},f.driver,Number(original.version)),/changed/i);
 await assert.rejects(()=>f.scalar('select public.server_session_create($1,$2,$3,$4)',['b'.repeat(64),uid,sid,'TEST']),/permission/i);
 await f.asUser(true);
 await assert.rejects(()=>f.save('drivers',{remarks:'Unauthorized'},f.driver,Number(saved.version)),/permission|sign in/i);
});

test('Required fields reuse storage keys, distinguish Inam/commission and validate choices/dates',()=>{
 for(const resource of ['vehicles','drivers','trips','maintenance'] as const){
  const keys=formContract[resource].fields.map(f=>f.key);
  assert.equal(keys.length,new Set(keys).size,resource+' duplicate fields');
 }
 assert.equal(formContract.drivers.fields.find(f=>f.key==='remarks')?.source,'drivers.remarks');
 assert.equal(registerColumns('drivers',[]).filter(f=>f.key==='remarks').length,1);
 assert.equal(formContract.trips.fields.find(f=>f.key==='reward')?.label,'Inam / reward (PKR)');
 assert.equal(formContract.trips.fields.find(f=>f.key==='commission')?.label,'Driver cycle commission (PKR)');
 assert.throws(()=>validateForm('drivers',{full_name:'A',mobile:'0300',employment_status:'administrator'},[]));
 assert.throws(()=>validateForm('drivers',{full_name:'A',mobile:'0300',joining_date:'2026-10-11',leaving_date:'2026-10-10'},[]),/Leaving date/);
 assert.throws(()=>validateForm('drivers',{full_name:'A',mobile:'0300',joining_date:'2026-02-30'},[]),/valid date/);
 assert.throws(()=>validateForm('drivers',{full_name:'A',mobile:'0300',cnic:'sensitive'},[]));
 assert.equal(validateForm('drivers',{full_name:'A',mobile:'0300',remarks:'Saved notes'},[]).remarks,'Saved notes');
});

test('Cookie lifetime, expired-cookie cleanup, private caching and crawler files work over HTTP',async t=>{
 const c=parseConfig({APP_ENV:'production',NODE_ENV:'production',ALLOW_LIVE_DATABASE_ACCESS:'true',APP_URL:'https://transport.example.test',ALLOWED_ORIGINS:'https://transport.example.test',SUPABASE_URL:'https://example.supabase.co',SUPABASE_PUBLISHABLE_KEY:'test-publishable-not-valid',SUPABASE_SECRET_KEY:'test-secret-not-valid',SESSION_ENCRYPTION_KEY:randomBytes(32).toString('hex')});
 assert.match(cookies(c,'TEST'),/Max-Age=10800/);
 assert.match(cookies(c,'TEST'),/^__Host-gbt_session=/);
 assert.match(cookies(c,'TEST'),/HttpOnly; Secure; SameSite=Strict/);
 const root=await mkdtemp(join(tmpdir(),'gbt-master-'));
 t.after(()=>rm(root,{recursive:true,force:true}));
 await mkdir(join(root,'assets'));
 await writeFile(join(root,'index.html'),'<!doctype html><title>TEST</title>');
 await writeFile(join(root,'assets','index-TESTHASH.js'),'export const test=true;');
 await writeFile(join(root,'logo.png'),'TEST');
 const sessions={authenticate:async()=>{throw new AppError(401,'SESSION_EXPIRED','Sign in again.');}} as unknown as SessionService;
 const admin={rpc:async()=>({data:true,error:null})} as unknown as Client;
 const server=createApp(c,{staticDir:root,sessions,admin}).listen(0,'127.0.0.1');
 await new Promise<void>(r=>server.once('listening',r));
 t.after(()=>new Promise<void>(r=>server.close(()=>r())));
 const addr=server.address();if(!addr||typeof addr==='string')throw new Error('No port');
 const base='http://127.0.0.1:'+addr.port;
 const api=await fetch(base+'/api/auth/me',{headers:{Cookie:'__Host-gbt_session=expired'}});
 assert.equal(api.status,401);assert.equal(api.headers.get('cache-control'),'no-store');
 assert.match(api.headers.get('set-cookie')??'',/Max-Age=0/);
 assert.match(api.headers.get('content-security-policy')??'',/frame-ancestors 'none'/);
 assert.equal((await fetch(base+'/drivers')).headers.get('cache-control'),'no-cache');
 assert.equal((await fetch(base+'/drivers')).headers.get('x-robots-tag'),'noindex, nofollow');
 assert.equal((await fetch(base+'/assets/index-TESTHASH.js')).headers.get('cache-control'),'public, max-age=31536000, immutable');
 assert.equal((await fetch(base+'/logo.png')).headers.get('cache-control'),'public, max-age=3600, must-revalidate');
 const robots=await fetch(base+'/robots.txt');assert.match(await robots.text(),/Disallow: \/\nSitemap: https:\/\/transport.example.test\/sitemap.xml/);
 const sitemap=await fetch(base+'/sitemap.xml'),xml=await sitemap.text();assert.match(sitemap.headers.get('content-type')??'',/xml/);assert.match(xml,/<urlset/);assert.ok(!xml.includes('/drivers'));
});
