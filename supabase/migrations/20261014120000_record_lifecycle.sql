-- Archive first; administrator-reviewed, transactional physical deletion.
-- Financial history is unchanged by archive. Purge removes the confirmed dependency graph.
insert into public.permissions(code,description) values
 ('records.archive','Archive and restore business records across all modules'),
 ('records.delete','Permanently delete records and their reviewed dependencies') on conflict do nothing;
insert into public.role_permissions(role_id,permission_code,scope)
 select r.id,p.code,'all' from public.roles r cross join public.permissions p
 where r.reserved and p.code in ('records.archive','records.delete') on conflict do nothing;

create table private.lifecycle_resources(resource text primary key, table_name text not null unique, key_column text not null default 'id', label_column text not null);
insert into private.lifecycle_resources(resource,table_name,key_column,label_column) values
 ('vehicles','vehicles','id','registration'),('drivers','drivers','id','full_name'),
 ('trips','trips','id','trip_number'),('maintenance','maintenance_records','id','description'),
 ('companies','companies','id','name'),('office-expenses','office_expenses','id','description'),
 ('bookings','office_bookings','id','origin'),('periods','accounting_periods','id','name'),
 ('loans','driver_loans','id','reference'),('loan-transactions','driver_loan_transactions','id','reference'),
 ('earnings','driver_earnings','id','kind'),('payments','driver_payments','id','reference'),
 ('cash','cash_transactions','id','reference'),('routes','routes','id','origin'),
 ('custom-fields','custom_field_definitions','id','label'),('documents','attachments','id','original_name'),
 ('assignments','vehicle_driver_assignments','id','remarks'),('duty','driver_duty_sessions','id','started_at'),
 ('imports','import_batches','id','original_reference'),('notifications','notifications','id','message'),
 ('users','app_users','id','display_name'),('roles','roles','id','name');
revoke all on private.lifecycle_resources from public,anon,authenticated;
do $$declare t record;begin
 for t in select * from private.lifecycle_resources loop
  execute format('alter table public.%I add column if not exists archived_at timestamptz',t.table_name);
  execute format('alter table public.%I add column if not exists version integer not null default 1',t.table_name);
  execute format('alter table public.%I add column if not exists archive_previous jsonb',t.table_name);
 end loop;
end $$;
update public.vehicles set archived_at=now(),archive_previous='{"status":"Active"}' where status='Archived';
update public.drivers set archived_at=now(),archive_previous='{"employment_status":"Active"}' where employment_status='Archived';
update public.routes set archived_at=now() where archived;
update public.custom_field_definitions set archived_at=now() where archived;

-- Only ownership relationships cascade. Deleting a company unlinks its vehicles;
-- deleting a driver/vehicle never deletes the other master record.
do $$declare c record;action text;definition text;begin
 for c in select fk.*,fk.conrelid::regclass::text child,fk.confrelid::regclass::text parent,
   (select attname from pg_attribute where attrelid=fk.conrelid and attnum=fk.conkey[1]) col
  from pg_constraint fk join pg_namespace n on n.oid=fk.connamespace
  where fk.contype='f' and n.nspname in ('public','private') loop
  action=null;
  if c.parent in ('companies','public.companies') then action='SET NULL';
  elsif c.parent in ('attachments','public.attachments') then action='SET NULL';
  elsif c.parent in ('vehicle_driver_assignments','public.vehicle_driver_assignments') then action='SET NULL';
  elsif c.parent in ('app_users','public.app_users') then
   if c.col in ('user_id') then action='CASCADE';
   elsif c.child in ('audit_logs','public.audit_logs','private.provisioning_tasks') then action='SET NULL';end if;
  elsif c.parent in ('roles','public.roles') then
   action=case when c.child='private.provisioning_tasks' then 'SET NULL' else 'CASCADE' end;
  elsif c.confrelid in (select cls.oid from pg_class cls join pg_namespace ns on ns.oid=cls.relnamespace where ns.nspname='public' and cls.relname=any(array[
   'vehicles','drivers','accounting_periods','trips','trip_expense_lines','maintenance_records','maintenance_items','office_expenses','office_bookings',
   'driver_earnings','driver_loans','driver_loan_transactions','driver_payments','revenue_entries','expense_entries','cash_transactions',
   'notifications','import_batches','custom_field_definitions'])) then action='CASCADE';end if;
  if action is not null then
   definition=regexp_replace(pg_get_constraintdef(c.oid),' ON DELETE (NO ACTION|RESTRICT|CASCADE|SET NULL|SET DEFAULT)','');
   execute format('alter table %s drop constraint %I',c.child,c.conname);
   execute format('alter table %s add constraint %I %s ON DELETE %s',c.child,c.conname,definition,action);
  end if;
 end loop;
end $$;

-- Outbox survives database deletion. File bytes and Auth users are removed only
-- through their official APIs, then these temporary queue rows are removed.
create table private.deletion_jobs(id uuid primary key default gen_random_uuid(),kind text not null check(kind in ('storage','auth')),payload jsonb not null,created_at timestamptz not null default now(),unique(kind,payload));
revoke all on private.deletion_jobs from public,anon,authenticated;
create function public.server_deletion_jobs() returns jsonb language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(j)),'[]') from (select * from private.deletion_jobs order by created_at,id limit 100) j
$$;
create function public.server_finish_deletion_job(p_id uuid) returns void language sql security definer set search_path='' as $$delete from private.deletion_jobs where id=p_id$$;
revoke all on function public.server_deletion_jobs(),public.server_finish_deletion_job(uuid) from public,anon,authenticated;
grant execute on function public.server_deletion_jobs(),public.server_finish_deletion_job(uuid) to service_role;

