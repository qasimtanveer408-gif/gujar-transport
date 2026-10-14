-- Fix SQLSTATE 21000: UPDATE requires a WHERE clause during permanent deletion.
-- Forward-only function replacement; already applied migrations stay unchanged.
-- This migration does not delete records or change the database safety settings.
do $preflight$
begin
 if to_regprocedure('public.record_lifecycle_action(text,text,text,integer,text,text,text)') is null
    or to_regprocedure('private.lifecycle_plan(text,text)') is null then
  raise exception 'Apply the earlier lifecycle migrations before this migration.';
 end if;
end $preflight$;

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
  -- The deletion plan retains vehicle IDs after their trips/maintenance are gone.
  -- Scope the update to those vehicles: Supabase safeupdate rejects an UPDATE
  -- without a WHERE clause, and unrelated records must not be rewritten.
  update public.vehicles v set current_odometer=greatest(v.opening_odometer,coalesce((select max(end_odometer) from public.trips where vehicle_id=v.id and financial_state='Approved'),0),coalesce((select max(odometer) from public.maintenance_records where vehicle_id=v.id and state='Approved'),0))
   where exists(
    select 1 from pg_temp.gbt_delete_plan p
    where p.rel in ('public.trips'::regclass,'public.maintenance_records'::regclass)
      and p.row_data->>'vehicle_id'=v.id::text
   );
 end if;
 perform private.audit('record.'||p_action,p_resource,p_id,p_reason);
 perform set_config('gbt.lifecycle','off',true);
 return jsonb_build_object('ok',true,'action',p_action,'counts',counts);
end $$;

revoke all on function public.record_lifecycle_action(text,text,text,integer,text,text,text) from public,anon,authenticated;
grant execute on function public.record_lifecycle_action(text,text,text,integer,text,text,text) to authenticated;
notify pgrst, 'reload schema';
