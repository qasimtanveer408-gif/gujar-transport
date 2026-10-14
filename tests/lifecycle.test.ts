import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {formFixture} from './helpers/form-fixture.js';
import {createTestDatabase} from '../scripts/test-sql.js';
import type {LifecyclePreview} from '../shared/lifecycle.js';

type Fixture=Awaited<ReturnType<typeof formFixture>>;
const preview=(f:Fixture,resource:string,id:string)=>f.scalar<LifecyclePreview>('select public.record_lifecycle_preview($1,$2)',[resource,id]);
const act=(f:Fixture,resource:string,id:string,action:string,v:number,token:string|null=null,confirmation:string|null=null)=>f.scalar('select public.record_lifecycle_action($1,$2,$3,$4,$5,$6,$7)',[resource,id,action,v,'TEST lifecycle reason',token,confirmation]);
async function purge(f:Fixture,resource:string,id:string){let p=await preview(f,resource,id);if(!p.archived_at){await act(f,resource,id,'archive',p.version);p=await preview(f,resource,id);}await act(f,resource,id,'delete',p.version,p.token,'DELETE');return p;}
async function count(f:Fixture,table:string){return Number(await f.scalar(`select count(*) from public.${table}`));}
async function approveTrip(f:Fixture){let r=await f.read('trips',f.trip);if(r.operational_state!=='Completed'){await f.db.query('select public.complete_form_trip($1,$2)',[f.trip,r.version]);r=await f.read('trips',f.trip);}await f.db.query('select public.trip_action($1,$2,$3,$4,$5)',[f.trip,'submit',r.version,'',randomUUID()]);r=await f.read('trips',f.trip);await f.db.query('select public.trip_action($1,$2,$3,$4,$5)',[f.trip,'approve',r.version,'',randomUUID()]);}

test('archive-first, restore, filters, permissions, stale previews and archived write guards',async()=>{
 const f=await formFixture();try{
  let p=await preview(f,'trips',f.trip);
  await assert.rejects(act(f,'trips',f.trip,'delete',p.version,p.token,'DELETE'),/Archive this record/);
  await f.asUser(true);await assert.rejects(preview(f,'trips',f.trip),/Permission denied/);await assert.rejects(act(f,'trips',f.trip,'archive',p.version),/Permission denied/);await f.asUser();
  await act(f,'trips',f.trip,'archive',p.version);p=await preview(f,'trips',f.trip);assert.ok(p.archived_at);
  const list=await f.scalar<{rows:unknown[];count:number}>('select public.form_register($1,$2,$3)',['trips',f.from,f.to]);assert.equal(list.count,0);
  const archived=await f.scalar<{count:number}>('select public.record_lifecycle_list($1,$2)',['trips','archived']);assert.equal(archived.count,1);
  await assert.rejects(f.save('trips',f.tripData,f.trip,p.version),/archived|Deleted drafts/);
  await assert.rejects(act(f,'trips',f.trip,'delete',p.version,p.token,'WRONG'),/Type DELETE/);
  await assert.rejects(act(f,'trips',f.trip,'delete',p.version,'0'.repeat(32),'DELETE'),/Related records changed/);
  await act(f,'trips',f.trip,'restore',p.version);assert.equal((await preview(f,'trips',f.trip)).archived_at,null);
  p=await preview(f,'vehicles',f.vehicle);await act(f,'vehicles',f.vehicle,'archive',p.version);
  assert.equal((await f.read('vehicles',f.vehicle)).status,'Archived');
  await assert.rejects(f.save('trips',{...f.tripData,cycle_number:'ARCHIVED-VEHICLE'}),/active|archived/);
  await act(f,'vehicles',f.vehicle,'restore',(await preview(f,'vehicles',f.vehicle)).version);
  assert.equal((await f.read('vehicles',f.vehicle)).status,'Active');
 }finally{await f.db.close();}
});