create function private.lifecycle_pk(p_rel oid,p_row jsonb) returns jsonb language sql stable set search_path='' as $$
 select jsonb_object_agg(a.attname,p_row->a.attname) from pg_index i join pg_attribute a on a.attrelid=i.indrelid and a.attnum=any(i.indkey)
 where i.indrelid=p_rel and i.indisprimary
$$;
create function private.lifecycle_add(p_rel oid,p_row jsonb) returns void language plpgsql set search_path='' as $$
begin
 if p_row is not null then insert into pg_temp.gbt_delete_plan(rel,pk,row_data) values(p_rel,private.lifecycle_pk(p_rel,p_row),p_row) on conflict do nothing;end if;
end $$;
create function private.lifecycle_plan(p_resource text,p_id text) returns jsonb language plpgsql security definer set search_path='' as $$
declare spec private.lifecycle_resources;root jsonb;item record;c record;joined text;previous_count integer=-1;current_count integer;summary jsonb;fingerprint text;dates date[];
begin
 select * into spec from private.lifecycle_resources where resource=p_resource;
 if spec.resource is null then raise exception 'Unknown record type';end if;
 execute format('select to_jsonb(t) from public.%I t where %I::text=$1',spec.table_name,spec.key_column) into root using p_id;
 if root is null then raise exception 'Record no longer exists';end if;
 drop table if exists pg_temp.gbt_delete_plan;
 create temporary table gbt_delete_plan(rel oid not null,pk jsonb not null,row_data jsonb not null,primary key(rel,pk)) on commit drop;
 revoke all on pg_temp.gbt_delete_plan from public,anon,authenticated;
 perform private.lifecycle_add(('public.'||spec.table_name)::regclass,root);
 -- A period owns its dated transactions and snapshots. A cross-period expense
 -- includes the whole source document to avoid partial accounting records.
 if p_resource='periods' then
  for item in select cl.oid,n.nspname,cl.relname from pg_class cl join pg_namespace n on n.oid=cl.relnamespace join pg_attribute a on a.attrelid=cl.oid
   where n.nspname='public' and cl.relkind='r' and a.attname='business_date' and not a.attisdropped loop
   execute format('insert into pg_temp.gbt_delete_plan select $1,private.lifecycle_pk($1,to_jsonb(t)),to_jsonb(t) from %I.%I t where business_date between $2 and $3 on conflict do nothing',item.nspname,item.relname) using item.oid,(root->>'start_date')::date,(root->>'end_date')::date;
  end loop;
 end if;
 loop
  select count(*) into current_count from pg_temp.gbt_delete_plan;
  exit when current_count=previous_count;previous_count=current_count;
  -- Follow only the explicitly configured cascading ownership edges.
  for c in select fk.conrelid,fk.confrelid,fk.conkey,fk.confkey from pg_constraint fk where fk.contype='f' and fk.confdeltype='c' and fk.confrelid in(select rel from pg_temp.gbt_delete_plan) loop
   select string_agg(format('to_jsonb(t)->%L = p.row_data->%L',a.attname,b.attname),' and ') into joined
    from unnest(c.conkey,c.confkey) as k(child,parent) join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.child join pg_attribute b on b.attrelid=c.confrelid and b.attnum=k.parent;
   execute format('insert into pg_temp.gbt_delete_plan select $1,private.lifecycle_pk($1,to_jsonb(t)),to_jsonb(t) from %s t where exists(select 1 from pg_temp.gbt_delete_plan p where p.rel=$2 and %s) on conflict do nothing',c.conrelid::regclass,joined) using c.conrelid,c.confrelid;
  end loop;
  -- A partially removed payment or cash settlement would misstate balances:
  -- include its entire parent and all allocations in the confirmation graph.
  for item in select 'public.driver_payments'::regclass::oid rel,to_jsonb(t) data from public.driver_payments t where exists(select 1 from public.driver_payment_allocations a join pg_temp.gbt_delete_plan p on p.rel='public.driver_earnings'::regclass and p.row_data->>'id'=a.earning_id::text where a.payment_id=t.id)
   union all select 'public.cash_transactions'::regclass::oid,to_jsonb(t) from public.cash_transactions t where exists(select 1 from public.settlement_allocations a join pg_temp.gbt_delete_plan p on (p.rel='public.revenue_entries'::regclass and p.row_data->>'id'=a.revenue_entry_id::text) or (p.rel='public.expense_entries'::regclass and p.row_data->>'id'=a.expense_entry_id::text) where a.cash_transaction_id=t.id)
   -- Deleting a disbursement includes later repayments; never leave a negative loan.
   union all select 'public.driver_loans'::regclass::oid,to_jsonb(t) from public.driver_loans t join pg_temp.gbt_delete_plan p on p.rel='public.driver_loan_transactions'::regclass and p.row_data->>'loan_id'=t.id::text and p.row_data->>'kind' in ('Opening','Disbursement')
   union all select 'public.trips'::regclass::oid,to_jsonb(t) from public.trips t join public.trip_expense_lines l on l.trip_id=t.id join pg_temp.gbt_delete_plan p on p.rel='public.driver_earnings'::regclass and p.row_data->>'trip_line_id'=l.id::text
   -- Source lines and derived postings belong to a whole source document.
   union all select 'public.trips'::regclass::oid,to_jsonb(t) from public.trips t join pg_temp.gbt_delete_plan p on p.rel in ('public.trip_expense_lines'::regclass,'public.revenue_entries'::regclass,'public.expense_entries'::regclass) and p.row_data->>'trip_id'=t.id::text
   union all select 'public.maintenance_records'::regclass::oid,to_jsonb(t) from public.maintenance_records t join public.maintenance_items mi on mi.maintenance_id=t.id join pg_temp.gbt_delete_plan p on p.rel='public.expense_entries'::regclass and p.row_data->>'maintenance_item_id'=mi.id::text
   union all select 'public.office_expenses'::regclass::oid,to_jsonb(t) from public.office_expenses t join pg_temp.gbt_delete_plan p on p.rel='public.expense_entries'::regclass and p.row_data->>'office_expense_id'=t.id::text
   union all select 'public.driver_earnings'::regclass::oid,to_jsonb(t) from public.driver_earnings t join pg_temp.gbt_delete_plan p on p.rel='public.expense_entries'::regclass and p.row_data->>'earning_id'=t.id::text
   union all select 'public.office_bookings'::regclass::oid,to_jsonb(t) from public.office_bookings t join pg_temp.gbt_delete_plan p on p.rel='public.revenue_entries'::regclass and p.row_data->>'booking_id'=t.id::text
   union all select 'public.driver_payments'::regclass::oid,to_jsonb(t) from public.driver_payments t join pg_temp.gbt_delete_plan p on p.rel='public.cash_transactions'::regclass and p.row_data->>'driver_payment_id'=t.id::text
   union all select 'public.driver_loan_transactions'::regclass::oid,to_jsonb(t) from public.driver_loan_transactions t join pg_temp.gbt_delete_plan p on p.rel='public.cash_transactions'::regclass and p.row_data->>'loan_transaction_id'=t.id::text
   union all select 'public.custom_field_definitions'::regclass::oid,to_jsonb(t) from public.custom_field_definitions t join pg_temp.gbt_delete_plan p on p.rel='public.custom_field_definitions'::regclass and p.row_data->>'resource'=t.resource and p.row_data->>'key'=any(t.dependencies)
  loop perform private.lifecycle_add(item.rel,item.data);end loop;
  for item in select 'public.period_close_snapshots'::regclass::oid rel,to_jsonb(s) data from public.period_close_snapshots s join public.accounting_periods ap on ap.id=s.period_id where exists(select 1 from pg_temp.gbt_delete_plan p where p.row_data->>'business_date' is not null and (p.row_data->>'business_date')::date between ap.start_date and ap.end_date) loop perform private.lifecycle_add(item.rel,item.data);end loop;
  -- Polymorphic values and import references do not have ordinary foreign keys.
  for item in select 'public.custom_field_values'::regclass::oid rel,to_jsonb(v) data from public.custom_field_values v join private.lifecycle_resources r on r.resource=v.resource join pg_temp.gbt_delete_plan p on p.rel=('public.'||r.table_name)::regclass and p.row_data->>'id'=v.record_id::text
   union all select 'public.import_rows'::regclass::oid,to_jsonb(v) from public.import_rows v join public.import_batches b on b.id=v.batch_id join private.lifecycle_resources r on r.resource=b.resource join pg_temp.gbt_delete_plan p on p.rel=('public.'||r.table_name)::regclass and p.row_data->>'id'=v.record_id::text
   union all select 'public.idempotency_keys'::regclass::oid,to_jsonb(v) from public.idempotency_keys v join pg_temp.gbt_delete_plan p on p.row_data->>'id'=v.record_id::text
  loop perform private.lifecycle_add(item.rel,item.data);end loop;
 end loop;
 select coalesce(jsonb_agg(jsonb_build_object('table',name,'count',n) order by name),'[]') into summary from(select cls.relname name,count(*) n from pg_temp.gbt_delete_plan p join pg_class cls on cls.oid=p.rel group by cls.relname)s;
 select md5(string_agg(rel::text||pk::text||row_data::text,'|' order by rel,pk::text)) into fingerprint from pg_temp.gbt_delete_plan;
 select array_agg(distinct (row_data->>'business_date')::date) into dates from pg_temp.gbt_delete_plan where row_data ? 'business_date' and row_data->>'business_date' is not null;
 return jsonb_build_object('resource',p_resource,'id',p_id,'label',coalesce(root->>spec.label_column,p_id),'version',(root->>'version')::integer,'archived_at',root->'archived_at','token',fingerprint,'counts',summary,'total',(select count(*) from pg_temp.gbt_delete_plan),
  'closed_periods',(select coalesce(jsonb_agg(name),'[]') from public.accounting_periods where status='Closed' and exists(select 1 from unnest(dates)d where d between start_date and end_date)),
  'cross_period',p_resource='periods' and exists(select 1 from unnest(dates)d where d<(root->>'start_date')::date or d>(root->>'end_date')::date),
  'protected',p_resource='roles' and coalesce((root->>'reserved')::boolean,false) or p_resource='users' and p_id=auth.uid()::text);
