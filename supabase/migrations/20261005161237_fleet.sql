create table public.companies(id uuid primary key default gen_random_uuid(),name text not null unique,created_by uuid references public.app_users(id),version integer not null default 1);
create table public.vehicles (
 id uuid primary key default gen_random_uuid(),registration text not null check(length(registration) between 2 and 30),
 manufacturer text not null,model text not null,owner_company_id uuid references public.companies(id),vehicle_class text,
 purchase_date date,opening_odometer numeric(14,3) not null default 0 check(opening_odometer>=0),
 current_odometer numeric(14,3) not null default 0 check(current_odometer>=opening_odometer),
 status text not null default 'Active' check(status in ('Active','Maintenance','Inactive','Sold','Archived')),
 service_interval_km numeric(12,3) check(service_interval_km>0),fuel_target numeric(8,3) check(fuel_target>0),document_expiry date,remarks text,
 created_by uuid not null references public.app_users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),version integer not null default 1
);
create unique index vehicles_registration on public.vehicles(upper(regexp_replace(registration,'\s','','g')));
create table public.vehicle_financials(vehicle_id uuid primary key references public.vehicles(id),purchase_price numeric(18,2) check(purchase_price>=0));
create table public.drivers (
 id uuid primary key default gen_random_uuid(),full_name text not null check(length(full_name) between 1 and 120),mobile text not null,
 joining_date date,leaving_date date,licence_expiry date,employment_status text not null default 'Active' check(employment_status in ('Active','On Leave','Left','Archived')),
 remarks text,created_by uuid not null references public.app_users(id),created_at timestamptz not null default now(),version integer not null default 1,
 check(leaving_date is null or joining_date is null or leaving_date>=joining_date)
);
create table public.driver_identity_details(driver_id uuid primary key references public.drivers(id),father_name text,cnic text,licence_number text,address text,emergency_contact text,version integer not null default 1);
create table public.user_vehicle_scopes(user_id uuid references public.app_users(id),vehicle_id uuid references public.vehicles(id),primary key(user_id,vehicle_id));
create table public.driver_duty_sessions(id uuid primary key default gen_random_uuid(),driver_id uuid not null references public.drivers(id),started_at timestamptz not null default now(),ended_at timestamptz,created_by uuid not null references public.app_users(id),check(ended_at is null or ended_at>=started_at));
create unique index duty_open on public.driver_duty_sessions(driver_id) where ended_at is null;
create table public.vehicle_driver_assignments(id uuid primary key default gen_random_uuid(),vehicle_id uuid not null references public.vehicles(id),driver_id uuid not null references public.drivers(id),started_at timestamptz not null default now(),ended_at timestamptz,remarks text,created_by uuid not null references public.app_users(id),check(ended_at is null or ended_at>=started_at));
create unique index assignment_vehicle_open on public.vehicle_driver_assignments(vehicle_id) where ended_at is null;
create unique index assignment_driver_open on public.vehicle_driver_assignments(driver_id) where ended_at is null;
create index assignments_driver on public.vehicle_driver_assignments(driver_id);

create or replace function private.can(p_permission text,p_vehicle uuid default null,p_owner uuid default null) returns boolean language sql stable security definer set search_path='' as $$
 select private.active_session() and exists(select 1 from public.user_roles ur join public.role_permissions rp on rp.role_id=ur.role_id
 where ur.user_id=auth.uid() and rp.permission_code=p_permission and (rp.scope='all' or (rp.scope='own' and p_owner=auth.uid()) or (rp.scope='assigned' and exists(select 1 from public.user_vehicle_scopes s where s.user_id=auth.uid() and s.vehicle_id=p_vehicle))))