test('physical vehicle purge removes posted ledger, full payment allocations, documents and custom values while preserving unrelated masters',async()=>{
 const f=await formFixture();try{
  const other=await f.save('vehicles',{registration:'KEEP-002',manufacturer:'Keep',purchase_year:'2021'});
  await approveTrip(f);
  const commission=await f.scalar<string>('select id from public.driver_earnings where trip_line_id in(select id from public.trip_expense_lines where trip_id=$1)',[f.trip]);
  const salary=await f.scalar<string>('select public.accrue_earning($1,$2,$3,$4,$5,$6)',[f.driver,f.today,'Salary',5000,'TEST fixed salary',randomUUID()]);
  await f.db.query('select public.settle_driver_payment($1,$2,$3,$4,$5)',[f.driver,f.today,'TEST-PAYMENT',JSON.stringify([{earning_id:commission,amount:1000},{earning_id:salary,amount:1000}]),randomUUID()]);
  const file=await f.scalar<{id:string}>('select public.reserve_attachment($1,$2,$3,$4,$5)',['vehicles',f.vehicle,'test.pdf','application/pdf',10]);
  const before=await preview(f,'vehicles',f.vehicle);await act(f,'vehicles',f.vehicle,'archive',before.version);
  let p=await preview(f,'vehicles',f.vehicle);
  await f.db.query('select public.settle_driver_payment($1,$2,$3,$4,$5)',[f.driver,f.today,'TEST-SECOND-PAYMENT',JSON.stringify([{earning_id:commission,amount:500}]),randomUUID()]);
  await f.db.query('select public.close_period($1,1,$2)',[f.period,'TEST close']);
  await assert.rejects(act(f,'vehicles',f.vehicle,'delete',p.version,p.token,'DELETE'),/Related records changed/);
  p=await preview(f,'vehicles',f.vehicle);
  assert.ok(p.counts.some(r=>r.table==='driver_payments'));assert.ok(p.counts.some(r=>r.table==='attachments'));assert.ok(p.counts.some(r=>r.table==='period_close_snapshots'));
  assert.deepEqual(p.closed_periods,['TEST accounting period']);
  await act(f,'vehicles',f.vehicle,'delete',p.version,p.token,'DELETE');
  for(const table of ['trips','trip_expense_lines','trip_financials','trip_status_history','driver_payments','driver_payment_allocations','cash_transactions','revenue_entries','attachments','period_close_snapshots'])assert.equal(await count(f,table),0,table);
  assert.equal(await count(f,'vehicles'),1);assert.equal((await f.read('vehicles',other)).registration,'KEEP-002');assert.equal(await count(f,'drivers'),1);
  const statement=await f.scalar<{earnings:{id:string;remaining:string}[]}>('select public.driver_statement($1)',[f.driver]);assert.equal(statement.earnings.find(e=>e.id===salary)?.remaining,'5000.00');
  assert.equal(await f.scalar('select status from public.accounting_periods where id=$1',[f.period]),'Reopened');
  await f.db.exec('reset role');const jobs=await f.scalar<{payload:{object_path:string}}[]>('select public.server_deletion_jobs()');assert.ok(jobs.some(j=>j.payload.object_path.includes(file.id)));
 }finally{await f.db.close();}
});

test('accounting periods can be archived, restored and physically deleted, freeing their date range',async()=>{
 const f=await formFixture();try{
  await approveTrip(f);await f.db.query('select public.close_period($1,1,$2)',[f.period,'TEST close']);
  let p=await preview(f,'periods',f.period);await act(f,'periods',f.period,'archive',p.version);
  await assert.rejects(f.scalar('select public.create_period($1,$2,$3)',['OVERLAP',f.from,f.to]),/cannot overlap/);
  p=await preview(f,'periods',f.period);await act(f,'periods',f.period,'restore',p.version);assert.equal(await f.scalar('select status from public.accounting_periods where id=$1',[f.period]),'Closed');
  await purge(f,'periods',f.period);
  for(const table of ['accounting_periods','period_close_snapshots','trips','revenue_entries','expense_entries','driver_earnings'])assert.equal(await count(f,table),0,table);
  assert.equal(await count(f,'vehicles'),1);assert.equal(await count(f,'drivers'),1);
  assert.ok(await f.scalar('select public.create_period($1,$2,$3)',['TEST accounting period',f.from,f.to]));
 }finally{await f.db.close();}
});

