-- Additive upgrade: retain all driver IDs, assignments and financial keys.
alter table public.vehicle_driver_assignments add column previous_assignment_id uuid references public.vehicle_driver_assignments(id);
alter table public.vehicle_driver_assignments add column transfer_date date;
create index assignment_previous on public.vehicle_driver_assignments(previous_assignment_id);
-- Link inherited history without inventing dates or replacing records.
with ordered as (
 select id,lag(id) over(partition by driver_id order by started_at,id) previous_id
 from public.vehicle_driver_assignments
)
update public.vehicle_driver_assignments a set previous_assignment_id=o.previous_id,
 transfer_date=case when o.previous_id is not null then (a.started_at at time zone 'Asia/Karachi')::date end
from ordered o where o.id=a.id;

create function public.transfer_driver(p_driver uuid,p_vehicle uuid,p_date date,p_reason text,p_assignment uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare d public.drivers;v public.vehicles;old public.vehicle_driver_assignments;prev uuid;at_time timestamptz;result uuid;
begin
 perform pg_advisory_xact_lock(87413002);
 select * into d from public.drivers where id=p_driver for update;
 if d.id is null or not private.can_driver('drivers.view',p_driver,d.created_by) then raise exception 'Driver unavailable or out of scope' using errcode='42501';end if;
 select * into old from public.vehicle_driver_assignments where driver_id=p_driver and ended_at is null for update;
 if old.id is distinct from p_assignment then raise exception 'Assignment changed; reload' using errcode='40001';end if;
 if old.id is not null then perform private.require_permission('assignments.manage',old.vehicle_id,(select created_by from public.vehicles where id=old.vehicle_id));end if;
 if p_vehicle is not null then
  select * into v from public.vehicles where id=p_vehicle for update;
  if v.id is null then raise exception 'Vehicle unavailable';end if;
  perform private.require_permission('assignments.manage',p_vehicle,v.created_by);
  if old.vehicle_id is not distinct from p_vehicle then return old.id;end if;
  if v.status<>'Active' or d.employment_status<>'Active' then raise exception 'Vehicle and driver must both be active';end if;
  if exists(select 1 from public.vehicle_driver_assignments where vehicle_id=p_vehicle and ended_at is null and driver_id<>p_driver) then raise exception 'Vehicle already has an active driver; transfer or remove that driver first';end if;
 else
  if old.id is null then perform private.require_permission('assignments.manage',null,d.created_by);return null;end if;
 end if;
 if old.vehicle_id is not distinct from p_vehicle then return old.id;end if;
 if length(coalesce(p_reason,''))>300 then raise exception 'Reason too long';end if;
 if p_date>(now() at time zone 'Asia/Karachi')::date or p_date<d.joining_date then raise exception 'Use a date between joining date and today';end if;
 at_time=case when p_date is null or p_date=(now() at time zone 'Asia/Karachi')::date then now() else p_date::timestamp at time zone 'Asia/Karachi' end;
 if old.id is not null and at_time<old.started_at then raise exception 'Transfer date cannot precede the current assignment';end if;
 if old.id is not null then
  update public.vehicle_driver_assignments set ended_at=greatest(old.started_at,at_time-interval '1 microsecond') where id=old.id;
  prev=old.id;
 else
  select id into prev from public.vehicle_driver_assignments where driver_id=p_driver order by started_at desc,id desc limit 1;
  if exists(select 1 from public.vehicle_driver_assignments where id=prev and ended_at>at_time) then raise exception 'Assignment date overlaps saved history';end if;
 end if;
 if p_vehicle is not null then
  insert into public.vehicle_driver_assignments(vehicle_id,driver_id,started_at,previous_assignment_id,transfer_date,remarks,created_by)
  values(p_vehicle,p_driver,at_time,prev,case when prev is not null then (at_time at time zone 'Asia/Karachi')::date end,nullif(trim(p_reason),''),auth.uid()) returning id into result;
 end if;
 perform private.audit('driver.transfer','driver',p_driver::text,'Vehicle assignment history saved');return result;
end $$;
create or replace function public.assign_driver(p_vehicle uuid,p_driver uuid,p_reason text) returns void
language plpgsql security definer set search_path='' as $$
declare a public.vehicle_driver_assignments;
begin
 perform pg_advisory_xact_lock(87413002);
 if p_driver is null then
  perform private.require_permission('assignments.manage',p_vehicle,(select created_by from public.vehicles where id=p_vehicle));
  select * into a from public.vehicle_driver_assignments where vehicle_id=p_vehicle and ended_at is null;
  if a.id is not null then perform public.transfer_driver(a.driver_id,null,null,p_reason,a.id);end if;
 else
  select * into a from public.vehicle_driver_assignments where driver_id=p_driver and ended_at is null;
  perform public.transfer_driver(p_driver,p_vehicle,null,p_reason,a.id);
 end if;
end $$;
create function public.driver_vehicle_history(p_driver uuid,p_page integer default 1,p_limit integer default 25) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not exists(select 1 from public.drivers where id=p_driver and private.can_driver('drivers.view',id,created_by)) then raise exception 'Driver out of scope' using errcode='42501';end if;
 if p_page<1 or p_limit not between 1 and 100 then raise exception 'Invalid page';end if;
 select jsonb_build_object('count',(select count(*) from public.vehicle_driver_assignments where driver_id=p_driver),'page',p_page,'rows',coalesce(jsonb_agg(to_jsonb(rows)),'[]')) into result from (
  select a.id,v.registration vehicle_number,(a.started_at at time zone 'Asia/Karachi')::date assigned_date,
   (a.ended_at at time zone 'Asia/Karachi')::date removed_date,a.transfer_date,pv.registration previous_vehicle,
   nv.registration new_vehicle,a.remarks reason,a.ended_at is null is_current
  from public.vehicle_driver_assignments a join public.vehicles v on v.id=a.vehicle_id
  left join public.vehicle_driver_assignments pa on pa.id=a.previous_assignment_id left join public.vehicles pv on pv.id=pa.vehicle_id
  left join public.vehicle_driver_assignments na on na.previous_assignment_id=a.id left join public.vehicles nv on nv.id=na.vehicle_id
  where a.driver_id=p_driver order by a.started_at desc,a.id desc limit p_limit offset (p_page-1)*p_limit
 ) rows;return result;
end $$;

alter table public.vehicles add column permit_expiry date;
alter table public.vehicles add column insurance_expiry date;
-- Preserve the custom-field wrapper and all its validation.
alter function public.save_form(text,uuid,integer,jsonb,integer,uuid) rename to save_form_before_enhancements;
alter function public.save_form_before_enhancements(text,uuid,integer,jsonb,integer,uuid) set schema private;
revoke all on function private.save_form_before_enhancements(text,uuid,integer,jsonb,integer,uuid) from public,anon,authenticated;
create function public.save_form(p_resource text,p_id uuid,p_version integer,p_data jsonb,p_identity_version integer default null,p_assignment uuid default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid;base jsonb=p_data;
begin
 if p_resource='drivers' then
  perform pg_advisory_xact_lock(87413002);base=base-'vehicle_id'-'assignment_date'-'assignment_reason';
 elsif p_resource='vehicles' then base=base-'permit_expiry'-'insurance_expiry';end if;
 result=private.save_form_before_enhancements(p_resource,p_id,p_version,base,p_identity_version,p_assignment);
 if p_resource='drivers' and p_data?'vehicle_id' then
  perform public.transfer_driver(result,nullif(p_data->>'vehicle_id','')::uuid,nullif(p_data->>'assignment_date','')::date,p_data->>'assignment_reason',p_assignment);
 elsif p_resource='vehicles' then
  update public.vehicles set permit_expiry=case when p_data?'permit_expiry' then nullif(p_data->>'permit_expiry','')::date else permit_expiry end,
   insurance_expiry=case when p_data?'insurance_expiry' then nullif(p_data->>'insurance_expiry','')::date else insurance_expiry end where id=result;
 end if;return result;
end $$;

create table public.routes(id uuid primary key default gen_random_uuid(),origin text not null check(length(trim(origin)) between 1 and 120),destination text not null check(length(trim(destination)) between 1 and 120),archived boolean not null default false,version integer not null default 1,created_by uuid not null references public.app_users(id),created_at timestamptz not null default now());
create unique index routes_active_pair on public.routes(lower(trim(origin)),lower(trim(destination))) where not archived;
alter table public.routes enable row level security;
revoke all on public.routes from public,anon,authenticated;grant select on public.routes to authenticated;
create policy routes_read on public.routes for select to authenticated using(private.has_capability('trips.view') or private.has_capability('bookings.view'));
create function public.save_route(p_id uuid,p_version integer,p_origin text,p_destination text,p_archived boolean default false) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if not (private.can('trips.create',null,auth.uid()) or private.can('trips.update') or private.can('bookings.create',null,auth.uid())) then raise exception 'Route management permission required' using errcode='42501';end if;
 if trim(p_origin)='' or trim(p_destination)='' or lower(trim(p_origin))=lower(trim(p_destination)) then raise exception 'Enter different From and To locations';end if;
 if p_id is null then insert into public.routes(origin,destination,created_by) values(trim(p_origin),trim(p_destination),auth.uid()) returning id into result;
 else
  update public.routes set origin=trim(p_origin),destination=trim(p_destination),archived=p_archived,version=version+1 where id=p_id and version=p_version returning id into result;
  if result is null then raise exception 'Route changed; reload' using errcode='40001';end if;
 end if;perform private.audit('route.save','route',result::text,'Route saved');return result;
end $$;
update public.expense_categories set label='Punjab Police' where code='fines_permits';
update public.expense_categories set label='Other incentives' where code='reward';
update public.expense_categories set label='Driver Reward' where code='commission';

create or replace function private.reconcile_alerts() returns void language plpgsql security definer set search_path='' as $$
declare today date=(now() at time zone 'Asia/Karachi')::date;days integer;
begin
 perform pg_advisory_xact_lock(87413004);
 select threshold::integer into days from public.alert_rules where code='expiry_days' and enabled;
 update public.notifications set resolved_at=now() where resolved_at is null;
 insert into public.notifications(dedup_key,type,message,vehicle_id,action_link)
 select 'vehicle-expiry:'||id||':'||document_expiry,'Document expiry','Vehicle '||registration||' documents expire on '||document_expiry,id,'/vehicles' from public.vehicles where status not in ('Sold','Archived') and document_expiry<=today+days
 union all select 'permit-expiry:'||id||':'||permit_expiry,'Permit expiry','Vehicle '||registration||' permit expires on '||permit_expiry,id,'/vehicles' from public.vehicles where status not in ('Sold','Archived') and permit_expiry<=today+days
 union all select 'insurance-expiry:'||id||':'||insurance_expiry,'Insurance reminder','Vehicle '||registration||' insurance expires on '||insurance_expiry,id,'/vehicles' from public.vehicles where status not in ('Sold','Archived') and insurance_expiry<=today+days
 on conflict(dedup_key) do update set resolved_at=null,message=excluded.message;
 insert into public.notifications(dedup_key,type,message,driver_id,action_link)
 select 'driver-expiry:'||id||':'||licence_expiry,'Licence expiry','Driver '||full_name||' licence expires on '||licence_expiry,id,'/drivers' from public.drivers where employment_status='Active' and licence_expiry<=today+days on conflict(dedup_key) do update set resolved_at=null,message=excluded.message;
 insert into public.notifications(dedup_key,type,message,vehicle_id,action_link)
 select 'oil-due:'||v.id||':'||m.id,'Service Reminder','Vehicle '||v.registration||' oil change due at '||o.next_due_odometer||' km',v.id,'/maintenance/invoices'
 from public.vehicles v join lateral(select mr.id from public.maintenance_records mr where mr.vehicle_id=v.id and mr.state='Approved' and mr.category='oil_change' order by mr.business_date desc,mr.odometer desc,mr.created_at desc limit 1) m on true
 join public.oil_changes o on o.maintenance_id=m.id where v.status not in ('Sold','Archived') and o.next_due_odometer<=v.current_odometer
 on conflict(dedup_key) do update set resolved_at=null,message=excluded.message;
 insert into public.notifications(dedup_key,type,message,vehicle_id,action_link)
 select 'service-due:'||v.id||':'||coalesce(m.id::text,'opening'),'Maintenance required','Vehicle '||v.registration||' maintenance required',v.id,'/maintenance/invoices'
 from public.vehicles v left join lateral(select mr.* from public.maintenance_records mr where mr.vehicle_id=v.id and mr.state='Approved' order by mr.business_date desc,mr.odometer desc,mr.created_at desc limit 1) m on true
 where v.status not in ('Sold','Archived') and (m.next_service_date<=today or v.current_odometer>=coalesce(m.next_service_odometer,coalesce(m.odometer,v.opening_odometer)+v.service_interval_km))
 on conflict(dedup_key) do update set resolved_at=null;
 insert into public.notifications(dedup_key,type,message,trip_id,action_link)
 select 'trip-approval:'||id,'Approval pending','Trip '||trip_number||' is awaiting review.',id,'/trips' from public.trips where financial_state='Submitted' and archived_at is null
 on conflict(dedup_key) do update set resolved_at=null;
 insert into public.notifications(dedup_key,type,message,trip_id,action_link)
 select 'fuel-review:'||id,'Fuel review','Trip '||trip_number||' efficiency is below the configured threshold.',id,'/trips' from public.trips where operational_state='Completed' and financial_state<>'Voided' and archived_at is null and fuel_basis='measured' and fuel_litres>0 and (end_odometer-start_odometer)/fuel_litres<(select threshold from public.alert_rules where code='low_efficiency' and enabled)
 on conflict(dedup_key) do update set resolved_at=null;
 insert into public.job_runs(job_name,last_completed_at,run_count) values('gbt-alert-reconciliation',now(),1) on conflict(job_name) do update set last_completed_at=now(),run_count=public.job_runs.run_count+1;
 delete from private.request_limits where expires_at<now()-interval '1 day';
end $$;
create function public.notification_center(p_status text default 'all',p_page integer default 1) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.active_session() then raise exception 'Sign in required' using errcode='42501';end if;
 if p_status not in ('all','read','unread') or p_page<1 then raise exception 'Invalid notification filter';end if;
 with visible as (
  select n.id,n.type,n.message,n.action_link,n.created_at,n.resolved_at,r.read_at
  from public.notifications n left join public.notification_reads r on r.notification_id=n.id and r.user_id=auth.uid() where private.can_notification(n.id)
 ), filtered as (
  select * from visible where case p_status when 'unread' then read_at is null and resolved_at is null when 'read' then read_at is not null else resolved_at is null or read_at is not null end
 ), paged as (select * from filtered order by created_at desc,id desc limit 25 offset (p_page-1)*25)
 select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(paged)) from paged),'[]'),'count',(select count(*) from filtered),'unread_count',(select count(*) from visible where read_at is null and resolved_at is null),'page',p_page) into result;return result;
