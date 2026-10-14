import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {formFixture} from './helpers/form-fixture.js';
import type {LifecyclePreview} from '../shared/lifecycle.js';

type Fixture=Awaited<ReturnType<typeof formFixture>>;
const migration='supabase/migrations/20261014170000_lifecycle_delete_where_guard.sql';
const preview=(f:Fixture,resource:string,id:string)=>f.scalar<LifecyclePreview>('select public.record_lifecycle_preview($1,$2)',[resource,id]);
const act=(f:Fixture,resource:string,id:string,action:string,p:LifecyclePreview)=>f.scalar('select public.record_lifecycle_action($1,$2,$3,$4,$5,$6,$7)',[resource,id,action,p.version,'TEST scoped odometer repair',p.token,'DELETE']);
async function purge(f:Fixture,resource:string,id:string){
 let p=await preview(f,resource,id);
 if(!p.archived_at){await act(f,resource,id,'archive',p);p=await preview(f,resource,id);}
 await act(f,resource,id,'delete',p);
}
const odometer=(f:Fixture,id:string)=>f.scalar<string>('select current_odometer::text from public.vehicles where id=$1',[id]);

async function observeOdometerWrites(f:Fixture){
 await f.db.exec('reset role');
 // Observe actual writes, including unchanged values, to catch fleet-wide UPDATEs.
 // PGlite does not include the hosted Supabase safeupdate extension.
 await f.db.exec(`
  create table private.test_odometer_writes(vehicle_id uuid not null);
  create function private.test_observe_odometer() returns trigger language plpgsql set search_path='' as $$
  begin insert into private.test_odometer_writes values(new.id);return new;end $$;
  create trigger test_observe_odometer after update of current_odometer on public.vehicles
   for each row execute function private.test_observe_odometer();
 `);
 await f.asUser();
}
async function writes(f:Fixture){
 await f.db.exec('reset role');
 const result=(await f.db.query<{vehicle_id:string}>('select vehicle_id from private.test_odometer_writes order by vehicle_id')).rows.map(r=>r.vehicle_id);
 await f.asUser();return result;
}
async function approveTrip(f:Fixture){
 let r=await f.read('trips',f.trip);
 await f.db.query('select public.complete_form_trip($1,$2)',[f.trip,r.version]);
 r=await f.read('trips',f.trip);
 await f.db.query('select public.trip_action($1,$2,$3,$4,$5)',[f.trip,'submit',r.version,'',randomUUID()]);
 r=await f.read('trips',f.trip);
 await f.db.query('select public.trip_action($1,$2,$3,$4,$5)',[f.trip,'approve',r.version,'',randomUUID()]);
}
async function maintenance(f:Fixture,vehicle:string,reading:number){
 const id=await f.scalar<string>('select public.save_maintenance(null,null,$1,$2,null)',[
  JSON.stringify({vehicle_id:vehicle,business_date:f.today,odometer:String(reading),category:'parts',description:'TEST scoped repair'}),
  JSON.stringify([{kind:'Parts',description:'TEST filter',amount:500}])
 ]);
 await f.db.query('select public.approve_maintenance($1,1,$2)',[id,randomUUID()]);return id;
}

test('forward migration fixes empty-period fleet rewrites and preserves data, preview and permissions',async()=>{
 const f=await formFixture({throughMigration:'20261014143000_lifecycle_delete_repair.sql'});
 try{
  const period=await f.scalar<string>('select public.create_period($1,$2,$3)',['TEST empty October','2099-10-01','2099-10-31']);
  await act(f,'periods',period,'archive',await preview(f,'periods',period));
  const p=await preview(f,'periods',period);
  await observeOdometerWrites(f);
  // Demonstrate the old function's unintended write in a rolled-back transaction.
  await f.db.exec('begin');await act(f,'periods',period,'delete',p);
  assert.deepEqual(await writes(f),[f.vehicle]);await f.db.exec('rollback');
  await f.db.exec('reset role');
  const sql=await readFile(migration,'utf8');await f.db.exec(sql);await f.db.exec(sql);
  assert.equal(await f.scalar("select has_function_privilege('anon','public.record_lifecycle_action(text,text,text,integer,text,text,text)','EXECUTE')"),false);
  assert.equal(await f.scalar("select has_function_privilege('authenticated','public.record_lifecycle_action(text,text,text,integer,text,text,text)','EXECUTE')"),true);
  await f.asUser();assert.deepEqual(await preview(f,'periods',period),p);
  const vehicleBefore=await f.scalar('select to_jsonb(v) from public.vehicles v where id=$1',[f.vehicle]);
  await act(f,'periods',period,'delete',p);
  assert.deepEqual(await writes(f),[]);
  assert.deepEqual(await f.scalar('select to_jsonb(v) from public.vehicles v where id=$1',[f.vehicle]),vehicleBefore);
  assert.equal(Number(await f.scalar('select count(*) from public.trips')),1);
  assert.equal(Number(await f.scalar('select count(*) from public.accounting_periods')),1);
  assert.ok(await f.scalar('select public.create_period($1,$2,$3)',['TEST replacement October','2099-10-01','2099-10-31']));
 }finally{await f.db.close();}
});

test('trip and maintenance deletions recalculate only their vehicle using remaining approved readings',async()=>{
 const f=await formFixture();
 try{
  const other=await f.save('vehicles',{registration:'KEEP-ODOMETER',manufacturer:'Test',opening_odometer:'4321'});
  const repair=await maintenance(f,f.vehicle,144900);await approveTrip(f);
  assert.equal(Number(await odometer(f,f.vehicle)),145382);
  await observeOdometerWrites(f);
  await purge(f,'trips',f.trip);
  assert.equal(Number(await odometer(f,f.vehicle)),144900);
  assert.deepEqual(await writes(f),[f.vehicle]);
  await purge(f,'maintenance',repair);
  assert.equal(Number(await odometer(f,f.vehicle)),0);
  assert.equal(Number(await odometer(f,other)),4321);
  assert.deepEqual(await writes(f),[f.vehicle,f.vehicle]);
 }finally{await f.db.close();}
});

test('period purge recalculates every affected vehicle and leaves unrelated archived vehicles untouched',async()=>{
 const f=await formFixture();
 try{
  const maintained=await f.save('vehicles',{registration:'MAINT-ODOMETER',manufacturer:'Test',opening_odometer:'1000'});
  const other=await f.save('vehicles',{registration:'KEEP-ARCHIVED',manufacturer:'Test',opening_odometer:'4321'});
  await maintenance(f,maintained,2000);await approveTrip(f);
  await act(f,'vehicles',other,'archive',await preview(f,'vehicles',other));
  const otherBefore=await f.scalar('select to_jsonb(v) from public.vehicles v where id=$1',[other]);
  await observeOdometerWrites(f);await purge(f,'periods',f.period);
  assert.equal(Number(await odometer(f,f.vehicle)),0);
  assert.equal(Number(await odometer(f,maintained)),1000);
  assert.deepEqual(await writes(f),[f.vehicle,maintained].sort());
  assert.deepEqual(await f.scalar('select to_jsonb(v) from public.vehicles v where id=$1',[other]),otherBefore);
  assert.equal(Number(await f.scalar('select count(*) from public.trips')),0);
  assert.equal(Number(await f.scalar('select count(*) from public.maintenance_records')),0);
 }finally{await f.db.close();}
});