test('loan disbursement deletion includes repayments; routes, companies, duties and assignments physically delete',async()=>{
 const f=await formFixture();try{
  const loanId=await f.scalar<string>('select public.loan_transaction(null,$1,$2,$3,$4,$5,$6,$7)',[f.driver,f.today,'Disbursement',10000,'TEST-LOAN',f.to,randomUUID()]);
  const loan=await f.scalar<string>('select id from public.driver_loan_transactions where loan_id=$1',[loanId]);
  await f.db.query('select public.loan_transaction($1,$2,$3,$4,$5,$6,null,$7)',[loanId,f.driver,f.today,'Repayment',2000,'TEST-REPAY',randomUUID()]);
  await purge(f,'loan-transactions',loan);assert.equal(await count(f,'driver_loans'),0);assert.equal(await count(f,'driver_loan_transactions'),0);assert.equal(await count(f,'cash_transactions'),0);
  const route=await f.scalar<string>('select public.save_route(null,null,$1,$2,false)',['TEST Lahore','TEST Karachi']);await purge(f,'routes',route);assert.equal(await count(f,'routes'),0);
  const company=await f.scalar<string>('select public.save_company($1)',['TEST company']);await purge(f,'companies',company);assert.equal(await count(f,'companies'),0);
  const assignment=await f.scalar<string>('select id from public.vehicle_driver_assignments where driver_id=$1',[f.driver]);await purge(f,'assignments',assignment);assert.equal(await count(f,'vehicle_driver_assignments'),0);
  await f.db.query('select public.set_driver_duty($1,true)',[f.driver]);const duty=await f.scalar<string>('select id from public.driver_duty_sessions where driver_id=$1',[f.driver]);await purge(f,'duty',duty);assert.equal(await count(f,'driver_duty_sessions'),0);
 }finally{await f.db.close();}
});

test('fresh SQL-editor installer applies all migrations, registers history and rejects accidental reuse',async()=>{
 const db=await createTestDatabase({throughMigration:'000'});try{
  const sql=await readFile('supabase/setup/NEW_DATABASE_SETUP.sql','utf8');await db.exec(sql);
  const migrationCount=(await readdir('supabase/migrations')).filter(name=>/^\d+_.+\.sql$/.test(name)).length;
  assert.equal(Number((await db.query<{n:number}>('select count(*) n from supabase_migrations.schema_migrations')).rows[0].n),migrationCount);
  await assert.rejects(db.exec(sql),/already contains the app/);await db.exec('rollback');
  assert.equal((await db.query('select count(*) from public.roles')).rows.length,1);
 }finally{await db.close();}
});

test('empty accounting period deletion removes exactly the reviewed row and preserves other periods and transactions',async()=>{
 const f=await formFixture();try{
  const period=await f.scalar<string>('select public.create_period($1,$2,$3)',['TEST empty October','2099-10-01','2099-10-31']);
  const p=await purge(f,'periods',period);
  assert.deepEqual(p.counts,[{table:'accounting_periods',count:1}]);assert.equal(p.total,1);
  assert.equal(await count(f,'accounting_periods'),1);assert.equal(await count(f,'trips'),1);
  assert.equal(await count(f,'vehicles'),1);assert.equal(await count(f,'drivers'),1);
  assert.ok(await f.scalar('select public.create_period($1,$2,$3)',['TEST October replacement','2099-10-01','2099-10-31']));
 }finally{await f.db.close();}
});