end $$;

create function public.record_lifecycle_preview(p_resource text,p_id text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.can('records.archive') and not private.can('records.delete') then raise exception 'Permission denied' using errcode='42501';end if;
 return private.lifecycle_plan(p_resource,p_id);
end $$;
create function public.record_lifecycle_list(p_resource text,p_state text default 'active',p_page integer default 1,p_search text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare spec private.lifecycle_resources;rows jsonb;total integer;predicate text;
begin
 if not private.can('records.archive') and not private.can('records.delete') then raise exception 'Permission denied' using errcode='42501';end if;
 select * into spec from private.lifecycle_resources where resource=p_resource;
 if spec.resource is null or p_state not in ('active','archived','all') or p_page<1 or p_page>100000 or length(p_search)>100 then raise exception 'Invalid record filter';end if;
 predicate=case p_state when 'active' then 'archived_at is null' when 'archived' then 'archived_at is not null' else 'true' end||format(' and coalesce(%I::text,'''') ilike $1',spec.label_column);
 execute format('select count(*) from public.%I where %s',spec.table_name,predicate) into total using '%'||replace(replace(replace(p_search,'\','\\'),'%','\%'),'_','\_')||'%';
 execute format('select coalesce(jsonb_agg(row),''[]'') from(select jsonb_build_object(''id'',%I,''label'',coalesce(%I::text,%I::text),''version'',version,''archived_at'',archived_at) row from public.%I where %s order by %I::text,%I limit 25 offset $2)s',spec.key_column,spec.label_column,spec.key_column,spec.table_name,predicate,spec.label_column,spec.key_column) into rows using '%'||replace(replace(replace(p_search,'\','\\'),'%','\%'),'_','\_')||'%',(p_page-1)*25;
 return jsonb_build_object('rows',rows,'count',total,'page',p_page);
end $$;

create function public.record_lifecycle_action(p_resource text,p_id text,p_action text,p_version integer,p_reason text,p_token text default null,p_confirmation text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare spec private.lifecycle_resources;root jsonb;preview jsonb;item record;c record;old_previous jsonb;dates date[];counts jsonb;
begin
 if p_action not in ('archive','restore','delete') or p_version is null or length(trim(coalesce(p_reason,''))) not between 3 and 300 then raise exception 'Choose an action and enter a reason (3 to 300 characters)';end if;
 perform private.require_permission(case when p_action='delete' then 'records.delete' else 'records.archive' end);
 -- Same lock order as identity, assignments, accounting and alert workflows.
 perform pg_advisory_xact_lock(87413001);perform pg_advisory_xact_lock(87413002);perform pg_advisory_xact_lock(87413003);perform pg_advisory_xact_lock(87413004);
 select * into spec from private.lifecycle_resources where resource=p_resource;
 if spec.resource is null then raise exception 'Unknown record type';end if;
 -- Serialize the short preview-check/delete transaction with every public writer.
 -- The reviewed token is recalculated after the locks, including all child rows.
 for item in select cls.oid from pg_class cls join pg_namespace n on n.oid=cls.relnamespace where n.nspname='public' and cls.relkind='r' order by cls.oid loop
  execute format('lock table %s in share row exclusive mode',item.oid::regclass);
 end loop;
 execute format('select to_jsonb(t) from public.%I t where %I::text=$1 for update',spec.table_name,spec.key_column) into root using p_id;
 if root is null then raise exception 'Record no longer exists';end if;
 if (root->>'version')::integer is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
 if p_resource='roles' and (root->>'reserved')::boolean then raise exception 'The built-in Super Admin role is required by the application';end if;
 if p_resource='users' and p_id=auth.uid()::text then raise exception 'Sign in with another administrator before removing your own account';end if;
 if p_resource='users' and exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=p_id::uuid and r.reserved)
  and not exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id join public.app_users u on u.id=ur.user_id where ur.user_id<>p_id::uuid and r.reserved and u.active and u.archived_at is null) then raise exception 'Keep at least one active Super Admin';end if;
 perform set_config('gbt.lifecycle','on',true);
 if p_action='archive' then
  if root->>'archived_at' is not null then raise exception 'Record is already archived';end if;
  if p_resource='custom-fields' and exists(select 1 from public.custom_field_definitions where resource=root->>'resource' and not archived and root->>'key'=any(dependencies)) then raise exception 'Archive the formulas that use this field first (Fields & print settings)';end if;
  old_previous=case p_resource when 'vehicles' then jsonb_build_object('status',root->'status') when 'drivers' then jsonb_build_object('employment_status',root->'employment_status') when 'users' then jsonb_build_object('active',root->'active') when 'assignments' then jsonb_build_object('ended_at',root->'ended_at') when 'duty' then jsonb_build_object('ended_at',root->'ended_at') when 'roles' then jsonb_build_object('grants',(select coalesce(jsonb_agg(to_jsonb(rp)),'[]') from public.role_permissions rp where role_id=p_id::uuid)) else '{}' end;
  execute format('update public.%I set archived_at=now(),archive_previous=$2,version=version+1 where %I::text=$1',spec.table_name,spec.key_column) using p_id,old_previous;
  if p_resource='vehicles' then update public.vehicles set status='Archived' where id=p_id::uuid;
  elsif p_resource='drivers' then update public.drivers set employment_status='Archived' where id=p_id::uuid;
  elsif p_resource='routes' then update public.routes set archived=true where id=p_id::uuid;
  elsif p_resource='custom-fields' then update public.custom_field_definitions set archived=true where id=p_id::uuid;
  elsif p_resource='users' then update public.app_users set active=false where id=p_id::uuid;update private.app_sessions set revoked_at=now() where user_id=p_id::uuid;
  elsif p_resource='roles' then delete from public.role_permissions where role_id=p_id::uuid;
  elsif p_resource in ('assignments','duty') then execute format('update public.%I set ended_at=coalesce(ended_at,greatest(now(),started_at)) where id=$1',spec.table_name) using p_id::uuid;
  end if;
 elsif p_action='restore' then
  if root->>'archived_at' is null then raise exception 'Record is already active';end if;
  -- Never restore a child while its owning master is archived.
  for c in select con.confrelid,(select attname from pg_attribute where attrelid=con.conrelid and attnum=con.conkey[1]) col from pg_constraint con join private.lifecycle_resources r on con.confrelid=('public.'||r.table_name)::regclass where con.contype='f' and con.conrelid=('public.'||spec.table_name)::regclass and array_length(con.conkey,1)=1 and r.key_column='id' loop
   if root->>c.col is not null then
    execute format('select to_jsonb(t) from %s t where id::text=$1 and archived_at is not null',c.confrelid::regclass) into old_previous using root->>c.col;
    if old_previous is not null then raise exception 'Restore the linked % record first',c.col;end if;
   end if;
  end loop;
  old_previous=coalesce(root->'archive_previous','{}');
  execute format('update public.%I set archived_at=null,archive_previous=null,version=version+1 where %I::text=$1',spec.table_name,spec.key_column) using p_id;
  if p_resource='vehicles' then update public.vehicles set status=coalesce(old_previous->>'status','Active') where id=p_id::uuid;
  elsif p_resource='drivers' then update public.drivers set employment_status=coalesce(old_previous->>'employment_status','Active') where id=p_id::uuid;
  elsif p_resource='routes' then update public.routes set archived=false where id=p_id::uuid;
  elsif p_resource='custom-fields' then
   if exists(select 1 from unnest((select dependencies from public.custom_field_definitions where id=p_id::uuid)) d where d like 'cf_%' and not exists(select 1 from public.custom_field_definitions where resource=root->>'resource' and key=d and not archived)) then raise exception 'Restore this formula''s source fields first';end if;
   update public.custom_field_definitions set archived=false where id=p_id::uuid;
  elsif p_resource='users' then update public.app_users set active=coalesce((old_previous->>'active')::boolean,true) where id=p_id::uuid;
  elsif p_resource='roles' then insert into public.role_permissions(role_id,permission_code,scope) select p_id::uuid,g->>'permission_code',g->>'scope' from jsonb_array_elements(old_previous->'grants') g;
  elsif p_resource in ('assignments','duty') then execute format('update public.%I set ended_at=$2 where id=$1',spec.table_name) using p_id::uuid,(old_previous->>'ended_at')::timestamptz;
  end if;
 else
  if root->>'archived_at' is null then raise exception 'Archive this record before permanently deleting it';end if;
  if p_confirmation is distinct from 'DELETE' then raise exception 'Type DELETE to confirm permanent removal';end if;
  preview=private.lifecycle_plan(p_resource,p_id);
  if p_token is distinct from preview->>'token' then raise exception 'Related records changed; review the deletion again' using errcode='40001';end if;
  counts=preview->'counts';
  select array_agg(distinct (row_data->>'business_date')::date) into dates from pg_temp.gbt_delete_plan where row_data->>'business_date' is not null;
  insert into private.deletion_jobs(kind,payload) select 'storage',jsonb_build_object('bucket_id',row_data->>'bucket_id','object_path',row_data->>'object_path') from pg_temp.gbt_delete_plan where rel='public.attachments'::regclass on conflict do nothing;
  if p_resource='users' then
   -- Retain business transactions; transfer ownership to the acting administrator.
   for c in select con.conrelid,(select attname from pg_attribute where attrelid=con.conrelid and attnum=con.conkey[1]) col from pg_constraint con where con.contype='f' and con.confrelid='public.app_users'::regclass and con.confdeltype not in ('c','n') loop
    execute format('update %s set %I=$2 where %I=$1',c.conrelid::regclass,c.col,c.col) using p_id::uuid,auth.uid();
   end loop;
   delete from private.provisioning_tasks where user_id=p_id::uuid;
   insert into private.deletion_jobs(kind,payload) values('auth',jsonb_build_object('user_id',p_id)) on conflict do nothing;
  end if;
  -- Cascade is a database constraint, not best-effort HTTP calls. All business
  -- rows, child values and linked ledger entries disappear in this transaction.
  for item in select * from pg_temp.gbt_delete_plan order by rel,pk::text loop
   execute format('delete from %s t where to_jsonb(t) @> $1',item.rel::regclass) using item.pk;
  end loop;
  -- Invalidate old closed totals affected by a purge, including linked payments
  -- dated outside the selected period. No stale monetary snapshot is retained.
  delete from public.period_close_snapshots s using public.accounting_periods p where s.period_id=p.id and exists(select 1 from unnest(dates)d where d between p.start_date and p.end_date);
  update public.accounting_periods p set status='Reopened',version=version+1 where status='Closed' and exists(select 1 from unnest(dates)d where d between p.start_date and p.end_date);
  update public.vehicles v set current_odometer=greatest(v.opening_odometer,coalesce((select max(end_odometer) from public.trips where vehicle_id=v.id and financial_state='Approved'),0),coalesce((select max(odometer) from public.maintenance_records where vehicle_id=v.id and state='Approved'),0));
 end if;
 perform private.audit('record.'||p_action,p_resource,p_id,p_reason);
 perform set_config('gbt.lifecycle','off',true);
 return jsonb_build_object('ok',true,'action',p_action,'counts',counts);
end $$;
revoke all on function private.lifecycle_pk(oid,jsonb),private.lifecycle_add(oid,jsonb),private.lifecycle_plan(text,text),public.record_lifecycle_preview(text,text),public.record_lifecycle_list(text,text,integer,text),public.record_lifecycle_action(text,text,text,integer,text,text,text) from public,anon,authenticated;
grant execute on function public.record_lifecycle_preview(text,text),public.record_lifecycle_list(text,text,integer,text),public.record_lifecycle_action(text,text,text,integer,text,text,text) to authenticated;

-- Archived forms are read-only at the database boundary, including direct RPC
-- callers. New/changed references cannot point to archived records.
create function private.lifecycle_write_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare c record;payload jsonb=to_jsonb(new);old_payload jsonb;linked boolean;
begin
 if current_setting('gbt.lifecycle',true)='on' and (private.can('records.archive') or private.can('records.delete')) then return new;end if;
 if tg_op='UPDATE' then
  old_payload=to_jsonb(old);
  if tg_table_name='vehicles' and payload->>'status'='Archived' and old_payload->>'archived_at' is null then
   new.archived_at=coalesce(new.archived_at,now());new.archive_previous=jsonb_build_object('status',old_payload->>'status');
  elsif tg_table_name='drivers' and payload->>'employment_status'='Archived' and old_payload->>'archived_at' is null then
   new.archived_at=coalesce(new.archived_at,now());new.archive_previous=jsonb_build_object('employment_status',old_payload->>'employment_status');
  elsif tg_table_name in ('routes','custom_field_definitions') and payload->>'archived'='true' and old_payload->>'archived_at' is null then new.archived_at=coalesce(new.archived_at,now());
  end if;
  if old_payload->>'archived_at' is not null and payload is distinct from old_payload then raise exception 'Restore this archived record before editing it';end if;
 end if;
 for c in select con.confrelid,(select attname from pg_attribute where attrelid=con.conrelid and attnum=con.conkey[1]) col from pg_constraint con join private.lifecycle_resources r on con.confrelid=('public.'||r.table_name)::regclass where con.contype='f' and con.conrelid=tg_relid and array_length(con.conkey,1)=1 and r.key_column='id' loop
  if payload->>c.col is not null and (tg_op='INSERT' or payload->c.col is distinct from old_payload->c.col) then
   execute format('select exists(select 1 from %s where id::text=$1 and archived_at is not null)',c.confrelid::regclass) into linked using payload->>c.col;
   if linked then raise exception 'The linked % record is archived; restore it first',c.col;end if;
  end if;
 end loop;
 return new;
end $$;
do $$declare t record;begin
 for t in select c.oid,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relname not in ('audit_logs','notifications','notification_reads') loop
  execute format('create trigger lifecycle_write_guard before insert or update on public.%I for each row execute function private.lifecycle_write_guard()',t.relname);
 end loop;
end $$;
revoke all on function private.lifecycle_write_guard() from public,anon,authenticated;

-- Extend the register without creating ambiguous PostgREST overloads.
alter function public.list_records(text,text,integer,integer,date,date,uuid,uuid) rename to list_records_before_lifecycle;
create or replace function public.list_records(p_resource text,p_search text default '',p_page integer default 1,p_limit integer default 25,p_from date default null,p_to date default null,p_vehicle uuid default null,p_driver uuid default null,p_include_archived boolean default false) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tbl text;cols text[];search_col text;date_col text;expr text='';col text;predicate text='true';q text;rows jsonb;total bigint;
begin
 if not private.active_session() then raise exception 'Sign in required' using errcode='42501';end if;
 if p_page<1 or p_page>100000 or p_limit not between 1 and 1000 or length(p_search)>100 then raise exception 'Invalid pagination';end if;
 case p_resource
 when 'vehicles' then tbl='vehicles';cols=array['id','registration','manufacturer','model','owner_company_id','vehicle_class','purchase_date','opening_odometer','current_odometer','status','service_interval_km','fuel_target','document_expiry','remarks','version','created_by'];search_col='registration';
 when 'companies' then tbl='companies';cols=array['id','name','version'];search_col='name';
 when 'drivers' then tbl='drivers';cols=array['id','full_name','mobile','joining_date','leaving_date','licence_expiry','employment_status','remarks','version','created_by'];search_col='full_name';
 when 'trips' then tbl='trips';cols=array['id','trip_number','business_date','vehicle_id','driver_id','cycle_number','origin','destination','route_description','cargo','customer_reference','operational_state','financial_state','start_odometer','end_odometer','fuel_litres','fuel_basis','weight','weight_unit','remarks','version','created_by'];search_col='trip_number';date_col='business_date';
 when 'maintenance' then tbl='maintenance_records';cols=array['id','vehicle_id','driver_id','trip_id','business_date','odometer','category','description','supplier','next_service_date','next_service_odometer','remarks','state','version','created_by'];search_col='description';date_col='business_date';
 when 'office-expenses' then tbl='office_expenses';cols=array['id','business_date','category','description','amount','vehicle_id','driver_id','payment_method','remarks','state','version'];search_col='description';date_col='business_date';
 when 'bookings' then tbl='office_bookings';cols=array['id','business_date','trip_id','external_vehicle','driver_contact','cargo','origin','destination','quoted_freight','commission','description','state','version'];search_col='origin';date_col='business_date';
 when 'loans' then tbl='driver_loans';cols=array['id','driver_id','reference','due_date','created_by'];search_col='reference';
 when 'loan-transactions' then tbl='driver_loan_transactions';cols=array['id','loan_id','business_date','kind','amount','reference','created_at'];search_col='reference';date_col='business_date';
 when 'earnings' then tbl='driver_earnings';cols=array['id','driver_id','business_date','kind','amount','trip_line_id','rule_snapshot','state'];search_col='kind';date_col='business_date';
 when 'payments' then tbl='driver_payments';cols=array['id','driver_id','business_date','amount','reference'];search_col='reference';date_col='business_date';
 when 'periods' then tbl='accounting_periods';cols=array['id','name','start_date','end_date','status','version'];search_col='name';
 when 'revenue' then tbl='revenue_entries';cols=array['id','business_date','amount','kind','vehicle_id','driver_id','trip_id','booking_id','reversal_of'];search_col='kind';date_col='business_date';
 when 'expenses' then tbl='expense_entries';cols=array['id','business_date','amount','category','vehicle_id','driver_id','trip_id','trip_line_id','maintenance_item_id','office_expense_id','earning_id','reversal_of'];search_col='category';date_col='business_date';
 when 'cash' then tbl='cash_transactions';cols=array['id','business_date','direction','amount','reference','loan_transaction_id','driver_payment_id'];search_col='reference';date_col='business_date';
 else raise exception 'Unknown resource';end case;
 if p_resource not in ('revenue','expenses') then cols=cols||array['archived_at'];if not 'version'=any(cols) then cols=cols||array['version'];end if;end if;
 foreach col in array cols loop expr=expr||case when expr='' then '' else ',' end||format('%L,t.%I',col,col)||case when col in ('amount','quoted_freight','commission','opening_odometer','current_odometer','start_odometer','end_odometer','fuel_litres','weight','odometer','service_interval_km','fuel_target','next_service_odometer') then '::text' else '' end;end loop;
 predicate=format('t.%I::text ilike $1',search_col);
 if p_resource not in ('revenue','expenses') and not p_include_archived then predicate=predicate||' and t.archived_at is null';end if;
 if date_col is not null then predicate=predicate||format(' and ($2::date is null or t.%I >= $2) and ($3::date is null or t.%I <= $3)',date_col,date_col);end if;
 if 'vehicle_id'=any(cols) then predicate=predicate||' and ($4::uuid is null or t.vehicle_id=$4)';end if;
 if 'driver_id'=any(cols) then predicate=predicate||' and ($5::uuid is null or t.driver_id=$5)';end if;
 execute format('select count(*) from public.%I t where %s',tbl,predicate) into total using '%'||replace(replace(replace(p_search,'\','\\'),'%','\%'),'_','\_')||'%',p_from,p_to,p_vehicle,p_driver;
 q=format('select coalesce(jsonb_agg(row),''[]''::jsonb) from (select jsonb_build_object(%s) row from public.%I t where %s order by %s,t.id limit %s offset %s) listed',expr,tbl,predicate,case when date_col is not null then 't.'||quote_ident(date_col)||' desc' else 't.'||quote_ident(search_col) end,p_limit,(p_page-1)*p_limit);
 execute q into rows using '%'||replace(replace(replace(p_search,'\','\\'),'%','\%'),'_','\_')||'%',p_from,p_to,p_vehicle,p_driver;
 return jsonb_build_object('rows',rows,'count',total,'page',p_page);
end $$;
revoke all on function public.list_records(text,text,integer,integer,date,date,uuid,uuid,boolean) from public,anon;
grant execute on function public.list_records(text,text,integer,integer,date,date,uuid,uuid,boolean) to authenticated;

create or replace function public.form_register(p_resource text,p_from date,p_to date,p_page integer default 1,p_limit integer default 25,p_search text default '',p_vehicle uuid default null,p_driver uuid default null,p_status text default '',p_sort text default 'name',p_direction text default 'asc',p_include_archived boolean default false) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tbl text;namecol text;sortcol text;statuscol text;predicate text;searchcols text[];c text;ids jsonb;item jsonb;rows jsonb='[]';total integer;pattern text;
begin
 if not private.active_session() then raise exception 'Sign in required' using errcode='42501';end if;
 if p_from is null or p_to is null or p_to<p_from or p_page<1 or p_limit not between 1 and 1000 or length(p_search)>100 or p_direction not in ('asc','desc') or p_sort not in ('name','date','status') or length(p_status)>30 then raise exception 'Invalid filters';end if;
 case p_resource
 when 'vehicles' then tbl='vehicles';namecol='registration';statuscol='status';searchcols=array['registration','manufacturer','model','address'];
 when 'drivers' then tbl='drivers';namecol='full_name';statuscol='employment_status';searchcols=array['full_name','mobile'];
 when 'trips' then tbl='trips';namecol='cycle_number';statuscol='operational_state';searchcols=array['cycle_number','origin','destination','route_description'];
 when 'maintenance' then tbl='maintenance_records';namecol='description';statuscol='state';searchcols=array['description','supplier'];
 else raise exception 'Unknown form';end case;
 sortcol=case p_sort when 'status' then statuscol when 'date' then case when p_resource in ('trips','maintenance') then 'business_date' else 'created_at' end else namecol end;
 pattern='%'||replace(replace(replace(p_search,'\','\\'),'%','\%'),'_','\_')||'%';predicate='(';
 foreach c in array searchcols loop if predicate<>'(' then predicate=predicate||' or ';end if;predicate=predicate||format('coalesce(t.%I::text,'''') ilike $1',c);end loop;predicate=predicate||')';
 predicate=predicate||format(' and ($6='''' or t.%I=$6)',statuscol);
 if p_resource='trips' then predicate=predicate||' and t.business_date between $2 and $3';end if;
 if not p_include_archived then predicate=predicate||' and t.archived_at is null';end if;
 if p_resource in ('trips','maintenance') then predicate=predicate||' and ($4::uuid is null or t.vehicle_id=$4) and ($5::uuid is null or t.driver_id=$5)';
 elsif p_resource='vehicles' then predicate=predicate||' and ($4::uuid is null or t.id=$4) and ($5::uuid is null or exists(select 1 from public.vehicle_driver_assignments a where a.vehicle_id=t.id and a.driver_id=$5 and a.ended_at is null))';
 else predicate=predicate||' and ($5::uuid is null or t.id=$5) and ($4::uuid is null or exists(select 1 from public.vehicle_driver_assignments a where a.driver_id=t.id and a.vehicle_id=$4 and a.ended_at is null))';end if;
 execute format('select count(*) from public.%I t where %s',tbl,predicate) into total using pattern,p_from,p_to,p_vehicle,p_driver,p_status;
 execute format('select coalesce(jsonb_agg(id),''[]'') from(select t.id from public.%I t where %s order by t.%I %s nulls last,t.id limit %s offset %s) q',tbl,predicate,sortcol,p_direction,p_limit,(p_page-1)*p_limit) into ids using pattern,p_from,p_to,p_vehicle,p_driver,p_status;
 for item in select value from jsonb_array_elements(ids) loop rows=rows||jsonb_build_array(public.form_record(p_resource,(item#>>'{}')::uuid,p_from,p_to));end loop;
 return jsonb_build_object('rows',rows,'count',total,'page',p_page,'from',p_from,'to',p_to);
end $$;

alter function public.form_record(text,uuid,date,date) rename to form_record_before_lifecycle;
create function public.form_record(p_resource text,p_id uuid,p_from date,p_to date) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;archive jsonb;
begin
 result=public.form_record_before_lifecycle(p_resource,p_id,p_from,p_to);
 if p_resource not in ('vehicles','drivers','trips','maintenance') then raise exception 'Unknown form';end if;
 execute format('select jsonb_build_object(''archived_at'',archived_at,''version'',version) from public.%I where id=$1',case p_resource when 'maintenance' then 'maintenance_records' else p_resource end) into archive using p_id;
 return result||coalesce(archive,'{}');
end $$;
revoke all on function public.form_record(text,uuid,date,date) from public,anon;
grant execute on function public.form_record(text,uuid,date,date) to authenticated;

create or replace function private.open_period(p_date date) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.accounting_periods;
begin
 -- All posting/closing workflows take this lock FIRST. Low-volume fleet ledger: intentional serialization.
 perform pg_advisory_xact_lock(87413003);
 if not exists(select 1 from public.business_settings where id and period_confirmed) then raise exception 'Confirm the accounting-period setting before financial entry';end if;
 select * into p from public.accounting_periods where p_date between start_date and end_date for update;
 if p.id is null then raise exception 'Create an accounting period covering this date';end if;
 if p.archived_at is not null then raise exception 'Accounting period is archived; restore it before posting';end if;
 if p.status='Closed' then raise exception 'Accounting period is closed';end if;return p.id;
end $$;

notify pgrst, 'reload schema';

create or replace function public.notification_center(p_status text default 'all',p_page integer default 1) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.active_session() then raise exception 'Sign in required' using errcode='42501';end if;
 if p_status not in ('all','read','unread') or p_page<1 then raise exception 'Invalid notification filter';end if;
 with visible as (
  select n.id,n.type,n.message,n.action_link,n.created_at,n.resolved_at,n.archived_at,n.version,r.read_at
  from public.notifications n left join public.notification_reads r on r.notification_id=n.id and r.user_id=auth.uid() where n.archived_at is null and private.can_notification(n.id)
 ), filtered as (
  select * from visible where case p_status when 'unread' then read_at is null and resolved_at is null when 'read' then read_at is not null else resolved_at is null or read_at is not null end
 ), paged as (select * from filtered order by created_at desc,id desc limit 25 offset (p_page-1)*25)
 select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(paged)) from paged),'[]'),'count',(select count(*) from filtered),'unread_count',(select count(*) from visible where read_at is null and resolved_at is null),'page',p_page) into result;return result;
end $$;

-- Expose lifecycle state on assignment history controls.
create or replace function public.driver_vehicle_history(p_driver uuid,p_page integer default 1,p_limit integer default 25) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not exists(select 1 from public.drivers where id=p_driver and private.can_driver('drivers.view',id,created_by)) then raise exception 'Driver out of scope' using errcode='42501';end if;
 if p_page<1 or p_limit not between 1 and 100 then raise exception 'Invalid page';end if;
 select jsonb_build_object('count',(select count(*) from public.vehicle_driver_assignments where driver_id=p_driver),'page',p_page,'rows',coalesce(jsonb_agg(to_jsonb(rows)),'[]')) into result from (
  select a.id,a.archived_at,a.version,v.registration vehicle_number,(a.started_at at time zone 'Asia/Karachi')::date assigned_date,
   (a.ended_at at time zone 'Asia/Karachi')::date removed_date,a.transfer_date,pv.registration previous_vehicle,
   nv.registration new_vehicle,a.remarks reason,a.ended_at is null is_current
  from public.vehicle_driver_assignments a join public.vehicles v on v.id=a.vehicle_id
  left join public.vehicle_driver_assignments pa on pa.id=a.previous_assignment_id left join public.vehicles pv on pv.id=pa.vehicle_id
  left join public.vehicle_driver_assignments na on na.previous_assignment_id=a.id left join public.vehicles nv on nv.id=na.vehicle_id
  where a.driver_id=p_driver order by a.started_at desc,a.id desc limit p_limit offset (p_page-1)*p_limit
 ) rows;return result;
end $$;
notify pgrst, 'reload schema';