$$;
create function private.can_driver(p_permission text,p_driver uuid,p_owner uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.can(p_permission,null,p_owner) or exists(select 1 from public.vehicle_driver_assignments a where a.driver_id=p_driver and a.ended_at is null and private.can(p_permission,a.vehicle_id,p_owner))
$$;

create function public.save_vehicle(p_id uuid,p_version integer,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare vid uuid;v public.vehicles;
begin
 if p_id is null then
  perform private.require_permission('vehicles.create',null,auth.uid());
  insert into public.vehicles(registration,manufacturer,model,owner_company_id,vehicle_class,purchase_date,opening_odometer,current_odometer,status,service_interval_km,fuel_target,document_expiry,remarks,created_by)
  values(trim(p_data->>'registration'),p_data->>'manufacturer',p_data->>'model',nullif(p_data->>'owner_company_id','')::uuid,p_data->>'vehicle_class',nullif(p_data->>'purchase_date','')::date,coalesce((p_data->>'opening_odometer')::numeric,0),coalesce((p_data->>'opening_odometer')::numeric,0),coalesce(p_data->>'status','Active'),nullif(p_data->>'service_interval_km','')::numeric,nullif(p_data->>'fuel_target','')::numeric,nullif(p_data->>'document_expiry','')::date,p_data->>'remarks',auth.uid()) returning id into vid;
 else
  select * into v from public.vehicles where id=p_id for update;
  perform private.require_permission('vehicles.update',p_id,v.created_by);
  if p_data->>'status' in ('Sold','Archived') then perform private.require_permission('vehicles.archive',p_id,v.created_by);end if;
  if v.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
  if nullif(p_data->>'opening_odometer','')::numeric is distinct from v.opening_odometer then raise exception 'Opening odometer is immutable; use an audited correction process';end if;
  update public.vehicles set registration=trim(p_data->>'registration'),manufacturer=p_data->>'manufacturer',model=p_data->>'model',owner_company_id=nullif(p_data->>'owner_company_id','')::uuid,vehicle_class=p_data->>'vehicle_class',purchase_date=nullif(p_data->>'purchase_date','')::date,status=p_data->>'status',service_interval_km=nullif(p_data->>'service_interval_km','')::numeric,fuel_target=nullif(p_data->>'fuel_target','')::numeric,document_expiry=nullif(p_data->>'document_expiry','')::date,remarks=p_data->>'remarks',version=version+1,updated_at=now() where id=p_id;vid=p_id;
 end if;
 if p_data?'purchase_price' then
  perform private.require_permission('reports.financial.view',vid,auth.uid());
  insert into public.vehicle_financials(vehicle_id,purchase_price) values(vid,nullif(p_data->>'purchase_price','')::numeric) on conflict(vehicle_id) do update set purchase_price=excluded.purchase_price;
 end if;
 perform private.audit('vehicle.save','vehicle',vid::text,'Vehicle details saved');return vid;
end $$;
create function public.save_driver(p_id uuid,p_version integer,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare did uuid;d public.drivers;
begin
 if p_id is null then
  perform private.require_permission('drivers.create',null,auth.uid());
  insert into public.drivers(full_name,mobile,joining_date,leaving_date,licence_expiry,employment_status,remarks,created_by) values(p_data->>'full_name',p_data->>'mobile',nullif(p_data->>'joining_date','')::date,nullif(p_data->>'leaving_date','')::date,nullif(p_data->>'licence_expiry','')::date,coalesce(p_data->>'employment_status','Active'),p_data->>'remarks',auth.uid()) returning id into did;
 else
  select * into d from public.drivers where id=p_id for update;
  if not private.can_driver('drivers.update',p_id,d.created_by) then raise exception 'Permission denied' using errcode='42501';end if;
  if d.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
  update public.drivers set full_name=p_data->>'full_name',mobile=p_data->>'mobile',joining_date=nullif(p_data->>'joining_date','')::date,leaving_date=nullif(p_data->>'leaving_date','')::date,licence_expiry=nullif(p_data->>'licence_expiry','')::date,employment_status=p_data->>'employment_status',remarks=p_data->>'remarks',version=version+1 where id=p_id;did=p_id;
  if p_data->>'employment_status'<>'Active' then update public.driver_duty_sessions set ended_at=now() where driver_id=did and ended_at is null;end if;
 end if;
 perform private.audit('driver.save','driver',did::text,'Driver operational details saved');return did;
end $$;
create function public.save_driver_identity(p_driver uuid,p_version integer,p_data jsonb) returns void language plpgsql security definer set search_path='' as $$
declare d public.drivers;v integer;
begin
 select * into d from public.drivers where id=p_driver for update;
 if not private.can_driver('drivers.identity.manage',p_driver,d.created_by) then raise exception 'Permission denied' using errcode='42501';end if;
 select version into v from public.driver_identity_details where driver_id=p_driver;
 if v is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
 insert into public.driver_identity_details(driver_id,father_name,cnic,licence_number,address,emergency_contact) values(p_driver,p_data->>'father_name',p_data->>'cnic',p_data->>'licence_number',p_data->>'address',p_data->>'emergency_contact') on conflict(driver_id) do update set father_name=excluded.father_name,cnic=excluded.cnic,licence_number=excluded.licence_number,address=excluded.address,emergency_contact=excluded.emergency_contact,version=public.driver_identity_details.version+1;
 perform private.audit('driver.identity','driver',p_driver::text,'Restricted identity details updated; values omitted');
end $$;
create function public.set_driver_duty(p_driver uuid,p_on_duty boolean) returns void language plpgsql security definer set search_path='' as $$
declare d public.drivers;
begin
 select * into d from public.drivers where id=p_driver for update;
 if not private.can_driver('duty.manage',p_driver,d.created_by) then raise exception 'Permission denied' using errcode='42501';end if;
 if p_on_duty then
  if d.employment_status<>'Active' then raise exception 'Driver must be active';end if;
  insert into public.driver_duty_sessions(driver_id,created_by) values(p_driver,auth.uid()) on conflict do nothing;
 else update public.driver_duty_sessions set ended_at=now() where driver_id=p_driver and ended_at is null;
 end if;
 perform private.audit('driver.duty','driver',p_driver::text,case when p_on_duty then 'Duty started' else 'Duty ended' end);
end $$;
create function public.assign_driver(p_vehicle uuid,p_driver uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare v public.vehicles;d public.drivers;
begin
 perform pg_advisory_xact_lock(87413002);
 select * into v from public.vehicles where id=p_vehicle for update;
 perform private.require_permission('assignments.manage',p_vehicle,v.created_by);
 if length(trim(p_reason))<3 then raise exception 'A reason is required';end if;
 if p_driver is not null then
  select * into d from public.drivers where id=p_driver for update;
  if v.status<>'Active' or d.employment_status<>'Active' or d.id is null then raise exception 'Vehicle and driver must both be active';end if;
  if exists(select 1 from public.vehicle_driver_assignments where driver_id=p_driver and vehicle_id<>p_vehicle and ended_at is null) then raise exception 'Driver already assigned to another vehicle';end if;
 end if;
 update public.vehicle_driver_assignments set ended_at=now() where vehicle_id=p_vehicle and ended_at is null;
 if p_driver is not null then insert into public.vehicle_driver_assignments(vehicle_id,driver_id,remarks,created_by) values(p_vehicle,p_driver,p_reason,auth.uid());end if;
 perform private.audit('vehicle.assign','vehicle',p_vehicle::text,p_reason);
end $$;
create function public.set_vehicle_scope(p_user uuid,p_vehicle uuid,p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.require_permission('users.roles');
 if not private.is_super() then raise exception 'Super Admin required for scope delegation' using errcode='42501';end if;
 if p_enabled then insert into public.user_vehicle_scopes values(p_user,p_vehicle) on conflict do nothing;else delete from public.user_vehicle_scopes where user_id=p_user and vehicle_id=p_vehicle;end if;
 perform private.audit('user.scope','user',p_user::text,'Vehicle scope updated');
end $$;
create function public.save_company(p_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid;
begin perform private.require_permission('vehicles.create',null,auth.uid());if length(trim(p_name)) not between 1 and 150 then raise exception 'Invalid company name';end if;insert into public.companies(name,created_by) values(trim(p_name),auth.uid()) returning id into cid;perform private.audit('company.create','company',cid::text,'Fleet company created');return cid;end $$;

do $$declare t text;begin
 foreach t in array array['companies','vehicles','vehicle_financials','drivers','driver_identity_details','user_vehicle_scopes','driver_duty_sessions','vehicle_driver_assignments'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;
create policy companies_read on public.companies for select to authenticated using(private.can('vehicles.view',null,created_by));
create policy vehicles_read on public.vehicles for select to authenticated using(private.can('vehicles.view',id,created_by));
create policy vehicle_financials_read on public.vehicle_financials for select to authenticated using(private.can('reports.financial.view',vehicle_id));
create policy drivers_read on public.drivers for select to authenticated using(private.can_driver('drivers.view',id,created_by));
create policy driver_identity_read on public.driver_identity_details for select to authenticated using(private.can_driver('drivers.identity.view',driver_id,null));
create policy scopes_read on public.user_vehicle_scopes for select to authenticated using(private.can('users.view'));
create policy duty_read on public.driver_duty_sessions for select to authenticated using(private.can_driver('drivers.view',driver_id,created_by));
create policy assignments_read on public.vehicle_driver_assignments for select to authenticated using(private.can('vehicles.view',vehicle_id,created_by));
revoke all on function private.can_driver(text,uuid,uuid) from public,anon,authenticated;
grant execute on function private.can_driver(text,uuid,uuid) to authenticated;
revoke all on function public.save_vehicle(uuid,integer,jsonb),public.save_driver(uuid,integer,jsonb),public.save_driver_identity(uuid,integer,jsonb),public.set_driver_duty(uuid,boolean),public.assign_driver(uuid,uuid,text),public.set_vehicle_scope(uuid,uuid,boolean),public.save_company(text) from public,anon,authenticated;
grant execute on function public.save_vehicle(uuid,integer,jsonb),public.save_driver(uuid,integer,jsonb),public.save_driver_identity(uuid,integer,jsonb),public.set_driver_duty(uuid,boolean),public.assign_driver(uuid,uuid,text),public.set_vehicle_scope(uuid,uuid,boolean),public.save_company(text) to authenticated;
