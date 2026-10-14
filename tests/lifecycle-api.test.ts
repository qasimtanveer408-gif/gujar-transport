import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {createApp} from '../server/app.js';
import {parseConfig} from '../server/config.js';
import {drainDeletionJobs} from '../server/lifecycle.js';
import type {SessionService,AuthContext} from '../server/session.js';
import type {Client} from '../server/supabase.js';

test('lifecycle API enforces permission, CSRF, explicit confirmation and reviewed token',async t=>{
 const c=parseConfig({APP_ENV:'development',APP_URL:'http://localhost:5173',ALLOWED_ORIGINS:'http://localhost:5173',SUPABASE_URL:'https://example.supabase.co',SUPABASE_PUBLISHABLE_KEY:'TEST-publishable-key-only',SUPABASE_SECRET_KEY:'TEST-privileged-key-only',SESSION_ENCRYPTION_KEY:randomBytes(32).toString('hex')});
 let permissions=['vehicles.view'],calls=0;
 const db={rpc:async(name:string)=>{if(name==='record_lifecycle_action')calls++;return {data:{ok:true},error:null};}};
 const sessions={authenticate:async()=>({db,access:{user:{id:randomUUID(),display_name:'TEST',email:'test@example.test'},roles:['TEST'],permissions},csrf:'test-csrf'} as unknown as AuthContext)} as SessionService;
 const admin={rpc:async(name:string)=>({data:name==='server_deletion_jobs'?[]:true,error:null})} as unknown as Client;
 const server=createApp(c,{sessions,admin}).listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));t.after(()=>new Promise<void>(r=>server.close(()=>r())));
 const address=server.address();if(!address||typeof address==='string')throw new Error();const url=`http://127.0.0.1:${address.port}/api/lifecycle/vehicles/${randomUUID()}`;
 const post=(body:unknown,csrf='test-csrf')=>fetch(url,{method:'POST',headers:{Origin:c.APP_URL,'Content-Type':'application/json','X-CSRF-Token':csrf},body:JSON.stringify(body)});
 const body={action:'delete',version:2,reason:'TEST delete',token:'a'.repeat(32),confirmation:'DELETE'};
 assert.equal((await post(body)).status,403);permissions=['records.archive'];assert.equal((await post(body)).status,403);
 permissions=['records.archive','records.delete'];assert.equal((await post(body,'bad-csrf')).status,403);
 assert.equal((await post({...body,confirmation:null})).status,422);assert.equal((await post({...body,token:null})).status,422);assert.equal(calls,0);
 assert.equal((await post(body)).status,200);assert.equal(calls,1);
});

test('failed Storage cleanup remains queued, retries successfully, and missing Auth users are idempotent',async()=>{
 const jobs=[{id:randomUUID(),kind:'storage',payload:{bucket_id:'gbt-vehicles',object_path:'TEST/test.pdf'}},{id:randomUUID(),kind:'auth',payload:{user_id:randomUUID()}}];let fail=true;
 const admin={rpc:async(name:string,args:{p_id:string})=>{if(name==='server_deletion_jobs')return {data:[...jobs],error:null};const i=jobs.findIndex(j=>j.id===args.p_id);if(i>=0)jobs.splice(i,1);return {data:null,error:null};},storage:{from:()=>({remove:async()=>({error:fail?{message:'TEST outage'}:null})})},auth:{admin:{deleteUser:async()=>({error:{message:'Already deleted',code:'user_not_found',status:404}})}}} as unknown as Client;
 assert.equal((await drainDeletionJobs(admin)).pending,true);assert.equal(jobs.length,1);
 fail=false;assert.equal((await drainDeletionJobs(admin)).pending,false);assert.equal(jobs.length,0);
});
