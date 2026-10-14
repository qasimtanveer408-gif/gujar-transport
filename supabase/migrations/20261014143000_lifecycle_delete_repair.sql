-- Reinstall the archive/delete RPC definitions on an existing application.
-- This migration changes functions and privileges only; it does not delete or
-- archive records, disable RLS, or remove the administrator confirmation checks.
do $preflight$
begin
 if to_regclass('private.lifecycle_resources') is null
    or to_regclass('private.deletion_jobs') is null then
  raise exception 'Apply 20261014120000_record_lifecycle.sql first, or run supabase/setup/REPAIR_RECORD_DELETE.sql.';
 end if;
end $preflight$;

create or replace function public.server_deletion_jobs() returns jsonb language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(j)),'[]') from (select * from private.deletion_jobs order by created_at,id limit 100) j
$$;
create or replace function public.server_finish_deletion_job(p_id uuid) returns void language sql security definer set search_path='' as $$delete from private.deletion_jobs where id=p_id$$;
revoke all on function public.server_deletion_jobs(),public.server_finish_deletion_job(uuid) from public,anon,authenticated;
grant execute on function public.server_deletion_jobs(),public.server_finish_deletion_job(uuid) to service_role;

create or replace function private.lifecycle_pk(p_rel oid,p_row jsonb) returns jsonb language sql stable set search_path='' as $$
 select jsonb_object_agg(a.attname,p_row->a.attname) from pg_index i join pg_attribute a on a.attrelid=i.indrelid and a.attnum=any(i.indkey)
 where i.indrelid=p_rel and i.indisprimary
$$;
create or replace function private.lifecycle_add(p_rel oid,p_row jsonb) returns void language plpgsql set search_path='' as $$
begin
 if p_row is not null then insert into pg_temp.gbt_delete_plan(rel,pk,row_data) values(p_rel,private.lifecycle_pk(p_rel,p_row),p_row) on conflict do nothing;end if;
end $$;
create or replace function private.lifecycle_plan(p_resource text,p_id text) returns jsonb language plpgsql security definer set search_path='' as $$
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

create or replace function public.record_lifecycle_preview(p_resource text,p_id text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.can('records.archive') and not private.can('records.delete') then raise exception 'Permission denied' using errcode='42501';end if;
 return private.lifecycle_plan(p_resource,p_id);
end $$;
create or replace function public.record_lifecycle_list(p_resource text,p_state text default 'active',p_page integer default 1,p_search text default '') returns jsonb language plpgsql security definer set search_path='' as $$
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

create or replace function public.record_lifecycle_action(p_resource text,p_id text,p_action text,p_version integer,p_reason text,p_token text default null,p_confirmation text default null) returns jsonb language plpgsql security definer set search_path='' as $$
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


notify pgrst, 'reload schema';