end $$;

alter function public.form_record(text,uuid,date,date) rename to form_record_before_enhancements;
alter function public.form_record_before_enhancements(text,uuid,date,date) set schema private;
grant execute on function private.form_record_before_enhancements(text,uuid,date,date) to authenticated;
create function public.form_record(p_resource text,p_id uuid,p_from date,p_to date) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;a public.vehicle_driver_assignments;
begin
 result=private.form_record_before_enhancements(p_resource,p_id,p_from,p_to);
 if p_resource='drivers' then
  select * into a from public.vehicle_driver_assignments where driver_id=p_id and ended_at is null;
  result=result||jsonb_build_object('assignment_date',(a.started_at at time zone 'Asia/Karachi')::date,'assignment_reason',a.remarks);
 end if;return result;
end $$;
revoke all on function public.form_record(text,uuid,date,date) from public,anon;
grant execute on function public.form_record(text,uuid,date,date) to authenticated;

-- First Google login creates a profile with zero business permissions.
-- Administrators choose its role in Users; existing roles are never overwritten.
alter table public.app_users add column avatar_url text;
alter table public.app_users add column auth_provider text not null default 'password';
insert into public.roles(name) values('Pending Access') on conflict(name) do nothing;
create function public.server_google_user_sync(p_user uuid,p_name text,p_avatar text) returns void
language plpgsql security definer set search_path='' as $$
declare e text;meta jsonb;existing public.app_users;created uuid;
begin
 perform pg_advisory_xact_lock(87413001);
 select email,raw_app_meta_data into e,meta from auth.users where id=p_user;
 if e is null or not (meta->>'provider'='google' or coalesce(meta->'providers','[]') ? 'google') then raise exception 'Verified Google identity required' using errcode='42501';end if;
 select * into existing from public.app_users where id=p_user for update;
 if existing.id is not null then
  if not existing.active then raise exception 'Account disabled' using errcode='42501';end if;
  update public.app_users set avatar_url=left(p_avatar,2048),auth_provider='google' where id=p_user;return;
 end if;
 if exists(select 1 from public.app_users where lower(email)=lower(e)) then raise exception 'Email is linked to a different account; contact an administrator' using errcode='42501';end if;
 insert into public.app_users(id,email,display_name,avatar_url,auth_provider) values(p_user,lower(e),left(coalesce(nullif(trim(p_name),''),split_part(e,'@',1)),120),left(p_avatar,2048),'google') returning id into created;
 insert into public.user_roles(user_id,role_id) select created,r.id from public.roles r where name='Pending Access' and not exists(select 1 from public.role_permissions rp where rp.role_id=r.id);
end $$;
-- No signature configuration may remove the final signing area.
update public.print_template_settings set signatures=array['Signature'] where cardinality(signatures)=0;
alter table public.print_template_settings add constraint print_signature_required check(cardinality(signatures)>0);
revoke all on function public.transfer_driver(uuid,uuid,date,text,uuid),public.driver_vehicle_history(uuid,integer,integer),public.save_form(text,uuid,integer,jsonb,integer,uuid),public.save_route(uuid,integer,text,text,boolean),public.notification_center(text,integer),public.server_google_user_sync(uuid,text,text) from public,anon,authenticated;
grant execute on function public.transfer_driver(uuid,uuid,date,text,uuid),public.driver_vehicle_history(uuid,integer,integer),public.save_form(text,uuid,integer,jsonb,integer,uuid),public.save_route(uuid,integer,text,text,boolean),public.notification_center(text,integer) to authenticated;
grant execute on function public.server_google_user_sync(uuid,text,text) to service_role;
notify pgrst,'reload schema';