test('SQL-editor repair restores a missing delete RPC, preserves records, and can be rerun',async()=>{
 const f=await formFixture({throughMigration:'20261014120000_record_lifecycle.sql'});try{
  const period=await f.scalar<string>('select public.create_period($1,$2,$3)',['TEST repair October','2099-10-01','2099-10-31']);
  await act(f,'periods',period,'archive',1);
  const before=await preview(f,'periods',period);
  await f.db.exec('reset role');
  await f.db.exec('drop function public.record_lifecycle_action(text,text,text,integer,text,text,text)');
  const sql=await readFile('supabase/setup/REPAIR_RECORD_DELETE.sql','utf8');
  await f.db.exec(sql);await f.db.exec(sql);
  assert.equal(await f.scalar("select has_function_privilege('anon','public.record_lifecycle_action(text,text,text,integer,text,text,text)','EXECUTE')"),false);
  assert.equal(await f.scalar("select has_function_privilege('authenticated','public.record_lifecycle_action(text,text,text,integer,text,text,text)','EXECUTE')"),true);
  assert.equal(Number(await f.scalar("select count(*) from supabase_migrations.schema_migrations where version in ('20261014120000','20261014143000')")),2);
  await f.asUser();
  assert.equal(await count(f,'accounting_periods'),2);assert.equal(await count(f,'trips'),1);
  assert.deepEqual(await preview(f,'periods',period),before);
  await act(f,'periods',period,'delete',before.version,before.token,'DELETE');
  assert.equal(await count(f,'accounting_periods'),1);assert.equal(await count(f,'trips'),1);
 }finally{await f.db.close();}
});

test('SQL-editor repair installs missing lifecycle migration on an existing app without removing data',async()=>{
 const f=await formFixture({throughMigration:'20261011160000_master_review.sql'});try{
  await f.db.exec('reset role');
  const sql=await readFile('supabase/setup/REPAIR_RECORD_DELETE.sql','utf8');
  await f.db.exec(sql);await f.db.exec(sql);await f.asUser();
  assert.equal(await count(f,'trips'),1);assert.equal(await count(f,'vehicles'),1);
  assert.equal((await f.read('vehicles',f.vehicle)).registration,'TEST-001');
  await purge(f,'periods',f.period);
  assert.equal(await count(f,'accounting_periods'),0);assert.equal(await count(f,'trips'),0);
  assert.equal(await count(f,'vehicles'),1);assert.equal(await count(f,'drivers'),1);
 }finally{await f.db.close();}
});

