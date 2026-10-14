create table public.attachments (
 id uuid primary key default gen_random_uuid(),vehicle_id uuid references public.vehicles(id),driver_id uuid references public.drivers(id),trip_id uuid references public.trips(id),maintenance_id uuid references public.maintenance_records(id),office_expense_id uuid references public.office_expenses(id),
 bucket_id text not null,object_path text not null unique,original_name text not null,mime_type text not null check(mime_type in ('image/jpeg','image/png','application/pdf')),size_bytes bigint not null check(size_bytes between 1 and 10485760),
 state text not null default 'pending' check(state in ('pending','ready','deleting','deleted')),created_by uuid not null references public.app_users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(num_nonnulls(vehicle_id,driver_id,trip_id,maintenance_id,office_expense_id)=1)
);
create function private.can_attachment(p_id uuid,p_action text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare a public.attachments;vid uuid;owner uuid;access_ok boolean;
begin
 select * into a from public.attachments where id=p_id;
 if a.id is null or a.state='deleted' or not private.active_session() then return false;end if;
 if a.driver_id is not null then
  select created_by into owner from public.drivers where id=a.driver_id;
  return private.can_driver('drivers.documents.view',a.driver_id,owner) and (p_action='view' or private.can_driver('documents.'||p_action,a.driver_id,a.created_by));
 elsif a.vehicle_id is not null then
  vid=a.vehicle_id;select created_by into owner from public.vehicles where id=vid;access_ok=private.can('vehicles.view',vid,owner);
 elsif a.trip_id is not null then
  select vehicle_id,created_by into vid,owner from public.trips where id=a.trip_id;access_ok=private.can('trips.view',vid,owner);
 elsif a.maintenance_id is not null then
  select vehicle_id,created_by into vid,owner from public.maintenance_records where id=a.maintenance_id;access_ok=private.can('maintenance.view',vid,owner);
 else
  select vehicle_id,created_by into vid,owner from public.office_expenses where id=a.office_expense_id;access_ok=private.can('expenses.view',vid,owner);
 end if;
 return coalesce(access_ok,false) and private.can('documents.'||p_action,vid,a.created_by);
end $$;
create function public.reserve_attachment(p_resource text,p_record uuid,p_name text,p_mime text,p_size bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare aid uuid=gen_random_uuid();bucket text;ext text;path text;result jsonb;
begin
 if p_resource not in ('vehicles','drivers','trips','maintenance','office-expenses') then raise exception 'Invalid attachment source';end if;
 if length(p_name) not between 1 and 160 or p_name~'[\r\n/\\]' then raise exception 'Invalid file name';end if;
 ext=case p_mime when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'application/pdf' then 'pdf' else null end;
 if ext is null then raise exception 'Only JPEG, PNG, and PDF documents are supported';end if;
 bucket='gbt-'||p_resource;path=p_record::text||'/'||aid::text||'.'||ext;
 insert into public.attachments(id,vehicle_id,driver_id,trip_id,maintenance_id,office_expense_id,bucket_id,object_path,original_name,mime_type,size_bytes,created_by) values(aid,case when p_resource='vehicles' then p_record end,case when p_resource='drivers' then p_record end,case when p_resource='trips' then p_record end,case when p_resource='maintenance' then p_record end,case when p_resource='office-expenses' then p_record end,bucket,path,p_name,p_mime,p_size,auth.uid());
 if not private.can_attachment(aid,'upload') then raise exception 'Document upload denied' using errcode='42501';end if;
 return jsonb_build_object('id',aid,'bucket_id',bucket,'object_path',path);
end $$;
create function public.finalize_attachment(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare a public.attachments;
begin
 select * into a from public.attachments where id=p_id for update;
 if not private.can_attachment(p_id,'upload') or a.created_by<>auth.uid() then raise exception 'Document upload denied' using errcode='42501';end if;
 if a.state='ready' then return;end if;
 if a.state<>'pending' or not exists(select 1 from storage.objects where bucket_id=a.bucket_id and name=a.object_path) then raise exception 'Uploaded object not found';end if;
 update public.attachments set state='ready',updated_at=now() where id=p_id;perform private.audit('attachment.ready','attachment',p_id::text,'Private document uploaded; file name omitted');
end $$;
create function public.delete_attachment_state(p_id uuid,p_finish boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.attachments;
begin
 select * into a from public.attachments where id=p_id for update;
 if not private.can_attachment(p_id,'delete') then raise exception 'Document deletion denied' using errcode='42501';end if;
 if p_finish and exists(select 1 from storage.objects where bucket_id=a.bucket_id and name=a.object_path) then raise exception 'Remove the stored file using the Storage API first';end if;
 update public.attachments set state=case when p_finish then 'deleted' else 'deleting' end,updated_at=now() where id=p_id;
 perform private.audit('attachment.delete','attachment',p_id::text,case when p_finish then 'Private document removed' else 'Private document deletion requested' end);
 return jsonb_build_object('bucket_id',a.bucket_id,'object_path',a.object_path);
end $$;
create function public.server_orphan_candidates() returns jsonb language sql security definer set search_path='' as $$
select coalesce(jsonb_agg(jsonb_build_object('id',id,'bucket_id',bucket_id,'object_path',object_path)),'[]') from public.attachments where state in ('pending','deleting') and updated_at<now()-interval '24 hours'
$$;
create function public.server_orphan_finish(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare a public.attachments;
begin
 select * into a from public.attachments where id=p_id for update;
 if a.state not in ('pending','deleting') or a.updated_at>=now()-interval '24 hours' then raise exception 'Not a stale pending upload';end if;
 if exists(select 1 from storage.objects where bucket_id=a.bucket_id and name=a.object_path) then raise exception 'Stored file must be removed through Storage API';end if;
 update public.attachments set state='deleted',updated_at=now() where id=p_id;
 insert into public.audit_logs(action,record_type,record_id,summary) values('system.orphan.cleanup','attachment',p_id::text,'Stale pending document cleaned up');
end $$;
alter table public.attachments enable row level security;
revoke all on public.attachments from anon,authenticated;grant select on public.attachments to authenticated;
create policy attachment_read on public.attachments for select to authenticated using(state in ('ready','deleting') and private.can_attachment(id,'view'));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) select 'gbt-'||r,'gbt-'||r,false,10485760,array['image/jpeg','image/png','application/pdf'] from unnest(array['vehicles','drivers','trips','maintenance','office-expenses'])r on conflict(id) do nothing;
create policy gbt_object_read on storage.objects for select to authenticated using(exists(select 1 from public.attachments a where a.bucket_id=storage.objects.bucket_id and a.object_path=storage.objects.name and a.state in ('ready','deleting') and private.can_attachment(a.id,'view')));
-- Definer helper is needed for pending objects, since pending metadata is not readable by ordinary users.
create function private.storage_allowed(p_bucket text,p_path text,p_operation text) returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from public.attachments a where a.bucket_id=p_bucket and a.object_path=p_path and
 ((p_operation='upload' and a.state='pending' and a.created_by=auth.uid() and private.can_attachment(a.id,'upload')) or (p_operation='delete' and a.state='deleting' and private.can_attachment(a.id,'delete'))))
$$;
create policy gbt_object_insert on storage.objects for insert to authenticated with check(private.storage_allowed(bucket_id,name,'upload'));
create policy gbt_object_delete on storage.objects for delete to authenticated using(private.storage_allowed(bucket_id,name,'delete'));
-- No UPDATE policy: replacement is a separately authorized new attachment, never an arbitrary overwrite.
revoke all on function private.can_attachment(uuid,text),private.storage_allowed(text,text,text) from public,anon,authenticated;
grant execute on function private.can_attachment(uuid,text),private.storage_allowed(text,text,text) to authenticated;
revoke all on function public.reserve_attachment(text,uuid,text,text,bigint),public.finalize_attachment(uuid),public.delete_attachment_state(uuid,boolean),public.server_orphan_candidates(),public.server_orphan_finish(uuid) from public,anon,authenticated;
grant execute on function public.reserve_attachment(text,uuid,text,text,bigint),public.finalize_attachment(uuid),public.delete_attachment_state(uuid,boolean) to authenticated;
grant execute on function public.server_orphan_candidates(),public.server_orphan_finish(uuid) to service_role;
insert into public.role_permissions select id,'documents.view','own' from public.roles where name='Data Entry';