test('maintenance, office expenses, bookings, import batches, notifications, custom values and accounts support archive and purge',async()=>{
 const f=await formFixture();try{
  const maintenance=await f.scalar<string>('select public.save_maintenance(null,null,$1,$2,null)',[JSON.stringify({vehicle_id:f.vehicle,driver_id:f.driver,business_date:f.today,odometer:'145400',category:'parts',description:'TEST repair'}),JSON.stringify([{kind:'Parts',description:'TEST filter',amount:500}])]);
  await f.db.query('select public.approve_maintenance($1,1,$2)',[maintenance,randomUUID()]);await purge(f,'maintenance',maintenance);assert.equal(await count(f,'maintenance_items'),0);
  const expense=await f.scalar<string>('select public.save_office_expense(null,null,$1)',[JSON.stringify({business_date:f.today,category:'Office',description:'TEST stationery',amount:600,payment_method:'Cash'})]);
  await f.db.query('select public.expense_action($1,$2,1,$3,$4)',[expense,'approve','',randomUUID()]);await purge(f,'office-expenses',expense);assert.equal(await count(f,'office_expenses'),0);
  const booking=await f.scalar<string>('select public.save_booking($1)',[JSON.stringify({business_date:f.today,external_vehicle:'TEST EXTERNAL',origin:'Lahore',destination:'Karachi',quoted_freight:10000,commission:400})]);
  await f.db.query('select public.approve_booking($1,1,$2)',[booking,randomUUID()]);await purge(f,'bookings',booking);assert.equal(await count(f,'office_bookings'),0);assert.equal(await count(f,'revenue_entries'),0);
  const imported=await f.scalar<string>('select public.prepare_import($1,$2,$3)',['vehicles','TEST import',JSON.stringify([{registration:'IMP-001',manufacturer:'Test',model:'Test',opening_odometer:'0',status:'Active'}])]);
  await purge(f,'imports',imported);assert.equal(await count(f,'import_rows'),0);
  const field=await f.scalar<string>('select public.save_custom_field(null,null,$1)',[JSON.stringify({resource:'vehicles',key:'cf_test',label:'Test field',type:'text',default_value:null,required:false,display_order:0,show_form:true,show_card:true,show_table:true,show_print:true,hidden:false,archived:false,restricted:false,options:[],formula:'',ast:null})]);
  const vr=await f.read('vehicles',f.vehicle);await f.save('vehicles',{registration:'TEST-001',manufacturer:'Test',purchase_year:'2020',custom_values:{cf_test:'Saved value'}},f.vehicle,Number(vr.version));
  await purge(f,'custom-fields',field);assert.equal(await count(f,'custom_field_values'),0);assert.equal(await count(f,'custom_field_definitions'),0);
  await f.db.exec('reset role');const notification=randomUUID();await f.db.query("insert into public.notifications(id,dedup_key,type,message,vehicle_id,action_link) values($1,'TEST','TEST','TEST reminder',$2,'/vehicles')",[notification,f.vehicle]);await f.asUser();
  await act(f,'notifications',notification,'archive',1);const notifications=await f.scalar<{rows:unknown[]}>('select public.notification_center()');assert.equal(notifications.rows.length,0);await purge(f,'notifications',notification);assert.equal(await count(f,'notifications'),0);
  const role=await f.scalar<string>("select public.save_role(null,'TEST removable',null,'[]')");await purge(f,'roles',role);assert.equal(Number(await f.scalar('select count(*) from public.roles where id=$1',[role])),0);
  const self=await f.scalar<string>('select auth.uid()');const target=randomUUID();await f.db.exec('reset role');await f.db.query("insert into auth.users(id,email) values($1,'remove@example.test')",[target]);await f.db.query("insert into public.app_users(id,email,display_name) values($1,'remove@example.test','TEST removable user')",[target]);await f.db.query('update public.vehicles set created_by=$1 where id=$2',[target,f.vehicle]);await f.asUser();
  await purge(f,'users',target);assert.equal(Number(await f.scalar('select count(*) from public.app_users where id=$1',[target])),0);assert.equal(await f.scalar('select created_by from public.vehicles where id=$1',[f.vehicle]),self);
  await assert.rejects(act(f,'users',self,'archive',1),/another administrator/);
 }finally{await f.db.close();}
});

test('a new unknown FK blocker rolls back the entire deletion; existing data upgrades in place',async()=>{
 const f=await formFixture({throughMigration:'20261011160000_master_review.sql'});try{
  await f.db.exec('reset role');await f.db.exec(await readFile('supabase/migrations/20261014120000_record_lifecycle.sql','utf8'));await f.asUser();
  assert.equal((await f.read('vehicles',f.vehicle)).registration,'TEST-001');assert.equal(await count(f,'trips'),1);
  await act(f,'vehicles',f.vehicle,'archive',(await preview(f,'vehicles',f.vehicle)).version);
  await f.db.exec('reset role');await f.db.exec('create table public.test_lifecycle_blocker(id uuid primary key,trip_id uuid references public.trips(id))');await f.db.query('insert into public.test_lifecycle_blocker values($1,$2)',[randomUUID(),f.trip]);await f.asUser();
  const p=await preview(f,'vehicles',f.vehicle);await assert.rejects(act(f,'vehicles',f.vehicle,'delete',p.version,p.token,'DELETE'),/foreign key/);
  assert.equal(await count(f,'vehicles'),1);assert.equal(await count(f,'trips'),1);assert.ok(await count(f,'trip_expense_lines')>0);
 }finally{await f.db.close();}
});
