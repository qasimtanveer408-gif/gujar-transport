-- Gujjar Brother Transport: NEW EMPTY SUPABASE PROJECT ONLY.
-- Run this complete file once in the Supabase SQL Editor as postgres.
-- Do not use this file to update an existing app. Use db:migrate instead.
-- Everything is transactional; a failed statement rolls back this installation.
begin;
do $$begin
 if to_regclass('public.app_users') is not null then
  raise exception 'This database already contains the app. Use npm run db:migrate for updates.';
 end if;
end $$;
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations(version text primary key,statements text[],name text);

-- Migration: 20261005160027_identity.sql
-- Phase 1. All application passwords remain in Supabase Auth.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema private revoke execute on functions from public;

create table public.app_users (
 id uuid primary key references auth.users(id) on delete restrict,
 email text not null, display_name text not null check(length(display_name) between 1 and 120),
 active boolean not null default true, version integer not null default 1,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index app_users_email on public.app_users(lower(email));
create table public.roles (id uuid primary key default gen_random_uuid(), name text not null unique, reserved boolean not null default false, version integer not null default 1);
create table public.permissions (code text primary key, description text not null);
create table public.user_roles (user_id uuid references public.app_users(id) on delete restrict, role_id uuid references public.roles(id) on delete restrict, primary key(user_id,role_id));
create table public.role_permissions (
 role_id uuid references public.roles(id) on delete restrict, permission_code text references public.permissions(code),
 scope text not null check(scope in ('all','assigned','own')), primary key(role_id,permission_code)
);
create table private.app_sessions (
 token_hash text primary key check(length(token_hash)=64), user_id uuid not null references public.app_users(id),
 auth_session_id uuid not null, credentials text not null, expires_at timestamptz not null,
 revoked_at timestamptz, version integer not null default 1, refresh_owner uuid, refresh_deadline timestamptz,
 created_at timestamptz not null default now()
);
create index app_sessions_user on private.app_sessions(user_id,auth_session_id) where revoked_at is null;
create table private.provisioning_tasks (
 id uuid primary key default gen_random_uuid(), email text not null, display_name text not null,
 role_id uuid references public.roles(id), actor_id uuid references public.app_users(id),
 kind text not null check(kind in ('bootstrap','user')), state text not null default 'pending' check(state in ('pending','completed')),
 user_id uuid, created_at timestamptz not null default now()
);
create unique index provisioning_pending_email on private.provisioning_tasks(lower(email)) where state='pending';
create table public.audit_logs (
 id bigint generated always as identity primary key, actor_id uuid references public.app_users(id),
 action text not null, record_type text not null, record_id text, summary text not null,
 created_at timestamptz not null default now()
);
create table public.business_settings (
 id boolean primary key default true check(id), business_name text not null default 'Gujjar Brother Transport',
 contact_email text not null default 'attiqgujjar360gb@gmail.com',
 phone_1 text not null default '03481201249',phone_2 text not null default '03003486360',phone_3 text not null default '03002676328',
 address text, currency text not null default 'PKR' check(currency='PKR'), timezone text not null default 'Asia/Karachi' check(timezone='Asia/Karachi'),
 period_start_day integer not null default 1 check(period_start_day between 1 and 28), period_confirmed boolean not null default false,
 refresh_seconds integer not null default 60 check(refresh_seconds between 30 and 600),
 version integer not null default 1
);
insert into public.business_settings(id) values(true);

create function private.active_session() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.app_users u join private.app_sessions s on s.user_id=u.id
 where u.id=auth.uid() and u.active and s.auth_session_id::text=auth.jwt()->>'session_id'
 and s.revoked_at is null and s.expires_at>now())
$$;
create function private.is_super() returns boolean language sql stable security definer set search_path='' as $$
 select private.active_session() and exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=auth.uid() and r.reserved)
$$;
-- Record scopes are extended in the operations migration; NULL owner never grants own scope.
create function private.can(p_permission text,p_vehicle uuid default null,p_owner uuid default null) returns boolean language sql stable security definer set search_path='' as $$
 select private.active_session() and exists(select 1 from public.user_roles ur join public.role_permissions rp on rp.role_id=ur.role_id
 where ur.user_id=auth.uid() and rp.permission_code=p_permission and (rp.scope='all' or (rp.scope='own' and p_owner=auth.uid())))
$$;
create function private.require_permission(p_permission text,p_vehicle uuid default null,p_owner uuid default null) returns void language plpgsql security definer set search_path='' as $$
begin if not private.can(p_permission,p_vehicle,p_owner) then raise exception 'Permission denied' using errcode='42501'; end if; end $$;
create function private.audit(p_action text,p_type text,p_id text,p_summary text) returns void language sql security definer set search_path='' as $$
 insert into public.audit_logs(actor_id,action,record_type,record_id,summary) values(auth.uid(),p_action,p_type,p_id,left(p_summary,500))
$$;

insert into public.permissions(code,description)
select p,p from unnest(array[
 'users.view','users.create','users.disable','users.roles','roles.view','roles.manage','audit.view','settings.view','settings.manage',
 'vehicles.view','vehicles.create','vehicles.update','vehicles.archive','drivers.view','drivers.create','drivers.update','drivers.identity.view','drivers.identity.manage','drivers.documents.view',
 'duty.manage','assignments.manage','documents.view','documents.upload','documents.delete',
 'trips.view','trips.create','trips.update_own_draft','trips.update','trips.submit','trips.approve','trips.reject','trips.void','trips.finance.view',
 'expenses.view','expenses.create','expenses.approve','expenses.void','maintenance.view','maintenance.create','maintenance.approve',
 'bookings.view','bookings.create','bookings.approve','loans.view','loans.issue','loans.repay','payments.view','payments.create','payments.approve',
 'reports.operational.view','reports.financial.view','reports.export','accounts.close','accounts.reopen','accounts.view','accounts.create','alerts.view','imports.manage'
]) p;
insert into public.roles(name,reserved) values ('Super Admin',true),('Admin',false),('Operations Manager',false),('Accountant',false),('Data Entry',false),('Maintenance Manager',false),('Viewer',false);
insert into public.role_permissions select r.id,p.code,'all' from public.roles r cross join public.permissions p where r.reserved;
insert into public.role_permissions select r.id,p.code,'all' from public.roles r cross join public.permissions p where r.name='Admin' and p.code not in ('roles.manage','users.roles','drivers.identity.view','drivers.identity.manage','drivers.documents.view');
insert into public.role_permissions select r.id,p,'all' from public.roles r cross join unnest(array['vehicles.view','vehicles.create','vehicles.update','drivers.view','drivers.create','drivers.update','duty.manage','assignments.manage','trips.view','trips.create','trips.update','trips.submit','reports.operational.view','alerts.view','maintenance.view']) p where r.name='Operations Manager';
insert into public.role_permissions select r.id,p,'all' from public.roles r cross join unnest(array['vehicles.view','drivers.view','trips.view','trips.finance.view','trips.approve','trips.reject','trips.void','expenses.view','expenses.create','expenses.approve','expenses.void','maintenance.view','maintenance.approve','bookings.view','bookings.create','bookings.approve','loans.view','loans.issue','loans.repay','payments.view','payments.create','payments.approve','reports.operational.view','reports.financial.view','reports.export','accounts.view','accounts.create','accounts.close','accounts.reopen','alerts.view']) p where r.name='Accountant';
insert into public.role_permissions select r.id,p,case when p like 'trips.%' then 'own' else 'all' end from public.roles r cross join unnest(array['vehicles.view','drivers.view','trips.view','trips.create','trips.update_own_draft','trips.submit','documents.upload']) p where r.name='Data Entry';
insert into public.role_permissions select r.id,p,'assigned' from public.roles r cross join unnest(array['vehicles.view','maintenance.view','maintenance.create','documents.view','documents.upload']) p where r.name='Maintenance Manager';
insert into public.role_permissions select r.id,p,'all' from public.roles r cross join unnest(array['vehicles.view','drivers.view','trips.view','reports.operational.view']) p where r.name='Viewer';

create function public.my_access() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not private.active_session() then raise exception 'Sign in required' using errcode='42501'; end if;
 select jsonb_build_object('user',jsonb_build_object('id',u.id,'email',u.email,'display_name',u.display_name),
 'permissions',(select coalesce(jsonb_agg(distinct rp.permission_code),'[]'::jsonb) from public.user_roles ur join public.role_permissions rp on rp.role_id=ur.role_id where ur.user_id=u.id),
 'roles',(select coalesce(jsonb_agg(r.name),'[]'::jsonb) from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id)) into result from public.app_users u where u.id=auth.uid();
 return result;
end $$;

-- Server-only, narrowly scoped session broker RPCs. Credentials are AES-GCM ciphertext.
create function public.server_session_create(p_hash text,p_user uuid,p_auth_session uuid,p_credentials text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.app_users where id=p_user and active) then raise exception 'Account unavailable' using errcode='42501';end if;
 if not exists(select 1 from auth.sessions where id=p_auth_session and user_id=p_user) then raise exception 'Invalid Auth session' using errcode='42501';end if;
 insert into private.app_sessions(token_hash,user_id,auth_session_id,credentials,expires_at) values(p_hash,p_user,p_auth_session,p_credentials,now()+interval '12 hours');
end $$;
create function public.server_session_read(p_hash text) returns jsonb language sql security definer set search_path='' as $$
 select to_jsonb(s) from private.app_sessions s join public.app_users u on u.id=s.user_id
 where s.token_hash=p_hash and s.revoked_at is null and s.expires_at>now() and u.active
$$;
create function public.server_session_claim(p_hash text,p_version integer,p_owner uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare s private.app_sessions;
begin
 select * into s from private.app_sessions where token_hash=p_hash for update;
 if s.revoked_at is not null or s.expires_at<=now() or s.version is distinct from p_version then return false;end if;
 if s.refresh_owner is not null then
  -- A crashed refresher may already have rotated the remote token: fail closed.
  if s.refresh_deadline<=now() then update private.app_sessions set revoked_at=now() where token_hash=p_hash;end if;
  return false;
 end if;
 update private.app_sessions set refresh_owner=p_owner,refresh_deadline=now()+interval '20 seconds' where token_hash=p_hash;
 return found;
end $$;
create function public.server_session_rotate(p_hash text,p_version integer,p_owner uuid,p_credentials text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 update private.app_sessions set credentials=p_credentials,version=version+1,refresh_owner=null,refresh_deadline=null
 where token_hash=p_hash and version=p_version and refresh_owner=p_owner and revoked_at is null and expires_at>now();
 return found;
end $$;
create function public.server_session_revoke(p_hash text) returns void language sql security definer set search_path='' as $$
 update private.app_sessions set revoked_at=now(),version=version+1 where token_hash=p_hash and revoked_at is null
$$;
create function public.revoke_my_sessions() returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.active_session() then raise exception 'Sign in required' using errcode='42501';end if;
 perform private.audit('sessions.revoke_all','user',auth.uid()::text,'All application sessions revoked');
 update private.app_sessions set revoked_at=now(),version=version+1 where user_id=auth.uid() and revoked_at is null;
end $$;

create function public.server_bootstrap_begin(p_email text) returns jsonb language plpgsql security definer set search_path='' as $$
declare task private.provisioning_tasks; existing_id uuid;
begin
 perform pg_advisory_xact_lock(87413001);
 select u.id into existing_id from public.app_users u join public.user_roles ur on ur.user_id=u.id join public.roles r on r.id=ur.role_id where r.reserved and lower(u.email)=lower(p_email) and u.active;
 if existing_id is not null then return jsonb_build_object('state','completed','user_id',existing_id);end if;
 if exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where r.reserved) then raise exception 'Bootstrap already completed; use an authorized administrator';end if;
 insert into private.provisioning_tasks(email,display_name,role_id,kind) select lower(p_email),'System Owner',id,'bootstrap' from public.roles where reserved on conflict do nothing;
 select * into task from private.provisioning_tasks where lower(email)=lower(p_email) and state='pending' and kind='bootstrap';
 if task.id is null then raise exception 'Provisioning conflict';end if;
 return to_jsonb(task);
end $$;
create function public.begin_user_provisioning(p_email text,p_name text,p_role uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare task private.provisioning_tasks;
begin
 perform private.require_permission('users.create');
 if not exists(select 1 from public.roles where id=p_role) then raise exception 'Unknown role';end if;
 if exists(select 1 from public.roles where id=p_role and reserved) and not private.is_super() then raise exception 'Cannot assign Super Admin' using errcode='42501';end if;
 if not private.is_super() and exists(select 1 from public.role_permissions target where target.role_id=p_role and not exists(
 select 1 from public.role_permissions mine join public.user_roles ur on ur.role_id=mine.role_id where ur.user_id=auth.uid() and mine.permission_code=target.permission_code and (mine.scope='all' or mine.scope=target.scope))) then raise exception 'Role exceeds your delegation authority' using errcode='42501';end if;
 if exists(select 1 from public.app_users where lower(email)=lower(p_email)) then raise exception 'Account already linked';end if;
 if length(p_name) not between 1 and 120 then raise exception 'Invalid name';end if;
 insert into private.provisioning_tasks(email,display_name,role_id,kind,actor_id) values(lower(p_email),p_name,p_role,'user',auth.uid()) on conflict do nothing;
 select * into task from private.provisioning_tasks where lower(email)=lower(p_email) and state='pending' and actor_id=auth.uid() and role_id=p_role;
 if task.id is null then raise exception 'Provisioning conflict';end if;
 return to_jsonb(task);
end $$;
create function public.server_provision_finish(p_task uuid,p_user uuid) returns void language plpgsql security definer set search_path='' as $$
declare task private.provisioning_tasks;
begin
 perform pg_advisory_xact_lock(87413001);
 select * into task from private.provisioning_tasks where id=p_task for update;
 if task.state='completed' and task.user_id=p_user then return;end if;
 if task.id is null or task.state<>'pending' then raise exception 'Invalid provisioning task';end if;
 if not exists(select 1 from auth.users where id=p_user and lower(email)=task.email and raw_app_meta_data->>'gbt_provisioning_id'=p_task::text) then raise exception 'Auth identity does not match provisioning task';end if;
 if task.kind='bootstrap' and exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where r.reserved) then raise exception 'Bootstrap already completed';end if;
 if task.kind='user' and not exists(select 1 from public.app_users u join public.user_roles ur on ur.user_id=u.id join public.role_permissions rp on rp.role_id=ur.role_id where u.id=task.actor_id and u.active and rp.permission_code='users.create' and rp.scope='all') then raise exception 'Provisioning authorization expired' using errcode='42501';end if;
 -- Recheck delegation at commit; permissions may have changed during the Auth call.
 if task.kind='user' and not exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=task.actor_id and r.reserved) and (
 exists(select 1 from public.roles where id=task.role_id and reserved) or exists(select 1 from public.role_permissions target where target.role_id=task.role_id and not exists(select 1 from public.role_permissions mine join public.user_roles ur on ur.role_id=mine.role_id where ur.user_id=task.actor_id and mine.permission_code=target.permission_code and (mine.scope='all' or mine.scope=target.scope)))) then raise exception 'Delegation authorization changed' using errcode='42501';end if;
 insert into public.app_users(id,email,display_name) values(p_user,task.email,task.display_name);
 insert into public.user_roles(user_id,role_id) values(p_user,task.role_id);
 update private.provisioning_tasks set state='completed',user_id=p_user where id=p_task;
 insert into public.audit_logs(actor_id,action,record_type,record_id,summary) values(task.actor_id,'user.provision','user',p_user::text,'Auth account linked to application role');
end $$;

create function public.set_user_access(p_user uuid,p_active boolean,p_role uuid,p_version integer,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare target public.app_users;old_role uuid;
begin
 perform private.require_permission('users.disable');
 if length(trim(p_reason))<3 then raise exception 'A reason is required';end if;
 perform pg_advisory_xact_lock(87413001);
 select * into target from public.app_users where id=p_user for update;
 if target.id is null or target.version<>p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
 select role_id into old_role from public.user_roles where user_id=p_user;
 if p_role is distinct from old_role then perform private.require_permission('users.roles');end if;
 if not exists(select 1 from public.roles where id=p_role) then raise exception 'Unknown role';end if;
 if (exists(select 1 from public.roles where id in (p_role,old_role) and reserved)) and not private.is_super() then raise exception 'Super Admin required' using errcode='42501';end if;
 if p_role is distinct from old_role and not private.is_super() and exists(select 1 from public.role_permissions target_grant where target_grant.role_id=p_role and not exists(select 1 from public.role_permissions mine join public.user_roles ur on ur.role_id=mine.role_id where ur.user_id=auth.uid() and mine.permission_code=target_grant.permission_code and (mine.scope='all' or mine.scope=target_grant.scope))) then raise exception 'Role exceeds delegation authority' using errcode='42501';end if;
 if target.active and exists(select 1 from public.roles where id=old_role and reserved) and (not p_active or not exists(select 1 from public.roles where id=p_role and reserved)) and not exists(select 1 from public.app_users u join public.user_roles ur on ur.user_id=u.id join public.roles r on r.id=ur.role_id where u.active and r.reserved and u.id<>p_user) then raise exception 'The last active Super Admin must remain active';end if;
 update public.app_users set active=p_active,version=version+1,updated_at=now() where id=p_user;
 delete from public.user_roles where user_id=p_user;
 insert into public.user_roles values(p_user,p_role);
 update private.app_sessions set revoked_at=now(),version=version+1 where user_id=p_user and revoked_at is null;
 perform private.audit('user.access','user',p_user::text,p_reason);
end $$;
create function public.save_role(p_id uuid,p_name text,p_version integer,p_grants jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare rid uuid; item jsonb;
begin
 perform private.require_permission('roles.manage');
 perform pg_advisory_xact_lock(87413001);
 if length(trim(p_name)) not between 2 and 80 or jsonb_typeof(p_grants)<>'array' then raise exception 'Invalid role';end if;
 if p_id is null then insert into public.roles(name) values(trim(p_name)) returning id into rid;
 else
  if exists(select 1 from public.roles where id=p_id and reserved) then raise exception 'Reserved Super Admin role is immutable';end if;
  update public.roles set name=trim(p_name),version=version+1 where id=p_id and version=p_version returning id into rid;
  if rid is null then raise exception 'Record changed; reload' using errcode='40001';end if;
 end if;
 for item in select value from jsonb_array_elements(p_grants) loop
  if not private.is_super() and not exists(select 1 from public.role_permissions rp join public.user_roles ur on ur.role_id=rp.role_id where ur.user_id=auth.uid() and rp.permission_code=item->>'permission_code' and (rp.scope='all' or rp.scope=item->>'scope')) then raise exception 'Grant exceeds delegation authority' using errcode='42501';end if;
 end loop;
 delete from public.role_permissions where role_id=rid;
 insert into public.role_permissions(role_id,permission_code,scope) select rid,e->>'permission_code',e->>'scope' from jsonb_array_elements(p_grants)e;
 perform private.audit('role.save','role',rid::text,'Permission matrix updated');return rid;
end $$;
create function public.save_business_settings(p_data jsonb,p_version integer) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.require_permission('settings.manage');
 update public.business_settings set business_name=coalesce(p_data->>'business_name',business_name),contact_email=coalesce(p_data->>'contact_email',contact_email),
 phone_1=coalesce(p_data->>'phone_1',phone_1),phone_2=coalesce(p_data->>'phone_2',phone_2),phone_3=coalesce(p_data->>'phone_3',phone_3),address=p_data->>'address',
 period_start_day=coalesce((p_data->>'period_start_day')::integer,period_start_day),period_confirmed=coalesce((p_data->>'period_confirmed')::boolean,period_confirmed),refresh_seconds=coalesce((p_data->>'refresh_seconds')::integer,refresh_seconds),version=version+1 where id and version=p_version;
 if not found then raise exception 'Record changed; reload' using errcode='40001';end if;
 perform private.audit('settings.save','settings','business','Business settings updated');
end $$;

create function public.server_admin_reset(p_user uuid,p_email text,p_stage text) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_stage not in ('requested','completed') then raise exception 'Invalid reset stage';end if;
 if not exists(select 1 from public.app_users u join public.user_roles ur on ur.user_id=u.id join public.roles r on r.id=ur.role_id where u.id=p_user and lower(u.email)=lower(p_email) and r.reserved and u.active) then raise exception 'Active Super Admin target does not match';end if;
 update private.app_sessions set revoked_at=now(),version=version+1 where user_id=p_user and revoked_at is null;
 insert into public.audit_logs(action,record_type,record_id,summary) values('admin.reset.'||p_stage,'user',p_user::text,'Explicit server administrator reset; all application sessions revoked');
end $$;

-- Table reads use RLS; writes only go through the reviewed action functions above.
alter table public.app_users enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.business_settings enable row level security;
alter table public.audit_logs enable row level security;
revoke all on public.app_users,public.roles,public.permissions,public.user_roles,public.role_permissions,public.business_settings,public.audit_logs from anon,authenticated;
grant select on public.app_users,public.roles,public.permissions,public.user_roles,public.role_permissions,public.business_settings,public.audit_logs to authenticated;
create policy users_read on public.app_users for select to authenticated using (private.can('users.view') or (id=auth.uid() and private.active_session()));
create policy roles_read on public.roles for select to authenticated using (private.can('roles.view') or private.can('users.create') or private.can('users.view'));
create policy permissions_read on public.permissions for select to authenticated using(private.can('roles.view'));
create policy user_roles_read on public.user_roles for select to authenticated using(private.can('users.view'));
create policy role_permissions_read on public.role_permissions for select to authenticated using(private.can('roles.view'));
create policy settings_read on public.business_settings for select to authenticated using(private.active_session());
create policy audit_read on public.audit_logs for select to authenticated using(private.can('audit.view'));

revoke all on all tables in schema private from public,anon,authenticated;
revoke all on all functions in schema private from public,anon,authenticated;
revoke all on all functions in schema public from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.active_session(),private.can(text,uuid,uuid) to authenticated;
grant execute on function public.my_access(), public.revoke_my_sessions(),public.begin_user_provisioning(text,text,uuid),public.set_user_access(uuid,boolean,uuid,integer,text),public.save_role(uuid,text,integer,jsonb),public.save_business_settings(jsonb,integer) to authenticated;
grant execute on function public.server_session_create(text,uuid,uuid,text),public.server_session_read(text),public.server_session_claim(text,integer,uuid),public.server_session_rotate(text,integer,uuid,text),public.server_session_revoke(text),public.server_bootstrap_begin(text),public.server_provision_finish(uuid,uuid),public.server_admin_reset(uuid,text,text) to service_role;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261005160027','identity',array[]::text[]);

-- Migration: 20261005161100_throttle.sql
create table private.request_limits (key text primary key,window_start timestamptz not null,hits integer not null,expires_at timestamptz not null);
revoke all on private.request_limits from public,anon,authenticated;
create function public.server_throttle(p_key text,p_limit integer,p_seconds integer) returns boolean language plpgsql security definer set search_path='' as $$
declare count_hits integer;bucket timestamptz;
begin
 if p_limit not between 1 and 10000 or p_seconds not between 1 and 3600 or length(p_key)>200 then raise exception 'Invalid limiter';end if;
 bucket=to_timestamp(floor(extract(epoch from now())/p_seconds)*p_seconds);
 insert into private.request_limits(key,window_start,hits,expires_at) values(p_key,bucket,1,bucket+make_interval(secs=>p_seconds*2))
 on conflict(key) do update set hits=case when private.request_limits.window_start=excluded.window_start then private.request_limits.hits+1 else 1 end,window_start=excluded.window_start,expires_at=excluded.expires_at returning hits into count_hits;
 return count_hits<=p_limit;
end $$;
revoke all on function public.server_throttle(text,integer,integer) from public,anon,authenticated;
grant execute on function public.server_throttle(text,integer,integer) to service_role;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261005161100','throttle',array[]::text[]);

-- Migration: 20261005161237_fleet.sql
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

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261005161237','fleet',array[]::text[]);

-- Migration: 20261005161449_accounts.sql
create table public.accounting_periods(id uuid primary key default gen_random_uuid(),name text not null unique,start_date date not null,end_date date not null,status text not null default 'Open' check(status in ('Open','Closed','Reopened')),version integer not null default 1,check(end_date>=start_date));
create table public.period_close_snapshots(id uuid primary key default gen_random_uuid(),period_id uuid not null references public.accounting_periods(id),close_version integer not null,summary jsonb not null,closed_by uuid not null references public.app_users(id),closed_at timestamptz not null default now(),unique(period_id,close_version));
create sequence public.trip_number;
create table public.trips (
 id uuid primary key default gen_random_uuid(),trip_number text not null unique default ('GBT-'||lpad(nextval('public.trip_number')::text,7,'0')),
 business_date date not null,vehicle_id uuid not null references public.vehicles(id),driver_id uuid not null references public.drivers(id),
 cycle_number text not null,origin text not null,destination text not null,route_description text,cargo text,customer_reference text,
 operational_state text not null default 'Planned' check(operational_state in ('Planned','In Progress','Completed','Cancelled')),
 financial_state text not null default 'Draft' check(financial_state in ('Draft','Submitted','Approved','Rejected','Voided')),
 start_odometer numeric(14,3) not null check(start_odometer>=0),end_odometer numeric(14,3),
 fuel_litres numeric(14,3) check(fuel_litres>=0),fuel_basis text not null default 'purchase_estimate' check(fuel_basis in ('measured','tank_reconciled','purchase_estimate')),
 weight numeric(14,3) check(weight>=0),weight_unit text not null default 'metric tonnes' check(weight_unit in ('metric tonnes','kg')),
 remarks text,created_by uuid not null references public.app_users(id),created_at timestamptz not null default now(),version integer not null default 1,
 check(end_odometer is null or end_odometer>=start_odometer),unique(vehicle_id,cycle_number)
);
create index trips_dates on public.trips(business_date,vehicle_id,driver_id);
create index trips_owner on public.trips(created_by);
create table public.trip_financials(trip_id uuid primary key references public.trips(id),fare numeric(18,2) not null check(fare>=0));
create table public.expense_categories(code text primary key,label text not null,active boolean not null default true);
insert into public.expense_categories values ('diesel','Diesel',true),('tolls','Tolls',true),('fines_permits','Documented fines / permit fees',true),('food','Food',true),('reward','Reward',true),('service','Service',true),('parking','Parking',true),('engine_oil','Engine oil',true),('commission','Driver cycle commission',true),('other','Other',true);
create table public.trip_expense_lines(id uuid primary key default gen_random_uuid(),trip_id uuid not null references public.trips(id),category text not null references public.expense_categories(code),business_date date not null,amount numeric(18,2) not null check(amount>=0),description text not null default '');
create index trip_expense_parent on public.trip_expense_lines(trip_id);
create table public.trip_status_history(id bigint generated always as identity primary key,trip_id uuid not null references public.trips(id),state text not null,reason text,actor_id uuid not null references public.app_users(id),created_at timestamptz not null default now());
create table public.maintenance_categories(code text primary key,label text not null);
insert into public.maintenance_categories values ('engine','Engine'),('gearbox','Gearbox'),('parts','Mechanical Parts'),('tyres','Tyres'),('wiring','Electrical Wiring'),('starter','Starter Motor'),('alternator','Alternator / Generator'),('lighting','Lighting'),('cabin','Cabin'),('body','Body'),('oil_change','Oil Change');
create table public.maintenance_records(
 id uuid primary key default gen_random_uuid(),vehicle_id uuid not null references public.vehicles(id),driver_id uuid references public.drivers(id),trip_id uuid references public.trips(id),
 business_date date not null,odometer numeric(14,3) not null check(odometer>=0),category text not null references public.maintenance_categories(code),description text not null,supplier text,
 next_service_date date,next_service_odometer numeric(14,3),remarks text,
 state text not null default 'Draft' check(state in ('Draft','Approved','Voided','Review')),
 created_by uuid not null references public.app_users(id),created_at timestamptz not null default now(),version integer not null default 1
);
create table public.maintenance_items(id uuid primary key default gen_random_uuid(),maintenance_id uuid not null references public.maintenance_records(id),kind text not null check(kind in ('Parts','Labour','Other')),description text not null,amount numeric(18,2) not null check(amount>=0),part_identifier text,tyre_position text,warranty_until date);
create table public.oil_changes(maintenance_id uuid primary key references public.maintenance_records(id),specification text not null,quantity_litres numeric(12,3) not null check(quantity_litres>0),previous_date date,previous_odometer numeric(14,3),next_due_odometer numeric(14,3));
create table public.office_expenses(id uuid primary key default gen_random_uuid(),business_date date not null,category text not null,description text not null,amount numeric(18,2) not null check(amount>=0),vehicle_id uuid references public.vehicles(id),driver_id uuid references public.drivers(id),payment_method text not null,remarks text,state text not null default 'Draft' check(state in ('Draft','Approved','Voided')),created_by uuid not null references public.app_users(id),version integer not null default 1);
create table public.office_bookings(id uuid primary key default gen_random_uuid(),business_date date not null,trip_id uuid references public.trips(id),external_vehicle text,driver_contact text,cargo text,origin text not null,destination text not null,quoted_freight numeric(18,2) not null check(quoted_freight>=0),commission numeric(18,2) not null check(commission>=0),description text,state text not null default 'Draft' check(state in ('Draft','Approved','Voided')),created_by uuid not null references public.app_users(id),version integer not null default 1,check((trip_id is not null)<>(external_vehicle is not null)),check(trip_id is null or commission=0));
create table public.driver_earnings(id uuid primary key default gen_random_uuid(),driver_id uuid not null references public.drivers(id),business_date date not null,kind text not null check(kind in ('Salary','Commission','Allowance','Reward')),amount numeric(18,2) not null check(amount>0),state text not null default 'Accrued' check(state in ('Accrued','Voided')),trip_line_id uuid unique references public.trip_expense_lines(id),rule_snapshot text not null,created_by uuid not null references public.app_users(id));
create table public.revenue_entries(id uuid primary key default gen_random_uuid(),business_date date not null,amount numeric(18,2) not null,kind text not null check(kind in ('Transport','Brokerage')),vehicle_id uuid references public.vehicles(id),driver_id uuid references public.drivers(id),trip_id uuid references public.trips(id),booking_id uuid references public.office_bookings(id),reversal_of uuid unique references public.revenue_entries(id),created_by uuid not null references public.app_users(id),created_at timestamptz not null default now(),check(num_nonnulls(trip_id,booking_id)=1),check((reversal_of is null and amount>=0) or (reversal_of is not null and amount<=0)));
create unique index revenue_trip_once on public.revenue_entries(trip_id) where reversal_of is null and trip_id is not null;
create unique index revenue_booking_once on public.revenue_entries(booking_id) where reversal_of is null and booking_id is not null;
create index revenue_dates on public.revenue_entries(business_date,vehicle_id);
create table public.expense_entries(id uuid primary key default gen_random_uuid(),business_date date not null,amount numeric(18,2) not null,category text not null,vehicle_id uuid references public.vehicles(id),driver_id uuid references public.drivers(id),trip_id uuid references public.trips(id),trip_line_id uuid references public.trip_expense_lines(id),maintenance_item_id uuid references public.maintenance_items(id),office_expense_id uuid references public.office_expenses(id),earning_id uuid references public.driver_earnings(id),reversal_of uuid unique references public.expense_entries(id),created_by uuid not null references public.app_users(id),created_at timestamptz not null default now(),check(num_nonnulls(trip_line_id,maintenance_item_id,office_expense_id,earning_id)=1),check((reversal_of is null and amount>=0) or (reversal_of is not null and amount<=0)));
create unique index expense_trip_once on public.expense_entries(trip_line_id) where reversal_of is null and trip_line_id is not null;
create unique index expense_maintenance_once on public.expense_entries(maintenance_item_id) where reversal_of is null and maintenance_item_id is not null;
create unique index expense_office_once on public.expense_entries(office_expense_id) where reversal_of is null and office_expense_id is not null;
create unique index expense_earning_once on public.expense_entries(earning_id) where reversal_of is null and earning_id is not null;
create index expense_dates on public.expense_entries(business_date,vehicle_id);
create table public.driver_loans(id uuid primary key default gen_random_uuid(),driver_id uuid not null references public.drivers(id),reference text not null unique,due_date date,created_by uuid not null references public.app_users(id));
create table public.driver_loan_transactions(id uuid primary key default gen_random_uuid(),loan_id uuid not null references public.driver_loans(id),business_date date not null,kind text not null check(kind in ('Opening','Disbursement','Repayment')),amount numeric(18,2) not null check(amount>0),reference text not null unique,created_by uuid not null references public.app_users(id),created_at timestamptz not null default now());
create table public.driver_payments(id uuid primary key default gen_random_uuid(),driver_id uuid not null references public.drivers(id),business_date date not null,amount numeric(18,2) not null check(amount>0),reference text not null unique,created_by uuid not null references public.app_users(id),created_at timestamptz not null default now());
create table public.driver_payment_allocations(payment_id uuid references public.driver_payments(id),earning_id uuid references public.driver_earnings(id),amount numeric(18,2) not null check(amount>0),primary key(payment_id,earning_id));
create table public.cash_transactions(id uuid primary key default gen_random_uuid(),business_date date not null,direction text not null check(direction in ('Receipt','Payment')),amount numeric(18,2) not null check(amount>0),reference text not null unique,loan_transaction_id uuid unique references public.driver_loan_transactions(id),driver_payment_id uuid unique references public.driver_payments(id),created_by uuid not null references public.app_users(id));
create table public.settlement_allocations(id uuid primary key default gen_random_uuid(),cash_transaction_id uuid not null references public.cash_transactions(id),revenue_entry_id uuid references public.revenue_entries(id),expense_entry_id uuid references public.expense_entries(id),amount numeric(18,2) not null check(amount>0),check(num_nonnulls(revenue_entry_id,expense_entry_id)=1));
create table public.idempotency_keys(key uuid primary key,actor_id uuid not null references public.app_users(id),action text not null,record_id uuid not null,payload_hash text not null,created_at timestamptz not null default now());

create function private.open_period(p_date date) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.accounting_periods;
begin
 -- All posting/closing workflows take this lock FIRST. Low-volume fleet ledger: intentional serialization.
 perform pg_advisory_xact_lock(87413003);
 if not exists(select 1 from public.business_settings where id and period_confirmed) then raise exception 'Confirm the accounting-period setting before financial entry';end if;
 select * into p from public.accounting_periods where p_date between start_date and end_date for update;
 if p.id is null then raise exception 'Create an accounting period covering this date';end if;
 if p.status='Closed' then raise exception 'Accounting period is closed';end if;return p.id;
end $$;
create function private.claim_action(p_key uuid,p_action text,p_record uuid,p_payload text) returns boolean language plpgsql security definer set search_path='' as $$
declare existing public.idempotency_keys;
begin
 insert into public.idempotency_keys(key,actor_id,action,record_id,payload_hash) values(p_key,auth.uid(),p_action,p_record,md5(p_payload)) on conflict do nothing;
 if found then return true;end if;
 select * into existing from public.idempotency_keys where key=p_key;
 if existing.actor_id<>auth.uid() or existing.action<>p_action or existing.record_id<>p_record or existing.payload_hash<>md5(p_payload) then raise exception 'Idempotency key reused with different input';end if;return false;
end $$;
create function public.create_period(p_name text,p_start date,p_end date) returns uuid language plpgsql security definer set search_path='' as $$
declare pid uuid;
begin
 perform private.require_permission('accounts.create');perform pg_advisory_xact_lock(87413003);
 if p_end<p_start or length(trim(p_name))<2 then raise exception 'Invalid accounting period';end if;
 if exists(select 1 from public.accounting_periods where daterange(start_date,end_date,'[]')&&daterange(p_start,p_end,'[]')) then raise exception 'Accounting periods cannot overlap';end if;
 insert into public.accounting_periods(name,start_date,end_date) values(trim(p_name),p_start,p_end) returning id into pid;perform private.audit('period.create','period',pid::text,'Accounting period created');return pid;
end $$;
create function public.save_trip(p_id uuid,p_version integer,p_data jsonb,p_lines jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare t public.trips;vid uuid;did uuid;tid uuid;old_date date;op text;line jsonb;
begin
 perform pg_advisory_xact_lock(87413003);
 vid=(p_data->>'vehicle_id')::uuid;did=(p_data->>'driver_id')::uuid;op=p_data->>'operational_state';
 if p_id is null then perform private.require_permission('trips.create',vid,auth.uid());else
  select * into t from public.trips where id=p_id for update;old_date=t.business_date;
  if not (private.can('trips.update',t.vehicle_id,t.created_by) or (t.created_by=auth.uid() and private.can('trips.update_own_draft',t.vehicle_id,t.created_by))) then raise exception 'Permission denied' using errcode='42501';end if;
  if t.financial_state not in ('Draft','Rejected') then raise exception 'Only drafts and rejected trips can be edited';end if;
  if t.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
  if vid<>t.vehicle_id or did<>t.driver_id then raise exception 'Vehicle and driver are fixed; cancel the draft and create a replacement';end if;
  perform private.open_period(old_date);
 end if;
 perform private.open_period((p_data->>'business_date')::date);
 perform 1 from public.vehicles where id=vid for update;
 if not exists(select 1 from public.vehicles where id=vid and status='Active') or not exists(select 1 from public.drivers where id=did and employment_status='Active') then raise exception 'Vehicle and driver must be active';end if;
 if not private.can('vehicles.view',vid,(select created_by from public.vehicles where id=vid)) or not private.can_driver('drivers.view',did,(select created_by from public.drivers where id=did)) then raise exception 'Linked record out of scope' using errcode='42501';end if;
 if not exists(select 1 from public.vehicle_driver_assignments where vehicle_id=vid and driver_id=did and (started_at at time zone 'Asia/Karachi')::date<=(p_data->>'business_date')::date and (ended_at is null or (ended_at at time zone 'Asia/Karachi')::date>=(p_data->>'business_date')::date)) then raise exception 'Create a matching vehicle-driver assignment first';end if;
 if op='Completed' and nullif(p_data->>'end_odometer','') is null then raise exception 'Completed trips require an end odometer';end if;
 if (p_data->>'start_odometer')::numeric < (select opening_odometer from public.vehicles where id=vid) then raise exception 'Trip starts below vehicle opening odometer';end if;
 if op<>'Cancelled' and nullif(p_data->>'end_odometer','') is not null and exists(select 1 from public.trips x where x.vehicle_id=vid and x.id is distinct from p_id and x.operational_state<>'Cancelled' and x.financial_state<>'Voided' and x.end_odometer is not null and numrange(x.start_odometer,x.end_odometer,'[)')&&numrange((p_data->>'start_odometer')::numeric,(p_data->>'end_odometer')::numeric,'[)')) then raise exception 'Odometer range overlaps another trip';end if;
 if p_id is null then
  insert into public.trips(business_date,vehicle_id,driver_id,cycle_number,origin,destination,route_description,cargo,customer_reference,operational_state,start_odometer,end_odometer,fuel_litres,fuel_basis,weight,weight_unit,remarks,created_by)
  values((p_data->>'business_date')::date,vid,did,p_data->>'cycle_number',p_data->>'origin',p_data->>'destination',p_data->>'route_description',p_data->>'cargo',p_data->>'customer_reference',op,(p_data->>'start_odometer')::numeric,nullif(p_data->>'end_odometer','')::numeric,nullif(p_data->>'fuel_litres','')::numeric,p_data->>'fuel_basis',nullif(p_data->>'weight','')::numeric,coalesce(p_data->>'weight_unit','metric tonnes'),p_data->>'remarks',auth.uid()) returning id into tid;
 else
  update public.trips set business_date=(p_data->>'business_date')::date,cycle_number=p_data->>'cycle_number',origin=p_data->>'origin',destination=p_data->>'destination',route_description=p_data->>'route_description',cargo=p_data->>'cargo',customer_reference=p_data->>'customer_reference',operational_state=op,start_odometer=(p_data->>'start_odometer')::numeric,end_odometer=nullif(p_data->>'end_odometer','')::numeric,fuel_litres=nullif(p_data->>'fuel_litres','')::numeric,fuel_basis=p_data->>'fuel_basis',weight=nullif(p_data->>'weight','')::numeric,weight_unit=coalesce(p_data->>'weight_unit','metric tonnes'),remarks=p_data->>'remarks',financial_state='Draft',version=version+1 where id=p_id;tid=p_id;
 end if;
 if p_data?'fare' then
  if p_id is not null then perform private.require_permission('trips.finance.view',vid,t.created_by);end if;
  insert into public.trip_financials values(tid,(p_data->>'fare')::numeric) on conflict(trip_id) do update set fare=excluded.fare;
 elsif p_id is null then insert into public.trip_financials values(tid,0);end if;
 if p_lines is not null then
  if p_id is not null then perform private.require_permission('trips.finance.view',vid,t.created_by);end if;
  if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)>100 then raise exception 'Invalid expense lines';end if;
  delete from public.trip_expense_lines where trip_id=tid;
  for line in select value from jsonb_array_elements(p_lines) loop
   perform private.open_period((line->>'business_date')::date);
   insert into public.trip_expense_lines(trip_id,category,business_date,amount,description) values(tid,line->>'category',(line->>'business_date')::date,(line->>'amount')::numeric,coalesce(line->>'description',''));
  end loop;
 end if;
 insert into public.trip_status_history(trip_id,state,actor_id) values(tid,'Draft / '||op,auth.uid());
 perform private.audit('trip.save','trip',tid::text,'Trip draft saved');return tid;
end $$;
create function public.trip_action(p_trip uuid,p_action text,p_version integer,p_reason text,p_key uuid) returns void language plpgsql security definer set search_path='' as $$
declare t public.trips;fare numeric;line public.trip_expense_lines;
begin
 perform pg_advisory_xact_lock(87413003);select * into t from public.trips where id=p_trip for update;
 if t.id is null then raise exception 'Trip unavailable';end if;
 if p_action not in ('submit','approve','reject','void') then raise exception 'Unknown action';end if;
 perform private.require_permission('trips.'||p_action,t.vehicle_id,t.created_by);
 if not private.claim_action(p_key,'trip.'||p_action,p_trip,p_version::text||coalesce(p_reason,'')) then return;end if;
 if t.version<>p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
 perform private.open_period(t.business_date);
 if p_action='submit' then
  if t.financial_state<>'Draft' or t.operational_state<>'Completed' then raise exception 'Complete the draft trip before submitting';end if;
  update public.trips set financial_state='Submitted',version=version+1 where id=p_trip;
 elsif p_action='reject' then
  if t.financial_state<>'Submitted' or length(trim(p_reason))<3 then raise exception 'Reject only a submitted trip, with a reason';end if;
  update public.trips set financial_state='Rejected',version=version+1 where id=p_trip;
 elsif p_action='approve' then
  if t.financial_state<>'Submitted' or t.operational_state<>'Completed' or t.end_odometer is null then raise exception 'Only a completed, submitted trip can be approved';end if;
  select f.fare into fare from public.trip_financials f where f.trip_id=p_trip;
  insert into public.revenue_entries(business_date,amount,kind,vehicle_id,driver_id,trip_id,created_by) values(t.business_date,fare,'Transport',t.vehicle_id,t.driver_id,p_trip,auth.uid());
  for line in select * from public.trip_expense_lines where trip_id=p_trip loop
   perform private.open_period(line.business_date);
   insert into public.expense_entries(business_date,amount,category,vehicle_id,driver_id,trip_id,trip_line_id,created_by) values(line.business_date,line.amount,line.category,t.vehicle_id,t.driver_id,p_trip,line.id,auth.uid());
   if line.category='commission' and line.amount>0 then insert into public.driver_earnings(driver_id,business_date,kind,amount,trip_line_id,rule_snapshot,created_by) values(t.driver_id,line.business_date,'Commission',line.amount,line.id,'Fixed amount entered on approved trip',auth.uid());end if;
  end loop;
  update public.vehicles set current_odometer=greatest(current_odometer,t.end_odometer) where id=t.vehicle_id;
  update public.trips set financial_state='Approved',version=version+1 where id=p_trip;
 else
  if t.financial_state<>'Approved' or length(trim(p_reason))<3 then raise exception 'Void only an approved trip, with a reason';end if;
  if exists(select 1 from public.driver_earnings e join public.driver_payment_allocations a on a.earning_id=e.id where e.trip_line_id in(select id from public.trip_expense_lines where trip_id=p_trip)) then raise exception 'Trip commission already settled; a reviewed adjustment is required';end if;
  if exists(select 1 from public.settlement_allocations where revenue_entry_id in(select id from public.revenue_entries where trip_id=p_trip) or expense_entry_id in(select id from public.expense_entries where trip_id=p_trip)) then raise exception 'Trip has cash settlements; a reviewed adjustment is required';end if;
  for line in select * from public.trip_expense_lines where trip_id=p_trip loop perform private.open_period(line.business_date);end loop;
  insert into public.revenue_entries(business_date,amount,kind,vehicle_id,driver_id,trip_id,reversal_of,created_by) select business_date,-amount,kind,vehicle_id,driver_id,trip_id,id,auth.uid() from public.revenue_entries where trip_id=p_trip and reversal_of is null;
  insert into public.expense_entries(business_date,amount,category,vehicle_id,driver_id,trip_id,trip_line_id,reversal_of,created_by) select business_date,-amount,category,vehicle_id,driver_id,trip_id,trip_line_id,id,auth.uid() from public.expense_entries where trip_id=p_trip and trip_line_id is not null and reversal_of is null;
  update public.driver_earnings set state='Voided' where trip_line_id in(select id from public.trip_expense_lines where trip_id=p_trip);
  update public.trips set financial_state='Voided',version=version+1 where id=p_trip;
 end if;
 insert into public.trip_status_history(trip_id,state,reason,actor_id) values(p_trip,p_action,p_reason,auth.uid());perform private.audit('trip.'||p_action,'trip',p_trip::text,coalesce(nullif(p_reason,''),'Trip state changed'));
end $$;
create function public.trip_finance(p_trip uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare t public.trips;result jsonb;
begin
 select * into t from public.trips where id=p_trip;perform private.require_permission('trips.finance.view',t.vehicle_id,t.created_by);
 select jsonb_build_object('fare',f.fare::text,'lines',(select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'category',l.category,'amount',l.amount::text,'business_date',l.business_date,'description',l.description)),'[]') from public.trip_expense_lines l where l.trip_id=p_trip)) into result from public.trip_financials f where trip_id=p_trip;return result;
end $$;
insert into public.role_permissions select id,'trips.finance.view','own' from public.roles where name='Data Entry';

do $$declare t text;begin foreach t in array array['accounting_periods','period_close_snapshots','trips','trip_financials','expense_categories','trip_expense_lines','trip_status_history','maintenance_categories','maintenance_records','maintenance_items','oil_changes','office_expenses','office_bookings','driver_earnings','revenue_entries','expense_entries','driver_loans','driver_loan_transactions','driver_payments','driver_payment_allocations','cash_transactions','settlement_allocations','idempotency_keys'] loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);end loop;end $$;
create policy periods_read on public.accounting_periods for select to authenticated using(private.active_session());
create policy closes_read on public.period_close_snapshots for select to authenticated using(private.can('reports.financial.view'));
create policy trips_read on public.trips for select to authenticated using(private.can('trips.view',vehicle_id,created_by));
create policy trip_finance_read on public.trip_financials for select to authenticated using(exists(select 1 from public.trips t where t.id=trip_id and private.can('trips.finance.view',t.vehicle_id,t.created_by)));
create policy categories_read on public.expense_categories for select to authenticated using(private.active_session());
create policy expense_lines_read on public.trip_expense_lines for select to authenticated using(exists(select 1 from public.trips t where t.id=trip_id and private.can('trips.finance.view',t.vehicle_id,t.created_by)));
create policy history_read on public.trip_status_history for select to authenticated using(exists(select 1 from public.trips t where t.id=trip_id and private.can('trips.view',t.vehicle_id,t.created_by)));
create policy maintenance_categories_read on public.maintenance_categories for select to authenticated using(private.active_session());
create policy maintenance_read on public.maintenance_records for select to authenticated using(private.can('maintenance.view',vehicle_id,created_by));
create policy maintenance_items_read on public.maintenance_items for select to authenticated using(exists(select 1 from public.maintenance_records m where m.id=maintenance_id and private.can('maintenance.view',m.vehicle_id,m.created_by)));
create policy oil_read on public.oil_changes for select to authenticated using(exists(select 1 from public.maintenance_records m where m.id=maintenance_id and private.can('maintenance.view',m.vehicle_id,m.created_by)));
create policy office_expenses_read on public.office_expenses for select to authenticated using(private.can('expenses.view',vehicle_id,created_by));
create policy bookings_read on public.office_bookings for select to authenticated using(private.can('bookings.view',null,created_by));
create policy earnings_read on public.driver_earnings for select to authenticated using(private.can_driver('payments.view',driver_id,created_by));
create policy revenue_read on public.revenue_entries for select to authenticated using(private.can('reports.financial.view',vehicle_id,created_by));
create policy expense_read on public.expense_entries for select to authenticated using(private.can('reports.financial.view',vehicle_id,created_by));
create policy loans_read on public.driver_loans for select to authenticated using(private.can_driver('loans.view',driver_id,created_by));
create policy loan_transactions_read on public.driver_loan_transactions for select to authenticated using(exists(select 1 from public.driver_loans l where l.id=loan_id and private.can_driver('loans.view',l.driver_id,l.created_by)));
create policy payments_read on public.driver_payments for select to authenticated using(private.can_driver('payments.view',driver_id,created_by));
create policy payment_allocations_read on public.driver_payment_allocations for select to authenticated using(exists(select 1 from public.driver_payments p where p.id=payment_id and private.can_driver('payments.view',p.driver_id,p.created_by)));
create policy cash_read on public.cash_transactions for select to authenticated using(private.can('reports.financial.view'));
create policy settlements_read on public.settlement_allocations for select to authenticated using(private.can('reports.financial.view'));
-- No idempotency SELECT policy: client requests cannot inspect other users' keys.
revoke all on function private.open_period(date),private.claim_action(uuid,text,uuid,text) from public,anon,authenticated;
revoke all on function public.create_period(text,date,date),public.save_trip(uuid,integer,jsonb,jsonb),public.trip_action(uuid,text,integer,text,uuid),public.trip_finance(uuid) from public,anon,authenticated;
grant execute on function public.create_period(text,date,date),public.save_trip(uuid,integer,jsonb,jsonb),public.trip_action(uuid,text,integer,text,uuid),public.trip_finance(uuid) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261005161449','accounts',array[]::text[]);

-- Migration: 20261005161907_finance_actions.sql
create function public.save_maintenance(p_id uuid,p_version integer,p_data jsonb,p_items jsonb,p_oil jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare m public.maintenance_records;mid uuid;vid uuid;item jsonb;review boolean=false;
begin
 perform pg_advisory_xact_lock(87413003);vid=(p_data->>'vehicle_id')::uuid;
 perform private.require_permission('maintenance.create',vid,auth.uid());
 perform private.open_period((p_data->>'business_date')::date);
 if not private.can('vehicles.view',vid,(select created_by from public.vehicles where id=vid)) then raise exception 'Vehicle out of scope' using errcode='42501';end if;
 if nullif(p_data->>'trip_id','') is not null and not exists(select 1 from public.trips where id=(p_data->>'trip_id')::uuid and vehicle_id=vid and private.can('trips.view',vehicle_id,created_by)) then raise exception 'Invalid linked trip';end if;
 if p_oil is not null then
  review=coalesce(nullif(p_oil->>'previous_odometer','')::numeric>(p_data->>'odometer')::numeric,false) or coalesce(nullif(p_oil->>'previous_date','')::date>(p_data->>'business_date')::date,false);
 end if;
 if p_id is null then
  insert into public.maintenance_records(vehicle_id,driver_id,trip_id,business_date,odometer,category,description,supplier,next_service_date,next_service_odometer,remarks,state,created_by) values(vid,nullif(p_data->>'driver_id','')::uuid,nullif(p_data->>'trip_id','')::uuid,(p_data->>'business_date')::date,(p_data->>'odometer')::numeric,p_data->>'category',p_data->>'description',p_data->>'supplier',nullif(p_data->>'next_service_date','')::date,nullif(p_data->>'next_service_odometer','')::numeric,p_data->>'remarks',case when review then 'Review' else 'Draft' end,auth.uid()) returning id into mid;
 else
  select * into m from public.maintenance_records where id=p_id for update;
  perform private.require_permission('maintenance.create',m.vehicle_id,m.created_by);perform private.open_period(m.business_date);
  if m.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
  if m.state not in ('Draft','Review') then raise exception 'Approved maintenance cannot be edited';end if;
  update public.maintenance_records set vehicle_id=vid,driver_id=nullif(p_data->>'driver_id','')::uuid,trip_id=nullif(p_data->>'trip_id','')::uuid,business_date=(p_data->>'business_date')::date,odometer=(p_data->>'odometer')::numeric,category=p_data->>'category',description=p_data->>'description',supplier=p_data->>'supplier',next_service_date=nullif(p_data->>'next_service_date','')::date,next_service_odometer=nullif(p_data->>'next_service_odometer','')::numeric,remarks=p_data->>'remarks',state=case when review then 'Review' else 'Draft' end,version=version+1 where id=p_id;mid=p_id;
  delete from public.maintenance_items where maintenance_id=mid;delete from public.oil_changes where maintenance_id=mid;
 end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>100 then raise exception 'Invalid maintenance items';end if;
 for item in select value from jsonb_array_elements(p_items) loop
  insert into public.maintenance_items(maintenance_id,kind,description,amount,part_identifier,tyre_position,warranty_until) values(mid,item->>'kind',item->>'description',(item->>'amount')::numeric,item->>'part_identifier',item->>'tyre_position',nullif(item->>'warranty_until','')::date);
 end loop;
 if p_oil is not null then
  if p_data->>'category'<>'oil_change' then raise exception 'Use the Oil Change category for oil data';end if;
  insert into public.oil_changes(maintenance_id,specification,quantity_litres,previous_date,previous_odometer,next_due_odometer) values(mid,p_oil->>'specification',(p_oil->>'quantity_litres')::numeric,nullif(p_oil->>'previous_date','')::date,nullif(p_oil->>'previous_odometer','')::numeric,nullif(p_oil->>'next_due_odometer','')::numeric);
 elsif p_data->>'category'='oil_change' then raise exception 'Oil specification and quantity are required';end if;
 perform private.audit('maintenance.save','maintenance',mid::text,case when review then 'Inconsistent history requires review' else 'Maintenance draft saved' end);return mid;
end $$;
create function public.approve_maintenance(p_id uuid,p_version integer,p_key uuid) returns void language plpgsql security definer set search_path='' as $$
declare m public.maintenance_records;
begin
 perform pg_advisory_xact_lock(87413003);select * into m from public.maintenance_records where id=p_id for update;perform private.require_permission('maintenance.approve',m.vehicle_id,m.created_by);
 if not private.claim_action(p_key,'maintenance.approve',p_id,p_version::text) then return;end if;
 if m.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
 if m.state<>'Draft' then raise exception 'Only a reviewed draft can be approved';end if;
 perform private.open_period(m.business_date);
 if m.trip_id is not null and exists(select 1 from public.trips where id=m.trip_id and financial_state='Voided') then raise exception 'Linked trip was voided';end if;
 insert into public.expense_entries(business_date,amount,category,vehicle_id,driver_id,trip_id,maintenance_item_id,created_by) select m.business_date,amount,m.category,m.vehicle_id,m.driver_id,m.trip_id,id,auth.uid() from public.maintenance_items where maintenance_id=p_id;
 update public.maintenance_records set state='Approved',version=version+1 where id=p_id;update public.vehicles set current_odometer=greatest(current_odometer,m.odometer) where id=m.vehicle_id;
 perform private.audit('maintenance.approve','maintenance',p_id::text,'Each invoice item posted once');
end $$;
create function public.save_office_expense(p_id uuid,p_version integer,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare e public.office_expenses;eid uuid;vid uuid;
begin
 perform pg_advisory_xact_lock(87413003);vid=nullif(p_data->>'vehicle_id','')::uuid;perform private.require_permission('expenses.create',vid,auth.uid());perform private.open_period((p_data->>'business_date')::date);
 if p_id is null then
  insert into public.office_expenses(business_date,category,description,amount,vehicle_id,driver_id,payment_method,remarks,created_by) values((p_data->>'business_date')::date,p_data->>'category',p_data->>'description',(p_data->>'amount')::numeric,vid,nullif(p_data->>'driver_id','')::uuid,p_data->>'payment_method',p_data->>'remarks',auth.uid()) returning id into eid;
 else
  select * into e from public.office_expenses where id=p_id for update;perform private.require_permission('expenses.create',e.vehicle_id,e.created_by);perform private.open_period(e.business_date);
  if e.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
  if e.state<>'Draft' then raise exception 'Only drafts can be edited';end if;
  update public.office_expenses set business_date=(p_data->>'business_date')::date,category=p_data->>'category',description=p_data->>'description',amount=(p_data->>'amount')::numeric,vehicle_id=vid,driver_id=nullif(p_data->>'driver_id','')::uuid,payment_method=p_data->>'payment_method',remarks=p_data->>'remarks',version=version+1 where id=p_id;eid=p_id;
 end if;perform private.audit('expense.save','expense',eid::text,'Office expense saved');return eid;
end $$;
create function public.expense_action(p_id uuid,p_action text,p_version integer,p_reason text,p_key uuid) returns void language plpgsql security definer set search_path='' as $$
declare e public.office_expenses;
begin
 perform pg_advisory_xact_lock(87413003);select * into e from public.office_expenses where id=p_id for update;
 if p_action not in ('approve','void') then raise exception 'Invalid action';end if;perform private.require_permission('expenses.'||p_action,e.vehicle_id,e.created_by);
 if not private.claim_action(p_key,'expense.'||p_action,p_id,p_version::text||coalesce(p_reason,'')) then return;end if;
 if e.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;perform private.open_period(e.business_date);
 if p_action='approve' then
  if e.state<>'Draft' then raise exception 'Only drafts can be approved';end if;
  insert into public.expense_entries(business_date,amount,category,vehicle_id,driver_id,office_expense_id,created_by) values(e.business_date,e.amount,e.category,e.vehicle_id,e.driver_id,p_id,auth.uid());
  update public.office_expenses set state='Approved',version=version+1 where id=p_id;
 else
  if e.state<>'Approved' or length(trim(p_reason))<3 then raise exception 'A posted expense and a reason are required';end if;
  if exists(select 1 from public.settlement_allocations where expense_entry_id in(select id from public.expense_entries where office_expense_id=p_id)) then raise exception 'Expense is settled; reviewed adjustment required';end if;
  insert into public.expense_entries(business_date,amount,category,vehicle_id,driver_id,office_expense_id,reversal_of,created_by) select business_date,-amount,category,vehicle_id,driver_id,office_expense_id,id,auth.uid() from public.expense_entries where office_expense_id=p_id and reversal_of is null;
  update public.office_expenses set state='Voided',version=version+1 where id=p_id;
 end if;perform private.audit('expense.'||p_action,'expense',p_id::text,coalesce(nullif(p_reason,''),'Office expense approved'));
end $$;
create function public.save_booking(p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare bid uuid;tid uuid;
begin
 perform pg_advisory_xact_lock(87413003);perform private.require_permission('bookings.create',null,auth.uid());perform private.open_period((p_data->>'business_date')::date);tid=nullif(p_data->>'trip_id','')::uuid;
 if tid is not null and not exists(select 1 from public.trips where id=tid and private.can('trips.view',vehicle_id,created_by)) then raise exception 'Linked trip out of scope' using errcode='42501';end if;
 insert into public.office_bookings(business_date,trip_id,external_vehicle,driver_contact,cargo,origin,destination,quoted_freight,commission,description,created_by) values((p_data->>'business_date')::date,tid,nullif(p_data->>'external_vehicle',''),p_data->>'driver_contact',p_data->>'cargo',p_data->>'origin',p_data->>'destination',(p_data->>'quoted_freight')::numeric,(p_data->>'commission')::numeric,p_data->>'description',auth.uid()) returning id into bid;
 perform private.audit('booking.create','booking',bid::text,'Booking draft created');return bid;
end $$;
create function public.approve_booking(p_id uuid,p_version integer,p_key uuid) returns void language plpgsql security definer set search_path='' as $$
declare b public.office_bookings;
begin
 perform pg_advisory_xact_lock(87413003);select * into b from public.office_bookings where id=p_id for update;perform private.require_permission('bookings.approve',null,b.created_by);
 if not private.claim_action(p_key,'booking.approve',p_id,p_version::text) then return;end if;
 if b.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
 if b.state<>'Draft' then raise exception 'Only a draft can be approved';end if;perform private.open_period(b.business_date);
 if b.trip_id is null then insert into public.revenue_entries(business_date,amount,kind,booking_id,created_by) values(b.business_date,b.commission,'Brokerage',b.id,auth.uid());end if;
 update public.office_bookings set state='Approved',version=version+1 where id=p_id;perform private.audit('booking.approve','booking',p_id::text,'External freight excluded; only brokerage commission recognized');
end $$;
create function public.loan_transaction(p_loan uuid,p_driver uuid,p_date date,p_kind text,p_amount numeric,p_reference text,p_due date,p_key uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare lid uuid;balance numeric;tx uuid;owner uuid;
begin
 perform pg_advisory_xact_lock(87413003);
 if p_kind not in ('Opening','Disbursement','Repayment') or p_amount<=0 then raise exception 'Invalid loan transaction';end if;
 if not private.can_driver(case when p_kind='Repayment' then 'loans.repay' else 'loans.issue' end,p_driver,(select created_by from public.drivers where id=p_driver)) then raise exception 'Permission denied' using errcode='42501';end if;
 perform private.open_period(p_date);
 if not private.claim_action(p_key,'loan.'||p_kind,coalesce(p_loan,p_driver),concat_ws('|',p_date,p_amount,p_reference,p_due)) then select id into lid from public.driver_loans where reference=p_reference;return coalesce(p_loan,lid);end if;
 if p_loan is null then
  if p_kind='Repayment' then raise exception 'Select an existing loan';end if;
  insert into public.driver_loans(driver_id,reference,due_date,created_by) values(p_driver,p_reference,p_due,auth.uid()) returning id into lid;
 else
  select id,created_by into lid,owner from public.driver_loans where id=p_loan and driver_id=p_driver for update;
  if lid is null then raise exception 'Loan does not belong to this driver';end if;
  if not private.can_driver(case when p_kind='Repayment' then 'loans.repay' else 'loans.issue' end,p_driver,owner) then raise exception 'Permission denied' using errcode='42501';end if;
  if p_kind='Opening' then raise exception 'Opening balance can only create a new loan';end if;
 end if;
 select coalesce(sum(case when kind='Repayment' then -amount else amount end),0) into balance from public.driver_loan_transactions where loan_id=lid;
 if p_kind='Repayment' and p_amount>balance then raise exception 'Repayment exceeds outstanding balance';end if;
 insert into public.driver_loan_transactions(loan_id,business_date,kind,amount,reference,created_by) values(lid,p_date,p_kind,p_amount,p_reference,auth.uid()) returning id into tx;
 if p_kind<>'Opening' then insert into public.cash_transactions(business_date,direction,amount,reference,loan_transaction_id,created_by) values(p_date,case when p_kind='Repayment' then 'Receipt' else 'Payment' end,p_amount,'LOAN:'||p_reference,tx,auth.uid());end if;
 perform private.audit('loan.'||lower(p_kind),'loan',lid::text,'Loan ledger updated; no operating-profit posting');return lid;
end $$;
create function public.accrue_earning(p_driver uuid,p_date date,p_kind text,p_amount numeric,p_rule text,p_key uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare eid uuid;
begin
 perform pg_advisory_xact_lock(87413003);
 if not private.can_driver('payments.approve',p_driver,(select created_by from public.drivers where id=p_driver)) then raise exception 'Permission denied' using errcode='42501';end if;perform private.open_period(p_date);
 if p_amount<=0 or p_kind not in ('Salary','Allowance','Reward') or length(trim(p_rule))<3 then raise exception 'Invalid earning or missing rule';end if;
 if not private.claim_action(p_key,'earning.accrue',p_driver,concat_ws('|',p_date,p_kind,p_amount,p_rule)) then return null;end if;
 insert into public.driver_earnings(driver_id,business_date,kind,amount,rule_snapshot,created_by) values(p_driver,p_date,p_kind,p_amount,p_rule,auth.uid()) returning id into eid;
 insert into public.expense_entries(business_date,amount,category,driver_id,earning_id,created_by) values(p_date,p_amount,lower(p_kind),p_driver,eid,auth.uid());perform private.audit('earning.accrue','earning',eid::text,'Driver earning accrued');return eid;
end $$;
create function public.settle_driver_payment(p_driver uuid,p_date date,p_reference text,p_allocations jsonb,p_key uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare total numeric=0;entry jsonb;earning public.driver_earnings;paid numeric;pid uuid;
begin
 perform pg_advisory_xact_lock(87413003);
 if not private.can_driver('payments.approve',p_driver,(select created_by from public.drivers where id=p_driver)) then raise exception 'Permission denied' using errcode='42501';end if;perform private.open_period(p_date);
 if not private.claim_action(p_key,'payment.settle',p_driver,concat_ws('|',p_date,p_reference,p_allocations)) then select id into pid from public.driver_payments where reference=p_reference;return pid;end if;
 if jsonb_typeof(p_allocations)<>'array' or jsonb_array_length(p_allocations) not between 1 and 100 then raise exception 'Select earnings to pay';end if;
 for entry in select value from jsonb_array_elements(p_allocations) loop
  select * into earning from public.driver_earnings where id=(entry->>'earning_id')::uuid and driver_id=p_driver for update;
  if earning.id is null or earning.state<>'Accrued' or not private.can_driver('payments.approve',p_driver,earning.created_by) or (entry->>'amount')::numeric<=0 then raise exception 'Invalid earning allocation';end if;
  select coalesce(sum(amount),0) into paid from public.driver_payment_allocations where earning_id=earning.id;
  if paid+(entry->>'amount')::numeric>earning.amount then raise exception 'Payment exceeds outstanding earning';end if;total=total+(entry->>'amount')::numeric;
 end loop;
 insert into public.driver_payments(driver_id,business_date,amount,reference,created_by) values(p_driver,p_date,total,p_reference,auth.uid()) returning id into pid;
 insert into public.driver_payment_allocations(payment_id,earning_id,amount) select pid,(value->>'earning_id')::uuid,(value->>'amount')::numeric from jsonb_array_elements(p_allocations);
 insert into public.cash_transactions(business_date,direction,amount,reference,driver_payment_id,created_by) values(p_date,'Payment',total,'PAY:'||p_reference,pid,auth.uid());
 perform private.audit('payment.settle','payment',pid::text,'Accrued earnings settled; no second expense');return pid;
end $$;
create function public.close_period(p_period uuid,p_version integer,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare p public.accounting_periods;summary jsonb;rev numeric;exp numeric;
begin
 perform private.require_permission('accounts.close');perform pg_advisory_xact_lock(87413003);select * into p from public.accounting_periods where id=p_period for update;
 if p.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
 if p.status='Closed' or length(trim(p_reason))<3 then raise exception 'Period must be open and a reason is required';end if;
 if exists(select 1 from public.trips where business_date between p.start_date and p.end_date and financial_state='Submitted') then raise exception 'Resolve submitted trips before closing';end if;
 select coalesce(sum(amount),0) into rev from public.revenue_entries where business_date between p.start_date and p.end_date;
 select coalesce(sum(amount),0) into exp from public.expense_entries where business_date between p.start_date and p.end_date;
 summary=jsonb_build_object('revenue',rev::text,'expenses',exp::text,'operating_profit',(rev-exp)::text,'from',p.start_date,'to',p.end_date);
 insert into public.period_close_snapshots(period_id,close_version,summary,closed_by) values(p.id,p.version+1,summary,auth.uid());
 update public.accounting_periods set status='Closed',version=version+1 where id=p.id;perform private.audit('period.close','period',p.id::text,p_reason);
end $$;
create function public.reopen_period(p_period uuid,p_version integer,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.require_permission('accounts.reopen');perform pg_advisory_xact_lock(87413003);
 if length(trim(p_reason))<3 then raise exception 'A reason is required';end if;
 update public.accounting_periods set status='Reopened',version=version+1 where id=p_period and version=p_version and status='Closed';
 if not found then raise exception 'Period changed or is already open' using errcode='40001';end if;perform private.audit('period.reopen','period',p_period::text,p_reason);
end $$;

revoke all on function public.save_maintenance(uuid,integer,jsonb,jsonb,jsonb),public.approve_maintenance(uuid,integer,uuid),public.save_office_expense(uuid,integer,jsonb),public.expense_action(uuid,text,integer,text,uuid),public.save_booking(jsonb),public.approve_booking(uuid,integer,uuid),public.loan_transaction(uuid,uuid,date,text,numeric,text,date,uuid),public.accrue_earning(uuid,date,text,numeric,text,uuid),public.settle_driver_payment(uuid,date,text,jsonb,uuid),public.close_period(uuid,integer,text),public.reopen_period(uuid,integer,text) from public,anon,authenticated;
grant execute on function public.save_maintenance(uuid,integer,jsonb,jsonb,jsonb),public.approve_maintenance(uuid,integer,uuid),public.save_office_expense(uuid,integer,jsonb),public.expense_action(uuid,text,integer,text,uuid),public.save_booking(jsonb),public.approve_booking(uuid,integer,uuid),public.loan_transaction(uuid,uuid,date,text,numeric,text,date,uuid),public.accrue_earning(uuid,date,text,numeric,text,uuid),public.settle_driver_payment(uuid,date,text,jsonb,uuid),public.close_period(uuid,integer,text),public.reopen_period(uuid,integer,text) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261005161907','finance_actions',array[]::text[]);

-- Migration: 20261005162715_reporting.sql
create function private.has_capability(p_permission text) returns boolean language sql stable security definer set search_path='' as $$
select private.active_session() and exists(select 1 from public.user_roles ur join public.role_permissions rp on rp.role_id=ur.role_id where ur.user_id=auth.uid() and rp.permission_code=p_permission)
$$;
revoke all on function private.has_capability(text) from public,anon,authenticated;
grant execute on function private.has_capability(text) to authenticated;

-- Whitelisted row listings, invoker RLS, exact numeric-to-text serialization before JSON.
create function public.list_records(p_resource text,p_search text default '',p_page integer default 1,p_limit integer default 25,p_from date default null,p_to date default null,p_vehicle uuid default null,p_driver uuid default null) returns jsonb language plpgsql stable security invoker set search_path='' as $$
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
 foreach col in array cols loop expr=expr||case when expr='' then '' else ',' end||format('%L,t.%I',col,col)||case when col in ('amount','quoted_freight','commission','opening_odometer','current_odometer','start_odometer','end_odometer','fuel_litres','weight','odometer','service_interval_km','fuel_target','next_service_odometer') then '::text' else '' end;end loop;
 predicate=format('t.%I::text ilike $1',search_col);
 if date_col is not null then predicate=predicate||format(' and ($2::date is null or t.%I >= $2) and ($3::date is null or t.%I <= $3)',date_col,date_col);end if;
 if 'vehicle_id'=any(cols) then predicate=predicate||' and ($4::uuid is null or t.vehicle_id=$4)';end if;
 if 'driver_id'=any(cols) then predicate=predicate||' and ($5::uuid is null or t.driver_id=$5)';end if;
 execute format('select count(*) from public.%I t where %s',tbl,predicate) into total using '%'||replace(replace(replace(p_search,'\','\\'),'%','\%'),'_','\_')||'%',p_from,p_to,p_vehicle,p_driver;
 q=format('select coalesce(jsonb_agg(row),''[]''::jsonb) from (select jsonb_build_object(%s) row from public.%I t where %s order by %s,t.id limit %s offset %s) listed',expr,tbl,predicate,case when date_col is not null then 't.'||quote_ident(date_col)||' desc' else 't.'||quote_ident(search_col) end,p_limit,(p_page-1)*p_limit);
 execute q into rows using '%'||replace(replace(replace(p_search,'\','\\'),'%','\%'),'_','\_')||'%',p_from,p_to,p_vehicle,p_driver;
 return jsonb_build_object('rows',rows,'count',total,'page',p_page);
end $$;

create function public.dashboard(p_from date,p_to date,p_basis text default 'measured',p_min_distance numeric default 100) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare today date=(now() at time zone 'Asia/Karachi')::date;result jsonb;fin jsonb;rev numeric;exp numeric;series jsonb;profitability jsonb;fuel jsonb;
begin
 if not private.active_session() then raise exception 'Sign in required' using errcode='42501';end if;
 if p_to<p_from or p_to-p_from>1096 or p_min_distance<0 or p_basis not in ('measured','tank_reconciled','purchase_estimate') then raise exception 'Invalid dashboard filters';end if;
 result=jsonb_build_object('today',today,'from',p_from,'to',p_to,'refreshed_at',now());
 if private.has_capability('vehicles.view') then result=result||jsonb_build_object('vehicles',(select count(*) from public.vehicles where status not in ('Sold','Archived')),'vehicle_status',(select coalesce(jsonb_object_agg(status,n),'{}') from(select status,count(*) n from public.vehicles group by status)s));end if;
 if private.has_capability('drivers.view') then result=result||jsonb_build_object('on_duty',(select count(distinct d.id) from public.drivers d join public.driver_duty_sessions s on s.driver_id=d.id where d.employment_status='Active' and s.ended_at is null));end if;
 if private.has_capability('trips.view') then
 result=result||jsonb_build_object('today_trips',(select count(*) from public.trips where business_date=today and financial_state not in ('Draft','Voided') and operational_state<>'Cancelled'),
 'trip_status',(select coalesce(jsonb_object_agg(operational_state,n),'{}') from(select operational_state,count(*) n from public.trips where business_date=today and financial_state not in ('Draft','Voided') and operational_state<>'Cancelled' group by operational_state)s),
 'trip_series',(select coalesce(jsonb_agg(jsonb_build_object('date',business_date,'trips',n) order by business_date),'[]') from(select business_date,count(*) n from public.trips where business_date between p_from and p_to and financial_state not in ('Draft','Voided') and operational_state<>'Cancelled' group by business_date)s));
 select coalesce(jsonb_agg(row order by efficiency desc),'[]') into fuel from (
  select jsonb_build_object('vehicle_id',t.vehicle_id,'registration',v.registration,'distance',sum(t.end_odometer-t.start_odometer)::text,'litres',sum(t.fuel_litres)::text,'efficiency',round(sum(t.end_odometer-t.start_odometer)/sum(t.fuel_litres),2)::text,'basis',p_basis,'eligible_trips',count(*)) row,sum(t.end_odometer-t.start_odometer)/sum(t.fuel_litres) efficiency
  from public.trips t join public.vehicles v on v.id=t.vehicle_id where t.business_date between p_from and p_to and t.operational_state='Completed' and t.financial_state<>'Voided' and t.end_odometer>=t.start_odometer and t.fuel_litres>0 and t.fuel_basis=p_basis group by t.vehicle_id,v.registration having sum(t.end_odometer-t.start_odometer)>=p_min_distance order by efficiency desc limit 10
 )ranked;result=result||jsonb_build_object('fuel_ranking',fuel);
 end if;
 if private.has_capability('reports.financial.view') then
  select coalesce(sum(amount),0) into rev from public.revenue_entries where business_date=today;
  select coalesce(sum(amount),0) into exp from public.expense_entries where business_date=today;
  select coalesce(jsonb_agg(jsonb_build_object('date',d,'revenue',r::text,'expenses',e::text,'profit',(r-e)::text) order by d),'[]') into series from(
   select d,coalesce((select sum(amount) from public.revenue_entries where business_date=d),0) r,coalesce((select sum(amount) from public.expense_entries where business_date=d),0) e from(select generate_series(p_from,p_to,'1 day'::interval)::date d) dates
  )s;
  select coalesce(jsonb_agg(row order by profit desc),'[]') into profitability from(
   select jsonb_build_object('vehicle_id',v.id,'registration',v.registration,'revenue',coalesce(r.amount,0)::text,'expenses',coalesce(e.amount,0)::text,'profit',(coalesce(r.amount,0)-coalesce(e.amount,0))::text,'trips',coalesce(t.n,0)) row,coalesce(r.amount,0)-coalesce(e.amount,0) profit from public.vehicles v
   left join(select vehicle_id,sum(amount) amount from public.revenue_entries where business_date between p_from and p_to group by vehicle_id) r on r.vehicle_id=v.id
   left join(select vehicle_id,sum(amount) amount from public.expense_entries where business_date between p_from and p_to group by vehicle_id) e on e.vehicle_id=v.id
   left join(select vehicle_id,count(*) n from public.trips where business_date between p_from and p_to and financial_state='Approved' group by vehicle_id)t on t.vehicle_id=v.id
   where r.vehicle_id is not null or e.vehicle_id is not null order by profit desc limit 10
  )ranked;
  fin=jsonb_build_object('revenue',rev::text,'expenses',exp::text,'operating_profit',(rev-exp)::text,'transport',(select coalesce(sum(amount),0)::text from public.revenue_entries where business_date=today and kind='Transport'),'brokerage',(select coalesce(sum(amount),0)::text from public.revenue_entries where business_date=today and kind='Brokerage'),
  'pending_trips',(select count(*) from public.trips where financial_state='Submitted'),'series',series,'vehicle_ranking',profitability,
  'unallocated_overhead',(select coalesce(sum(amount),0)::text from public.expense_entries where business_date between p_from and p_to and vehicle_id is null));
  result=result||jsonb_build_object('finance',fin);
 end if;return result;
end $$;
create function public.driver_statement(p_driver uuid) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 if not private.can_driver('payments.view',p_driver,(select created_by from public.drivers where id=p_driver)) and not private.can_driver('loans.view',p_driver,(select created_by from public.drivers where id=p_driver)) then raise exception 'Permission denied' using errcode='42501';end if;
 result=jsonb_build_object('driver_id',p_driver);
 if private.can_driver('payments.view',p_driver,(select created_by from public.drivers where id=p_driver)) then result=result||jsonb_build_object('earnings',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'date',e.business_date,'kind',e.kind,'amount',e.amount::text,'paid',coalesce(p.amount,0)::text,'remaining',(e.amount-coalesce(p.amount,0))::text,'rule',e.rule_snapshot)),'[]') from public.driver_earnings e left join(select earning_id,sum(amount) amount from public.driver_payment_allocations group by earning_id)p on p.earning_id=e.id where e.driver_id=p_driver and e.state='Accrued'),'payments',(select coalesce(sum(amount),0)::text from public.driver_payments where driver_id=p_driver));end if;
 if private.can_driver('loans.view',p_driver,(select created_by from public.drivers where id=p_driver)) then result=result||jsonb_build_object('loans',(select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'reference',l.reference,'due_date',l.due_date,'balance',coalesce(t.balance,0)::text)),'[]') from public.driver_loans l left join(select loan_id,sum(case when kind='Repayment' then -amount else amount end) balance from public.driver_loan_transactions group by loan_id)t on t.loan_id=l.id where l.driver_id=p_driver));end if;return result;
end $$;
revoke all on function public.list_records(text,text,integer,integer,date,date,uuid,uuid),public.dashboard(date,date,text,numeric),public.driver_statement(uuid) from public,anon,authenticated;
grant execute on function public.list_records(text,text,integer,integer,date,date,uuid,uuid),public.dashboard(date,date,text,numeric),public.driver_statement(uuid) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261005162715','reporting',array[]::text[]);

-- Migration: 20261005163133_documents.sql
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

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261005163133','documents',array[]::text[]);

-- Migration: 20261005164409_exports.sql
create function public.export_records(p_resource text,p_from date default null,p_to date default null,p_vehicle uuid default null,p_driver uuid default null) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb='[]';page_result jsonb;pages integer;page integer;
begin
 if not private.has_capability('reports.export') then raise exception 'Export denied' using errcode='42501';end if;
 page_result=public.list_records(p_resource,'',1,1000,p_from,p_to,p_vehicle,p_driver);
 if (page_result->>'count')::integer>50000 then raise exception 'More than 50,000 rows: narrow the report filters';end if;
 result=page_result->'rows';pages=ceil((page_result->>'count')::numeric/1000)::integer;
 if pages>1 then for page in 2..pages loop page_result=public.list_records(p_resource,'',page,1000,p_from,p_to,p_vehicle,p_driver);result=result||(page_result->'rows');end loop;end if;
 return result;
end $$;
create function public.monthly_accounts(p_from date,p_to date,p_basis text default 'measured') returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 if not private.has_capability('reports.financial.view') then raise exception 'Financial report denied' using errcode='42501';end if;
 if p_to<p_from or p_to-p_from>1096 then raise exception 'Invalid report period';end if;
 select coalesce(jsonb_agg(jsonb_build_object('registration',v.registration,'revenue',coalesce(r.amount,0)::text,'diesel',coalesce(e.diesel,0)::text,'tolls',coalesce(e.tolls,0)::text,'fines_permits',coalesce(e.fines,0)::text,'maintenance',coalesce(e.maintenance,0)::text,'commission',coalesce(e.commission,0)::text,'other_expenses',coalesce(e.other,0)::text,'expenses',coalesce(e.total,0)::text,'operating_profit',(coalesce(r.amount,0)-coalesce(e.total,0))::text,'distance_km',coalesce(t.distance,0)::text,'fuel_litres',coalesce(t.litres,0)::text,'efficiency_km_l',round(t.distance/nullif(t.litres,0),2)::text,'basis',p_basis,'weight_tonnes',coalesce(t.weight,0)::text,'completed_cycles',coalesce(t.cycles,0)) order by v.registration),'[]') into result
 from public.vehicles v
 left join(select vehicle_id,sum(amount) amount from public.revenue_entries where business_date between p_from and p_to group by vehicle_id)r on r.vehicle_id=v.id
 left join(select vehicle_id,sum(amount) total,sum(amount) filter(where category='diesel') diesel,sum(amount) filter(where category='tolls') tolls,sum(amount) filter(where category='fines_permits') fines,sum(amount) filter(where maintenance_item_id is not null) maintenance,sum(amount) filter(where category='commission' and maintenance_item_id is null) commission,sum(amount) filter(where maintenance_item_id is null and category not in ('diesel','tolls','fines_permits','commission')) other from public.expense_entries where business_date between p_from and p_to group by vehicle_id)e on e.vehicle_id=v.id
 left join(select vehicle_id,count(*) cycles,sum(case when fuel_basis=p_basis and fuel_litres>0 and end_odometer>=start_odometer then end_odometer-start_odometer else 0 end) distance,sum(case when fuel_basis=p_basis and fuel_litres>0 and end_odometer>=start_odometer then fuel_litres else 0 end) litres,sum(case when weight_unit='kg' then weight/1000 else weight end) weight from public.trips where business_date between p_from and p_to and operational_state='Completed' and financial_state<>'Voided' group by vehicle_id)t on t.vehicle_id=v.id;
 return jsonb_build_object('rows',result,'unallocated_overhead',(select coalesce(sum(amount),0)::text from public.expense_entries where business_date between p_from and p_to and vehicle_id is null),'from',p_from,'to',p_to,'basis',p_basis);
end $$;
revoke all on function public.export_records(text,date,date,uuid,uuid),public.monthly_accounts(date,date,text) from public,anon,authenticated;
grant execute on function public.export_records(text,date,date,uuid,uuid),public.monthly_accounts(date,date,text) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261005164409','exports',array[]::text[]);

-- Migration: 20261006083000_alerts_imports.sql
create table public.alert_rules(code text primary key,threshold numeric not null check(threshold>=0),enabled boolean not null default true,version integer not null default 1);
insert into public.alert_rules(code,threshold) values('expiry_days',30),('low_efficiency',3);
create table public.notifications(id uuid primary key default gen_random_uuid(),dedup_key text not null unique,type text not null,message text not null,vehicle_id uuid references public.vehicles(id),driver_id uuid references public.drivers(id),trip_id uuid references public.trips(id),action_link text not null,created_at timestamptz not null default now(),resolved_at timestamptz,check(num_nonnulls(vehicle_id,driver_id,trip_id)=1));
create table public.notification_reads(notification_id uuid references public.notifications(id),user_id uuid references public.app_users(id),read_at timestamptz not null default now(),primary key(notification_id,user_id));
create table public.job_runs(job_name text primary key,last_completed_at timestamptz,run_count bigint not null default 0);
create function private.can_notification(p_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$declare n public.notifications;begin
 select * into n from public.notifications where id=p_id;
 if n.vehicle_id is not null then return exists(select 1 from public.vehicles v where v.id=n.vehicle_id and private.can('vehicles.view',v.id,v.created_by));end if;
 if n.driver_id is not null then return exists(select 1 from public.drivers d where d.id=n.driver_id and private.can_driver('drivers.view',d.id,d.created_by));end if;
 return exists(select 1 from public.trips t where t.id=n.trip_id and private.can('trips.view',t.vehicle_id,t.created_by));end$$;
create function private.reconcile_alerts() returns void language plpgsql security definer set search_path='' as $$declare today date=(now() at time zone 'Asia/Karachi')::date;begin
 perform pg_advisory_xact_lock(87413004);update public.notifications set resolved_at=now() where resolved_at is null;
 insert into public.notifications(dedup_key,type,message,vehicle_id,action_link) select 'vehicle-expiry:'||id,'Document expiry','Vehicle documents are due for review.',id,'/vehicles' from public.vehicles where status not in ('Sold','Archived') and document_expiry<=today+(select threshold::integer from public.alert_rules where code='expiry_days' and enabled) on conflict(dedup_key) do update set resolved_at=null;
 insert into public.notifications(dedup_key,type,message,driver_id,action_link) select 'driver-expiry:'||id,'Licence expiry','Driver licence is due for review.',id,'/drivers' from public.drivers where employment_status='Active' and licence_expiry<=today+(select threshold::integer from public.alert_rules where code='expiry_days' and enabled) on conflict(dedup_key) do update set resolved_at=null;
 insert into public.notifications(dedup_key,type,message,trip_id,action_link) select 'trip-approval:'||id,'Approval pending','A submitted trip is awaiting review.',id,'/trips' from public.trips where financial_state='Submitted' on conflict(dedup_key) do update set resolved_at=null;
 insert into public.notifications(dedup_key,type,message,trip_id,action_link) select 'fuel-review:'||id,'Fuel review','Recorded measured efficiency is below the configured threshold.',id,'/trips' from public.trips where operational_state='Completed' and financial_state<>'Voided' and fuel_basis='measured' and fuel_litres>0 and (end_odometer-start_odometer)/fuel_litres<(select threshold from public.alert_rules where code='low_efficiency' and enabled) on conflict(dedup_key) do update set resolved_at=null;
 insert into public.job_runs(job_name,last_completed_at,run_count) values('gbt-alert-reconciliation',now(),1) on conflict(job_name) do update set last_completed_at=now(),run_count=public.job_runs.run_count+1;
 delete from private.request_limits where expires_at<now()-interval '1 day';
end$$;
create function public.reconcile_alerts() returns void language plpgsql security definer set search_path='' as $$begin perform private.require_permission('settings.manage');perform private.reconcile_alerts();perform private.audit('alerts.reconcile','system','alerts','Manual reconciliation');end$$;
create function public.server_reconcile_alerts() returns void language sql security definer set search_path='' as $$select private.reconcile_alerts()$$;
create function public.refresh_alerts_after_change() returns void language plpgsql security definer set search_path='' as $$begin if not private.active_session() then raise exception 'Sign in required' using errcode='42501';end if;perform private.reconcile_alerts();end$$;
create function public.mark_notification_read(p_id uuid) returns void language plpgsql security definer set search_path='' as $$begin if not private.can_notification(p_id) then raise exception 'Permission denied' using errcode='42501';end if;insert into public.notification_reads(notification_id,user_id) values(p_id,auth.uid()) on conflict do nothing;end$$;
create function public.save_alert_rule(p_code text,p_enabled boolean,p_threshold numeric,p_version integer) returns void language plpgsql security definer set search_path='' as $$begin perform private.require_permission('settings.manage');update public.alert_rules set enabled=p_enabled,threshold=p_threshold,version=version+1 where code=p_code and version=p_version;if not found then raise exception 'Record changed; reload' using errcode='40001';end if;perform private.reconcile_alerts();perform private.audit('alerts.rule','alert_rule',p_code,'Threshold updated');end$$;
create table public.import_batches(id uuid primary key default gen_random_uuid(),resource text not null check(resource in ('vehicles','drivers')),original_reference text not null check(length(original_reference) between 3 and 200),state text not null default 'Reviewed' check(state in ('Reviewed','Committed')),created_by uuid not null references public.app_users(id),created_at timestamptz not null default now(),committed_at timestamptz);
create table public.import_rows(batch_id uuid references public.import_batches(id),row_number integer not null,data jsonb not null,record_id uuid,primary key(batch_id,row_number));
create function public.prepare_import(p_resource text,p_reference text,p_rows jsonb) returns uuid language plpgsql security definer set search_path='' as $$declare bid uuid;item jsonb;i integer=1;begin
 perform private.require_permission('imports.manage');if p_resource not in ('vehicles','drivers') or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows) not between 1 and 200 then raise exception 'Import requires 1 to 200 rows';end if;perform private.require_permission(p_resource||'.create',null,auth.uid());insert into public.import_batches(resource,original_reference,created_by) values(p_resource,p_reference,auth.uid()) returning id into bid;
 for item in select value from jsonb_array_elements(p_rows) loop i=i+1;insert into public.import_rows values(bid,i,item,null);end loop;perform private.audit('import.review','import',bid::text,'Operational CSV staged for explicit commit');return bid;end$$;
create function public.commit_import(p_batch uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare b public.import_batches;r public.import_rows;rid uuid;ids jsonb='[]';begin
 perform private.require_permission('imports.manage');perform pg_advisory_xact_lock(87413005);select * into b from public.import_batches where id=p_batch for update;if b.id is null or b.created_by<>auth.uid() then raise exception 'Permission denied' using errcode='42501';end if;perform private.require_permission(b.resource||'.create',null,auth.uid());if b.state='Committed' then return (select jsonb_agg(record_id order by row_number) from public.import_rows where batch_id=p_batch);end if;
 for r in select * from public.import_rows where batch_id=p_batch order by row_number loop
 if b.resource='vehicles' then
  if exists(select 1 from public.vehicles where upper(regexp_replace(registration,'\s','','g'))=upper(regexp_replace(r.data->>'registration','\s','','g'))) then raise exception 'Row %: duplicate registration',r.row_number;end if;rid=public.save_vehicle(null,null,r.data);
 else
  if exists(select 1 from public.drivers where lower(trim(full_name))=lower(trim(r.data->>'full_name')) and regexp_replace(mobile,'[^0-9]','','g')=regexp_replace(r.data->>'mobile','[^0-9]','','g')) then raise exception 'Row %: duplicate driver',r.row_number;end if;rid=public.save_driver(null,null,r.data);
 end if;update public.import_rows set record_id=rid where batch_id=p_batch and row_number=r.row_number;ids=ids||to_jsonb(rid);end loop;
 update public.import_batches set state='Committed',committed_at=now() where id=p_batch;perform private.audit('import.commit','import',p_batch::text,'Reviewed operational import committed atomically');return ids;end$$;
do $$declare t text;begin foreach t in array array['alert_rules','notifications','notification_reads','job_runs','import_batches','import_rows'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);end loop;end$$;
create policy alerts_read on public.notifications for select to authenticated using(private.can_notification(id));
create policy reads_read on public.notification_reads for select to authenticated using(user_id=auth.uid() and private.can_notification(notification_id));
create policy rules_read on public.alert_rules for select to authenticated using(private.can('settings.manage'));
create policy jobs_read on public.job_runs for select to authenticated using(private.can('settings.manage'));
create policy imports_read on public.import_batches for select to authenticated using(created_by=auth.uid() and private.can('imports.manage'));
create policy rows_read on public.import_rows for select to authenticated using(exists(select 1 from public.import_batches b where b.id=batch_id and b.created_by=auth.uid() and private.can('imports.manage')));
revoke all on function private.can_notification(uuid),private.reconcile_alerts(),public.reconcile_alerts(),public.server_reconcile_alerts(),public.refresh_alerts_after_change(),public.mark_notification_read(uuid),public.save_alert_rule(text,boolean,numeric,integer),public.prepare_import(text,text,jsonb),public.commit_import(uuid) from public,anon,authenticated;
grant execute on function private.can_notification(uuid),public.reconcile_alerts(),public.refresh_alerts_after_change(),public.mark_notification_read(uuid),public.save_alert_rule(text,boolean,numeric,integer),public.prepare_import(text,text,jsonb),public.commit_import(uuid) to authenticated;
grant execute on function public.server_reconcile_alerts() to service_role;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261006083000','alerts_imports',array[]::text[]);

-- Migration: 20261006135132_exact_forms.sql
-- Additive form correction. Historical fields, IDs and source postings remain intact.
alter table public.vehicles add column purchase_year integer check(purchase_year between 1900 and 2200), add column major_maintenance_work text;
update public.vehicles set purchase_year=extract(year from purchase_date)::integer where purchase_date is not null;
alter table public.vehicles alter column manufacturer drop not null, alter column model drop not null;
alter table public.trips alter column origin drop not null, alter column destination drop not null;
alter table public.maintenance_records alter column business_date drop not null, alter column odometer drop not null, alter column category drop not null, alter column description drop not null;
create table public.maintenance_components(maintenance_id uuid references public.maintenance_records(id),category text references public.maintenance_categories(code),work_detail text not null check(length(work_detail)<=1000),primary key(maintenance_id,category));
alter table public.maintenance_components enable row level security;
revoke all on public.maintenance_components from public,anon,authenticated;
grant select on public.maintenance_components to authenticated;
create policy component_read on public.maintenance_components for select to authenticated using(exists(select 1 from public.maintenance_records m where m.id=maintenance_id and private.can('maintenance.view',m.vehicle_id,m.created_by)));
insert into public.maintenance_components select id,category,left(description,1000) from public.maintenance_records where category is not null and category<>'oil_change' and description is not null;

create function public.save_form(p_resource text,p_id uuid,p_version integer,p_data jsonb,p_identity_version integer default null,p_assignment uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare v public.vehicles;d public.drivers;t public.trips;m public.maintenance_records;result uuid;merged jsonb;allowed text[];k text;cat text;old_assignment public.vehicle_driver_assignments;target uuid;desired numeric;existing numeric;delta numeric;l public.trip_expense_lines;ident jsonb;
begin
 if not private.active_session() then raise exception 'Sign in required' using errcode='42501';end if;
 case p_resource
 when 'vehicles' then allowed=array['registration','manufacturer','purchase_year','purchase_price','major_maintenance_work','remarks'];
 when 'drivers' then allowed=array['vehicle_id','full_name','father_name','cnic','licence_number','mobile','emergency_contact','joining_date','leaving_date','address'];
 when 'trips' then allowed=array['business_date','vehicle_id','driver_id','cycle_number','fare','diesel','tolls','fines_permits','food','reward','service','parking','engine_oil','other','commission','start_odometer','end_odometer','fuel_litres','weight','remarks'];
 when 'maintenance' then allowed=array['vehicle_id','driver_id','engine','gearbox','parts','tyres','wiring','starter','alternator','lighting','cabin','body'];
 else raise exception 'Unknown form';end case;
 if jsonb_typeof(p_data)<>'object' or exists(select 1 from jsonb_object_keys(p_data) key where not key=any(allowed)) then raise exception 'Unexpected form field';end if;
 if exists(select 1 from jsonb_each_text(p_data) e where length(e.value)>1000) then raise exception 'Field too long';end if;
 if p_resource='vehicles' then
  if p_id is not null then select * into v from public.vehicles where id=p_id for update;if v.id is null then raise exception 'Vehicle unavailable';end if;merged=to_jsonb(v)||p_data;else merged=jsonb_build_object('status','Active','opening_odometer','0')||p_data;end if;
  if p_data?'purchase_price' then perform private.require_permission('reports.financial.view',p_id,coalesce(v.created_by,auth.uid()));end if;
  result=public.save_vehicle(p_id,p_version,merged);
  update public.vehicles set purchase_year=case when p_data?'purchase_year' then nullif(p_data->>'purchase_year','')::integer else purchase_year end,major_maintenance_work=case when p_data?'major_maintenance_work' then p_data->>'major_maintenance_work' else major_maintenance_work end where id=result;
 elsif p_resource='drivers' then
  -- Match the assignment action's lock order before acquiring the driver lock.
  perform pg_advisory_xact_lock(87413002);
  if p_id is not null then select * into d from public.drivers where id=p_id for update;if d.id is null then raise exception 'Driver unavailable';end if;merged=to_jsonb(d)||p_data;else merged=jsonb_build_object('employment_status','Active')||p_data;end if;
  result=public.save_driver(p_id,p_version,merged);
  if p_data ?| array['father_name','cnic','licence_number','address','emergency_contact'] then
   select to_jsonb(i) into ident from public.driver_identity_details i where driver_id=result;
   perform public.save_driver_identity(result,p_identity_version,coalesce(ident,'{}')||p_data);
  end if;
  if p_data?'vehicle_id' then
   select * into old_assignment from public.vehicle_driver_assignments where driver_id=result and ended_at is null;
   if old_assignment.id is distinct from p_assignment then raise exception 'Assignment changed; reload' using errcode='40001';end if;
   target=nullif(p_data->>'vehicle_id','')::uuid;
   if target is distinct from old_assignment.vehicle_id then
    if old_assignment.id is not null then perform public.assign_driver(old_assignment.vehicle_id,null,'Changed through Driver form');end if;
    if target is not null then
     if exists(select 1 from public.vehicle_driver_assignments where vehicle_id=target and ended_at is null) then raise exception 'Vehicle already has an active driver';end if;
     if not private.can('vehicles.view',target,(select created_by from public.vehicles where id=target)) then raise exception 'Vehicle out of scope' using errcode='42501';end if;
     perform public.assign_driver(target,result,'Changed through Driver form');
    end if;
   end if;
  end if;
 elsif p_resource='trips' then
  perform pg_advisory_xact_lock(87413003);
  if p_id is not null then select * into t from public.trips where id=p_id for update;if t.id is null then raise exception 'Trip unavailable';end if;merged=to_jsonb(t)||p_data;else merged=jsonb_build_object('operational_state','Planned','fuel_basis','purchase_estimate','weight_unit','metric tonnes')||p_data;end if;
  if p_data ?| array['fare','diesel','tolls','fines_permits','food','reward','service','parking','engine_oil','other','commission'] then perform private.require_permission('trips.finance.view',(merged->>'vehicle_id')::uuid,coalesce(t.created_by,auth.uid()));end if;
  if nullif(merged->>'end_odometer','')::numeric < nullif(merged->>'start_odometer','')::numeric then raise exception 'End odometer must not be below start odometer';end if;
  result=public.save_trip(p_id,p_version,merged,null);
  foreach cat in array array['diesel','tolls','fines_permits','food','reward','service','parking','engine_oil','other','commission'] loop
   if not p_data?cat then continue;end if;
   desired=nullif(p_data->>cat,'')::numeric;
   if desired is null then continue;end if;
   if desired<0 or desired<>round(desired,2) then raise exception 'Invalid expense amount';end if;
   select coalesce(sum(amount),0) into existing from public.trip_expense_lines where trip_id=result and category=cat;
   delta=desired-existing;
   -- Keep original IDs/descriptions/dates and attachment associations. Increase one
   -- existing line; reduce descending-ID lines first, retaining zero-amount lines.
   if delta>0 then
    select * into l from public.trip_expense_lines where trip_id=result and category=cat order by id desc limit 1;
    if l.id is null then insert into public.trip_expense_lines(trip_id,category,business_date,amount,description) values(result,cat,(merged->>'business_date')::date,delta,'');
    else perform private.open_period(l.business_date);update public.trip_expense_lines set amount=amount+delta where id=l.id;end if;
   elsif delta<0 then
    delta=-delta;
    for l in select * from public.trip_expense_lines where trip_id=result and category=cat order by id desc for update loop
     exit when delta=0;perform private.open_period(l.business_date);
     update public.trip_expense_lines set amount=greatest(0,amount-delta) where id=l.id;
     delta=greatest(0,delta-l.amount);
    end loop;
   end if;
  end loop;
 elsif p_resource='maintenance' then
  perform pg_advisory_xact_lock(87413003);
  target=(p_data->>'vehicle_id')::uuid;
  if p_id is not null then
   select * into m from public.maintenance_records where id=p_id for update;
   if m.id is null then raise exception 'Maintenance unavailable';end if;
   perform private.require_permission('maintenance.create',m.vehicle_id,m.created_by);
   if m.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
   if m.state not in ('Draft','Review') then raise exception 'Posted maintenance is immutable';end if;
   if m.business_date is not null then perform private.open_period(m.business_date);end if;
   if target<>m.vehicle_id then raise exception 'Existing maintenance vehicle is fixed';end if;
  else perform private.require_permission('maintenance.create',target,auth.uid());end if;
  if not private.can('vehicles.view',target,(select created_by from public.vehicles where id=target)) then raise exception 'Vehicle out of scope' using errcode='42501';end if;
  if nullif(p_data->>'driver_id','') is not null and not private.can_driver('drivers.view',(p_data->>'driver_id')::uuid,(select created_by from public.drivers where id=(p_data->>'driver_id')::uuid)) then raise exception 'Driver out of scope' using errcode='42501';end if;
  if p_id is null then insert into public.maintenance_records(vehicle_id,driver_id,state,created_by) values(target,nullif(p_data->>'driver_id','')::uuid,'Draft',auth.uid()) returning id into result;
  else result=p_id;update public.maintenance_records set driver_id=case when p_data?'driver_id' then nullif(p_data->>'driver_id','')::uuid else driver_id end,version=version+1 where id=result;end if;
  foreach k in array array['engine','gearbox','parts','tyres','wiring','starter','alternator','lighting','cabin','body'] loop
   if p_data?k then insert into public.maintenance_components values(result,k,coalesce(p_data->>k,'')) on conflict(maintenance_id,category) do update set work_detail=excluded.work_detail;end if;
  end loop;
 end if;
 perform private.audit('form.save',p_resource,result::text,'Exact form saved atomically; sensitive values omitted');return result;
end $$;

-- A separate explicit operation completes a trip; saving a form never invents completion.
create function public.complete_form_trip(p_id uuid,p_version integer) returns void language plpgsql security definer set search_path='' as $$
declare t public.trips;
begin perform pg_advisory_xact_lock(87413003);select * into t from public.trips where id=p_id for update;
 if not (private.can('trips.update',t.vehicle_id,t.created_by) or private.can('trips.update_own_draft',t.vehicle_id,t.created_by)) then raise exception 'Permission denied' using errcode='42501';end if;
 if t.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
 if t.financial_state not in ('Draft','Rejected') or t.operational_state='Cancelled' or t.end_odometer is null then raise exception 'Only an editable trip with an end km can be completed';end if;
 perform private.open_period(t.business_date);update public.trips set operational_state='Completed',version=version+1 where id=p_id;
 perform private.audit('trip.complete','trip',p_id::text,'Trip explicitly marked completed');end $$;

revoke all on function public.save_form(text,uuid,integer,jsonb,integer,uuid),public.complete_form_trip(uuid,integer) from public,anon,authenticated;
grant execute on function public.save_form(text,uuid,integer,jsonb,integer,uuid),public.complete_form_trip(uuid,integer) to authenticated;

create or replace function public.approve_maintenance(p_id uuid,p_version integer,p_key uuid) returns void language plpgsql security definer set search_path='' as $$
declare m public.maintenance_records;
begin
 perform pg_advisory_xact_lock(87413003);select * into m from public.maintenance_records where id=p_id for update;perform private.require_permission('maintenance.approve',m.vehicle_id,m.created_by);
 if not private.claim_action(p_key,'maintenance.approve',p_id,p_version::text) then return;end if;
 if m.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
 if m.business_date is null or m.odometer is null or m.category is null or not exists(select 1 from public.maintenance_items where maintenance_id=p_id) then raise exception 'Work details are unposted: verified date, odometer, category and invoice items are required';end if;
 if m.state<>'Draft' then raise exception 'Only a reviewed draft can be approved';end if;
 perform private.open_period(m.business_date);
 if m.trip_id is not null and exists(select 1 from public.trips where id=m.trip_id and financial_state='Voided') then raise exception 'Linked trip was voided';end if;
 insert into public.expense_entries(business_date,amount,category,vehicle_id,driver_id,trip_id,maintenance_item_id,created_by) select m.business_date,amount,m.category,m.vehicle_id,m.driver_id,m.trip_id,id,auth.uid() from public.maintenance_items where maintenance_id=p_id;
 update public.maintenance_records set state='Approved',version=version+1 where id=p_id;update public.vehicles set current_odometer=greatest(current_odometer,m.odometer) where id=m.vehicle_id;
 perform private.audit('maintenance.approve','maintenance',p_id::text,'Each invoice item posted once');
end $$;

create function public.form_record(p_resource text,p_id uuid,p_from date,p_to date) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare r jsonb;v public.vehicles;d public.drivers;t public.trips;m public.maintenance_records;stats jsonb;fin jsonb;ident jsonb;amount numeric;total numeric;basis text;distance numeric;litres numeric;first_km numeric;last_km numeric;
begin
 if not private.active_session() then raise exception 'Sign in required' using errcode='42501';end if;
 if p_from is null or p_to is null or p_to<p_from then raise exception 'Invalid dates';end if;
 if p_resource='vehicles' then
  select * into v from public.vehicles where id=p_id;if v.id is null then raise exception 'Vehicle unavailable' using errcode='42501';end if;
  r=to_jsonb(v)||jsonb_build_object('purchase_year',v.purchase_year::text,'opening_odometer',v.opening_odometer::text,'current_odometer',v.current_odometer::text);
  if private.can('reports.financial.view',v.id,v.created_by) then
   select jsonb_build_object('purchase_price',purchase_price::text) into fin from public.vehicle_financials where vehicle_id=v.id;r=r||coalesce(fin,'{}');
  end if;
 elsif p_resource='drivers' then
  select * into d from public.drivers where id=p_id;if d.id is null then raise exception 'Driver unavailable' using errcode='42501';end if;r=to_jsonb(d);
  select jsonb_build_object('vehicle_id',a.vehicle_id,'vehicle_id_label',assigned_vehicle.registration,'assignment_id',a.id) into stats from public.vehicle_driver_assignments a join public.vehicles assigned_vehicle on assigned_vehicle.id=a.vehicle_id where a.driver_id=d.id and a.ended_at is null;r=r||coalesce(stats,jsonb_build_object('vehicle_id',null,'assignment_id',null));
  if private.can_driver('drivers.identity.view',d.id,d.created_by) then select jsonb_build_object('father_name',i.father_name,'cnic',i.cnic,'licence_number',i.licence_number,'emergency_contact',i.emergency_contact,'address',i.address,'identity_version',i.version) into ident from public.driver_identity_details i where driver_id=d.id;r=r||coalesce(ident,'{}');end if;
  if private.can_driver('loans.view',d.id,d.created_by) then
   select jsonb_build_object('loan_taken',coalesce(sum(x.amount) filter(where x.kind in ('Opening','Disbursement')),0)::text,'loan_paid',coalesce(sum(x.amount) filter(where x.kind='Repayment'),0)::text,'loan_left',coalesce(sum(case when x.kind='Repayment' then -x.amount else x.amount end),0)::text,'loan_opening',coalesce(sum(x.amount) filter(where x.kind='Opening'),0)::text) into stats from public.driver_loan_transactions x join public.driver_loans l on l.id=x.loan_id where l.driver_id=d.id and x.business_date<=p_to;r=r||stats;
  end if;
 elsif p_resource='trips' then
  select * into t from public.trips where id=p_id;if t.id is null then raise exception 'Trip unavailable' using errcode='42501';end if;
  r=to_jsonb(t)||jsonb_build_object('start_odometer',t.start_odometer::text,'end_odometer',t.end_odometer::text,'fuel_litres',t.fuel_litres::text,'weight',t.weight::text,'total_km',(t.end_odometer-t.start_odometer)::text,'average',round((t.end_odometer-t.start_odometer)/nullif(t.fuel_litres,0),2)::text);
  if private.can('trips.finance.view',t.vehicle_id,t.created_by) then
   select fare into amount from public.trip_financials where trip_id=p_id;select coalesce(sum(l.amount),0) into total from public.trip_expense_lines l where trip_id=p_id;
   select jsonb_object_agg(c.code,coalesce(x.amount,0)::text) into fin from public.expense_categories c left join(select category,sum(l.amount) amount from public.trip_expense_lines l where trip_id=p_id group by category)x on x.category=c.code;
   r=r||coalesce(fin,'{}')||jsonb_build_object('fare',amount::text,'total_expense',total::text,'profit',(amount-total)::text);
  end if;
 elsif p_resource='maintenance' then
  select * into m from public.maintenance_records where id=p_id;if m.id is null then raise exception 'Maintenance unavailable' using errcode='42501';end if;
  r=to_jsonb(m)||jsonb_build_object('odometer',m.odometer::text);
  select jsonb_object_agg(category,work_detail) into stats from public.maintenance_components where maintenance_id=p_id;r=r||coalesce(stats,'{}');
 else raise exception 'Unknown form';end if;
 if p_resource in ('vehicles','drivers') then
  -- Do not mix fuel bases. All measures come from approved, completed trips.
  select case when count(distinct x.fuel_basis)=1 then min(x.fuel_basis) else null end,min(x.start_odometer),max(x.end_odometer),sum(x.end_odometer-x.start_odometer) filter(where x.fuel_litres>0),sum(x.fuel_litres) filter(where x.fuel_litres>0),jsonb_build_object('cycles',count(*),'weight',sum(case when x.weight_unit='kg' then x.weight/1000 else x.weight end)::text)
  into basis,first_km,last_km,distance,litres,stats from public.trips x where x.financial_state='Approved' and x.operational_state='Completed' and x.business_date between p_from and p_to and (case when p_resource='vehicles' then x.vehicle_id=p_id else x.driver_id=p_id end);
  r=r||stats||jsonb_build_object('start_km',first_km::text,'end_km',last_km::text,'total_km',case when p_resource='vehicles' then (last_km-first_km)::text else distance::text end,'litres',litres::text,'average',case when basis is not null and (p_resource='drivers' or distance=last_km-first_km) then round(distance/nullif(litres,0),2)::text end,'fuel_basis',coalesce(basis,'Unavailable or mixed bases'));
  if (p_resource='vehicles' and private.can('reports.financial.view',p_id,v.created_by)) or (p_resource='drivers' and private.can_driver('reports.financial.view',p_id,d.created_by)) then
   select jsonb_build_object('tolls',coalesce(sum(e.amount) filter(where category='tolls'),0)::text,'fines_permits',coalesce(sum(e.amount) filter(where category='fines_permits'),0)::text,'expenses',coalesce(sum(e.amount),0)::text) into stats from public.expense_entries e where business_date between p_from and p_to and (case when p_resource='vehicles' then vehicle_id=p_id else driver_id=p_id end);
   select coalesce(sum(e.amount),0) into amount from public.revenue_entries e where business_date between p_from and p_to and (case when p_resource='vehicles' then vehicle_id=p_id else driver_id=p_id end);r=r||stats||jsonb_build_object('income',amount::text,'profit',(amount-(stats->>'expenses')::numeric)::text);
  end if;
 end if;
 if p_resource in ('trips','maintenance') then r=r||jsonb_build_object('vehicle_id_label',(select registration from public.vehicles where id=(r->>'vehicle_id')::uuid),'driver_id_label',(select full_name from public.drivers where id=(r->>'driver_id')::uuid));end if;
 return r;
end $$;
create function public.form_register(p_resource text,p_from date,p_to date,p_page integer default 1,p_limit integer default 25,p_search text default '',p_vehicle uuid default null,p_driver uuid default null) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare tbl text;search_col text;predicate text;ids jsonb;item jsonb;rows jsonb='[]';total integer;pattern text;
begin
 if not private.active_session() then raise exception 'Sign in required' using errcode='42501';end if;
 if p_from is null or p_to is null or p_to<p_from or p_page<1 or p_limit not between 1 and 1000 or length(p_search)>100 then raise exception 'Invalid filters';end if;
 case p_resource when 'vehicles' then tbl='vehicles';search_col='registration';when 'drivers' then tbl='drivers';search_col='full_name';when 'trips' then tbl='trips';search_col='cycle_number';when 'maintenance' then tbl='maintenance_records';search_col='description';else raise exception 'Unknown form';end case;
 pattern='%'||replace(replace(replace(p_search,'\','\\'),'%','\%'),'_','\_')||'%';
 predicate=format('coalesce(t.%I::text,'''') ilike $1',search_col);
 if p_resource='trips' then predicate=predicate||' and t.business_date between $2 and $3';end if;
 if p_resource in ('trips','maintenance') then predicate=predicate||' and ($4::uuid is null or t.vehicle_id=$4) and ($5::uuid is null or t.driver_id=$5)';
 elsif p_resource='vehicles' then predicate=predicate||' and ($4::uuid is null or t.id=$4) and ($5::uuid is null or exists(select 1 from public.vehicle_driver_assignments a where a.vehicle_id=t.id and a.driver_id=$5 and a.ended_at is null))';
 else predicate=predicate||' and ($5::uuid is null or t.id=$5) and ($4::uuid is null or exists(select 1 from public.vehicle_driver_assignments a where a.driver_id=t.id and a.vehicle_id=$4 and a.ended_at is null))';end if;
 execute format('select count(*) from public.%I t where %s',tbl,predicate) into total using pattern,p_from,p_to,p_vehicle,p_driver;
 execute format('select coalesce(jsonb_agg(id),''[]'') from(select t.id from public.%I t where %s order by t.%I nulls last,t.id limit %s offset %s) q',tbl,predicate,search_col,p_limit,(p_page-1)*p_limit) into ids using pattern,p_from,p_to,p_vehicle,p_driver;
 for item in select value from jsonb_array_elements(ids) loop rows=rows||jsonb_build_array(public.form_record(p_resource,(item#>>'{}')::uuid,p_from,p_to));end loop;
 return jsonb_build_object('rows',rows,'count',total,'page',p_page,'from',p_from,'to',p_to);
end $$;
create function public.form_export(p_resource text,p_from date,p_to date,p_vehicle uuid default null,p_driver uuid default null) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare page jsonb;rows jsonb;pages integer;n integer;
begin
 if not private.has_capability('reports.export') then raise exception 'Export denied' using errcode='42501';end if;
 page=public.form_register(p_resource,p_from,p_to,1,1000,'',p_vehicle,p_driver);if (page->>'count')::integer>50000 then raise exception 'Narrow filters: more than 50,000 records';end if;rows=page->'rows';pages=ceil((page->>'count')::numeric/1000)::integer;
 if pages>1 then for n in 2..pages loop page=public.form_register(p_resource,p_from,p_to,n,1000,'',p_vehicle,p_driver);rows=rows||(page->'rows');end loop;end if;return rows;
end $$;
revoke all on function public.form_record(text,uuid,date,date),public.form_register(text,date,date,integer,integer,text,uuid,uuid),public.form_export(text,date,date,uuid,uuid) from public,anon,authenticated;
grant execute on function public.form_record(text,uuid,date,date),public.form_register(text,date,date,integer,integer,text,uuid,uuid),public.form_export(text,date,date,uuid,uuid) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261006135132','exact_forms',array[]::text[]);

-- Migration: 20261006140546_reference_reports.sql
-- Caller-context snapshot for reference reports; every source table remains under RLS.
create function public.reference_dataset(p_kind text,p_from date,p_to date,p_vehicle uuid default null,p_driver uuid default null) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare r jsonb;items jsonb;oil jsonb;metadata jsonb;needed text;
begin
 if not private.has_capability('reports.export') then raise exception 'Export denied' using errcode='42501';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>1096 then raise exception 'Invalid reporting period';end if;
 if p_kind not in ('office','oil','monthly','combined','driver-details') then raise exception 'Unknown reference report';end if;
 needed=case when p_kind='office' then 'bookings.view' when p_kind='oil' then 'maintenance.view' else 'reports.financial.view' end;
 if not private.has_capability(needed) then raise exception 'Report permission denied' using errcode='42501';end if;
 select jsonb_build_object('business_name',business_name,'contact_email',contact_email,'phone_1',phone_1,'phone_2',phone_2,'phone_3',phone_3,'currency',currency,'timezone',timezone,'from',p_from,'to',p_to,'period_label',coalesce((select name from public.accounting_periods where start_date=p_from and end_date=p_to),to_char(p_to,'MON-YYYY')),'generated_at',now()) into metadata from public.business_settings where id;
 r=jsonb_build_object('metadata',metadata);
 if p_kind='office' then
  r=r||jsonb_build_object('bookings',public.export_records('bookings',p_from,p_to,null,null),'office',public.export_records('office-expenses',p_from,p_to,null,null),'trips',public.form_export('trips',p_from,p_to,null,null));
 else
  r=r||jsonb_build_object('vehicles',public.form_export('vehicles',p_from,p_to,null,null),'drivers',public.form_export('drivers',p_from,p_to,null,null),'trips',public.form_export('trips',p_from,p_to,p_vehicle,p_driver));
  select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'vehicle_id',m.vehicle_id,'driver_id',m.driver_id,'business_date',m.business_date,'odometer',m.odometer::text,'category',m.category,'description',m.description,'state',m.state,'items',(select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'description',i.description,'amount',i.amount::text,'kind',i.kind)),'[]') from public.maintenance_items i where i.maintenance_id=m.id),'components',(select coalesce(jsonb_object_agg(c.category,c.work_detail),'{}') from public.maintenance_components c where c.maintenance_id=m.id)) order by m.business_date,m.id),'[]') into items from public.maintenance_records m where (m.business_date<=p_to or m.business_date is null) and (p_vehicle is null or m.vehicle_id=p_vehicle) and (p_driver is null or m.driver_id=p_driver);
  if jsonb_array_length(items)>50000 then raise exception 'Narrow filters: too many maintenance records';end if;r=r||jsonb_build_object('maintenance',items);
  select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',m.vehicle_id,'driver_id',m.driver_id,'date',m.business_date,'odometer',m.odometer::text,'previous_date',o.previous_date,'previous_odometer',o.previous_odometer::text) order by m.business_date,m.id),'[]') into oil from public.oil_changes o join public.maintenance_records m on m.id=o.maintenance_id where m.state='Approved' and m.business_date<=p_to and (p_vehicle is null or m.vehicle_id=p_vehicle);r=r||jsonb_build_object('oil',oil);
  -- Odometer observations are bounded by report cutoff, never current_odometer.
  select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',vehicle_id,'date',business_date,'odometer',end_odometer::text) order by business_date,id),'[]') into items from (select id,vehicle_id,business_date,end_odometer from public.trips where financial_state='Approved' and operational_state='Completed' and business_date<=p_to and end_odometer is not null and (p_vehicle is null or vehicle_id=p_vehicle) union all select id,vehicle_id,business_date,odometer from public.maintenance_records where state='Approved' and business_date<=p_to and odometer is not null and (p_vehicle is null or vehicle_id=p_vehicle)) observations;
  if jsonb_array_length(items)>50000 then raise exception 'Narrow filters: too many odometer readings';end if;r=r||jsonb_build_object('closing_readings',items);
  if p_kind<>'oil' then r=r||jsonb_build_object('monthly',public.monthly_accounts(p_from,p_to),'revenue',public.export_records('revenue',p_from,p_to,p_vehicle,p_driver),'expenses',public.export_records('expenses',p_from,p_to,p_vehicle,p_driver),'earnings',public.export_records('earnings',p_from,p_to,p_vehicle,p_driver),'payments',public.export_records('payments',p_from,p_to,p_vehicle,p_driver));end if;
 end if;
 return r;
end $$;
revoke all on function public.reference_dataset(text,date,date,uuid,uuid) from public,anon,authenticated;
grant execute on function public.reference_dataset(text,date,date,uuid,uuid) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261006140546','reference_reports',array[]::text[]);

-- Migration: 20261008195000_dashboard_form_fields.sql
-- Restore operational inputs used by dashboard graphs and printed reports.
-- No tables, records, IDs, permissions, or accounting rules are removed.
create or replace function public.save_form(p_resource text,p_id uuid,p_version integer,p_data jsonb,p_identity_version integer default null,p_assignment uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare v public.vehicles;d public.drivers;t public.trips;m public.maintenance_records;result uuid;merged jsonb;allowed text[];k text;cat text;old_assignment public.vehicle_driver_assignments;target uuid;desired numeric;existing numeric;delta numeric;l public.trip_expense_lines;ident jsonb;
begin
 if not private.active_session() then raise exception 'Sign in required' using errcode='42501';end if;
 case p_resource
 when 'vehicles' then allowed=array['registration','manufacturer','purchase_year','purchase_price','major_maintenance_work','remarks','model','status','opening_odometer','service_interval_km','document_expiry'];
 when 'drivers' then allowed=array['vehicle_id','full_name','father_name','cnic','licence_number','mobile','emergency_contact','joining_date','leaving_date','address','licence_expiry','employment_status'];
 when 'trips' then allowed=array['business_date','vehicle_id','driver_id','cycle_number','fare','diesel','tolls','fines_permits','food','reward','service','parking','engine_oil','other','commission','start_odometer','end_odometer','fuel_litres','weight','remarks','origin','destination','route_description','cargo','fuel_basis','weight_unit'];
 when 'maintenance' then allowed=array['vehicle_id','driver_id','engine','gearbox','parts','tyres','wiring','starter','alternator','lighting','cabin','body'];
 else raise exception 'Unknown form';end case;
 if jsonb_typeof(p_data)<>'object' or exists(select 1 from jsonb_object_keys(p_data) key where not key=any(allowed)) then raise exception 'Unexpected form field';end if;
 if exists(select 1 from jsonb_each_text(p_data) e where length(e.value)>1000) then raise exception 'Field too long';end if;
 if p_resource='vehicles' then
  if p_id is not null then select * into v from public.vehicles where id=p_id for update;if v.id is null then raise exception 'Vehicle unavailable';end if;merged=to_jsonb(v)||p_data;else merged=jsonb_build_object('status','Active','opening_odometer','0')||p_data;end if;
  if p_data?'purchase_price' then perform private.require_permission('reports.financial.view',p_id,coalesce(v.created_by,auth.uid()));end if;
  result=public.save_vehicle(p_id,p_version,merged);
  update public.vehicles set purchase_year=case when p_data?'purchase_year' then nullif(p_data->>'purchase_year','')::integer else purchase_year end,major_maintenance_work=case when p_data?'major_maintenance_work' then p_data->>'major_maintenance_work' else major_maintenance_work end where id=result;
 elsif p_resource='drivers' then
  -- Match the assignment action's lock order before acquiring the driver lock.
  perform pg_advisory_xact_lock(87413002);
  if p_id is not null then select * into d from public.drivers where id=p_id for update;if d.id is null then raise exception 'Driver unavailable';end if;merged=to_jsonb(d)||p_data;else merged=jsonb_build_object('employment_status','Active')||p_data;end if;
  result=public.save_driver(p_id,p_version,merged);
  if p_data ?| array['father_name','cnic','licence_number','address','emergency_contact'] then
   select to_jsonb(i) into ident from public.driver_identity_details i where driver_id=result;
   perform public.save_driver_identity(result,p_identity_version,coalesce(ident,'{}')||p_data);
  end if;
  if p_data?'vehicle_id' then
   select * into old_assignment from public.vehicle_driver_assignments where driver_id=result and ended_at is null;
   if old_assignment.id is distinct from p_assignment then raise exception 'Assignment changed; reload' using errcode='40001';end if;
   target=nullif(p_data->>'vehicle_id','')::uuid;
   if target is distinct from old_assignment.vehicle_id then
    if old_assignment.id is not null then perform public.assign_driver(old_assignment.vehicle_id,null,'Changed through Driver form');end if;
    if target is not null then
     if exists(select 1 from public.vehicle_driver_assignments where vehicle_id=target and ended_at is null) then raise exception 'Vehicle already has an active driver';end if;
     if not private.can('vehicles.view',target,(select created_by from public.vehicles where id=target)) then raise exception 'Vehicle out of scope' using errcode='42501';end if;
     perform public.assign_driver(target,result,'Changed through Driver form');
    end if;
   end if;
  end if;
 elsif p_resource='trips' then
  perform pg_advisory_xact_lock(87413003);
  if p_id is not null then select * into t from public.trips where id=p_id for update;if t.id is null then raise exception 'Trip unavailable';end if;merged=to_jsonb(t)||p_data;else merged=jsonb_build_object('operational_state','Planned','fuel_basis','purchase_estimate','weight_unit','metric tonnes')||p_data;end if;
  if p_data ?| array['fare','diesel','tolls','fines_permits','food','reward','service','parking','engine_oil','other','commission'] then perform private.require_permission('trips.finance.view',(merged->>'vehicle_id')::uuid,coalesce(t.created_by,auth.uid()));end if;
  if nullif(merged->>'end_odometer','')::numeric < nullif(merged->>'start_odometer','')::numeric then raise exception 'End odometer must not be below start odometer';end if;
  result=public.save_trip(p_id,p_version,merged,null);
  foreach cat in array array['diesel','tolls','fines_permits','food','reward','service','parking','engine_oil','other','commission'] loop
   if not p_data?cat then continue;end if;
   desired=nullif(p_data->>cat,'')::numeric;
   if desired is null then continue;end if;
   if desired<0 or desired<>round(desired,2) then raise exception 'Invalid expense amount';end if;
   select coalesce(sum(amount),0) into existing from public.trip_expense_lines where trip_id=result and category=cat;
   delta=desired-existing;
   -- Keep original IDs/descriptions/dates and attachment associations. Increase one
   -- existing line; reduce descending-ID lines first, retaining zero-amount lines.
   if delta>0 then
    select * into l from public.trip_expense_lines where trip_id=result and category=cat order by id desc limit 1;
    if l.id is null then insert into public.trip_expense_lines(trip_id,category,business_date,amount,description) values(result,cat,(merged->>'business_date')::date,delta,'');
    else perform private.open_period(l.business_date);update public.trip_expense_lines set amount=amount+delta where id=l.id;end if;
   elsif delta<0 then
    delta=-delta;
    for l in select * from public.trip_expense_lines where trip_id=result and category=cat order by id desc for update loop
     exit when delta=0;perform private.open_period(l.business_date);
     update public.trip_expense_lines set amount=greatest(0,amount-delta) where id=l.id;
     delta=greatest(0,delta-l.amount);
    end loop;
   end if;
  end loop;
 elsif p_resource='maintenance' then
  perform pg_advisory_xact_lock(87413003);
  target=(p_data->>'vehicle_id')::uuid;
  if p_id is not null then
   select * into m from public.maintenance_records where id=p_id for update;
   if m.id is null then raise exception 'Maintenance unavailable';end if;
   perform private.require_permission('maintenance.create',m.vehicle_id,m.created_by);
   if m.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
   if m.state not in ('Draft','Review') then raise exception 'Posted maintenance is immutable';end if;
   if m.business_date is not null then perform private.open_period(m.business_date);end if;
   if target<>m.vehicle_id then raise exception 'Existing maintenance vehicle is fixed';end if;
  else perform private.require_permission('maintenance.create',target,auth.uid());end if;
  if not private.can('vehicles.view',target,(select created_by from public.vehicles where id=target)) then raise exception 'Vehicle out of scope' using errcode='42501';end if;
  if nullif(p_data->>'driver_id','') is not null and not private.can_driver('drivers.view',(p_data->>'driver_id')::uuid,(select created_by from public.drivers where id=(p_data->>'driver_id')::uuid)) then raise exception 'Driver out of scope' using errcode='42501';end if;
  if p_id is null then insert into public.maintenance_records(vehicle_id,driver_id,state,created_by) values(target,nullif(p_data->>'driver_id','')::uuid,'Draft',auth.uid()) returning id into result;
  else result=p_id;update public.maintenance_records set driver_id=case when p_data?'driver_id' then nullif(p_data->>'driver_id','')::uuid else driver_id end,version=version+1 where id=result;end if;
  foreach k in array array['engine','gearbox','parts','tyres','wiring','starter','alternator','lighting','cabin','body'] loop
   if p_data?k then insert into public.maintenance_components values(result,k,coalesce(p_data->>k,'')) on conflict(maintenance_id,category) do update set work_detail=excluded.work_detail;end if;
  end loop;
 end if;
 perform private.audit('form.save',p_resource,result::text,'Exact form saved atomically; sensitive values omitted');return result;
end $$;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261008195000','dashboard_form_fields',array[]::text[]);

-- Migration: 20261010103000_custom_fields_cards_print.sql
-- Additive upgrade: retain master rows, company FKs, postings, IDs and private documents.
alter table public.vehicles add column if not exists address text check(length(address)<=1000);
alter table public.trips add column if not exists archived_at timestamptz;
alter table public.maintenance_records add column if not exists archived_at timestamptz;
alter table public.drivers add column if not exists photo_attachment_id uuid references public.attachments(id) on delete set null;
insert into public.permissions(code,description) values
 ('drivers.archive','Archive inactive driver records'),('trips.delete_draft','Remove unposted trip drafts'),('maintenance.delete_draft','Remove unposted maintenance drafts') on conflict do nothing;
insert into public.role_permissions(role_id,permission_code,scope)
select r.id,p.code,'all' from public.roles r cross join public.permissions p where r.reserved and p.code in ('drivers.archive','trips.delete_draft','maintenance.delete_draft') on conflict do nothing;

create table public.custom_field_definitions(
 id uuid primary key default gen_random_uuid(),resource text not null check(resource in ('vehicles','drivers','trips','maintenance')),
 key text not null check(key ~ '^cf_[a-z][a-z0-9_]{0,45}$'),label text not null check(length(trim(label)) between 1 and 80),
 type text not null check(type in ('text','number','date','currency','percentage','dropdown','checkbox','formula')),
 default_value jsonb,required boolean not null default false,display_order integer not null default 0 check(display_order between 0 and 999),
 show_form boolean not null default true,show_card boolean not null default true,show_table boolean not null default true,show_print boolean not null default true,
 hidden boolean not null default false,archived boolean not null default false,restricted boolean not null default false,
 options text[] not null default '{}',formula text not null default '' check(length(formula)<=500),ast jsonb,
 dependencies text[] not null default '{}',required_permissions text[] not null default '{}',version integer not null default 1,
 created_by uuid not null references public.app_users(id),created_at timestamptz not null default now(),unique(resource,key)
);
create table public.custom_field_values(
 resource text not null,record_id uuid not null,field_id uuid not null references public.custom_field_definitions(id),
 value jsonb,updated_at timestamptz not null default now(),primary key(resource,record_id,field_id)
);
create index custom_values_record on public.custom_field_values(resource,record_id);
create table public.print_template_settings(
 kind text primary key check(kind in ('vehicles','drivers','trips','maintenance','office','oil','monthly','combined','driver-details')),
 orientation text not null default 'landscape' check(orientation in ('portrait','landscape')),
 signatures text[] not null default '{}',version integer not null default 1
);
insert into public.print_template_settings(kind,orientation,signatures) values
 ('drivers','portrait',array['Driver signature','Admin / authorized officer']),
 ('vehicles','portrait',array['Handover signature','Receiving signature','Admin / authorized officer']),
 ('trips','portrait',array['Driver signature','Admin / authorized officer']),
 ('maintenance','portrait',array['Prepared by','Driver / receiving signature','Authorized officer']),
 ('oil','landscape',array['Driver signature','Authorized officer']),
 ('office','landscape',array['Prepared by','Authorized officer']),
 ('monthly','landscape',array['Manager signature','C.E.O. signature']),
 ('combined','landscape',array['Driver signature','Driver thumb impression','Paid by','Authorized signature']),
 ('driver-details','landscape',array['Driver signature','Authorized officer']);

create function private.record_permission(p_resource text,p_id uuid,p_permission text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare own uuid;veh uuid;
begin
 if p_resource='vehicles' then select created_by,id into own,veh from public.vehicles where id=p_id;
 elsif p_resource='drivers' then select created_by into own from public.drivers where id=p_id;return own is not null and private.can_driver(p_permission,p_id,own);
 elsif p_resource='trips' then select created_by,vehicle_id into own,veh from public.trips where id=p_id;
 elsif p_resource='maintenance' then select created_by,vehicle_id into own,veh from public.maintenance_records where id=p_id;
 else return false;end if;return own is not null and private.can(p_permission,veh,own);
end $$;
create function private.custom_numeric_keys(p_resource text) returns text[] language sql immutable set search_path='' as $$
select case p_resource
 when 'vehicles' then array['purchase_year','purchase_price','opening_odometer','current_odometer','service_interval_km','income','expenses','profit','tolls','fines_permits','start_km','end_km','total_km','matched_km','litres','average']
 when 'drivers' then array['income','expenses','profit','tolls','fines_permits','litres','total_km','matched_km','average','weight','cycles','loan_taken','loan_paid','loan_left']
 when 'trips' then array['fare','diesel','tolls','fines_permits','food','reward','service','parking','engine_oil','other','commission','total_expense','profit','start_odometer','end_odometer','total_km','fuel_litres','average','weight']
 else '{}'::text[] end $$;
create function private.ast_refs(p_ast jsonb,p_depth integer default 0) returns text[] language plpgsql immutable set search_path='' as $$
declare k text;refs text[]='{}';a jsonb;
begin
 if p_depth>32 or p_ast is null or jsonb_typeof(p_ast)<>'object' then raise exception 'Invalid or overly complex formula';end if;
 k=p_ast->>'kind';
 if k='field' then if coalesce(p_ast->>'key','')!~'^[a-z][a-z0-9_]{0,60}$' then raise exception 'Invalid field reference';end if;return array[p_ast->>'key'];
 elsif k='number' then if coalesce(p_ast->>'value','')!~'^(\d+(\.\d+)?|\.\d+)$' or abs((p_ast->>'value')::numeric)>1e15 then raise exception 'Invalid number';end if;
 elsif k='unary' and p_ast->>'op' in ('+','-') then refs=private.ast_refs(p_ast->'arg',p_depth+1);
 elsif k='binary' and p_ast->>'op' in ('+','-','*','/','%') then refs=private.ast_refs(p_ast->'left',p_depth+1)||private.ast_refs(p_ast->'right',p_depth+1);
 elsif k='call' and p_ast->>'name' in ('SUM','MIN','MAX','ABS','ROUND') and jsonb_typeof(p_ast->'args')='array' then
  if jsonb_array_length(p_ast->'args') not between 1 and 20 or (p_ast->>'name'='ABS' and jsonb_array_length(p_ast->'args')<>1) or (p_ast->>'name'='ROUND' and jsonb_array_length(p_ast->'args') not in (1,2)) then raise exception 'Invalid function arguments';end if;
  for a in select value from jsonb_array_elements(p_ast->'args') loop refs=refs||private.ast_refs(a,p_depth+1);end loop;
 else raise exception 'Unsupported formula operation';end if;
 return array(select distinct x from unnest(refs) x);
end $$;
create function private.eval_custom_ast(p_ast jsonb,p_values jsonb,p_depth integer default 0) returns numeric language plpgsql immutable set search_path='' as $$
declare a numeric;b numeric;v numeric;k text;x jsonb;n text;args numeric[]='{}';digits integer;
begin
 if p_depth>32 then raise exception 'Formula nesting is too deep';end if;k=p_ast->>'kind';
 if k='number' then v=(p_ast->>'value')::numeric;
 elsif k='field' then n=p_ast->>'key';if p_values->>n is null or p_values->>n='' then raise exception 'Enter a value for %',n;end if;v=(p_values->>n)::numeric;
 elsif k='unary' then v=private.eval_custom_ast(p_ast->'arg',p_values,p_depth+1);if p_ast->>'op'='-' then v=-v;end if;
 elsif k='binary' then
  a=private.eval_custom_ast(p_ast->'left',p_values,p_depth+1);b=private.eval_custom_ast(p_ast->'right',p_values,p_depth+1);
  if p_ast->>'op' in ('/','%') and b=0 then raise exception 'Cannot divide by zero';end if;
  case p_ast->>'op' when '+' then v=a+b;when '-' then v=a-b;when '*' then v=a*b;when '/' then v=a/b;when '%' then v=mod(a,b);else raise exception 'Unsupported operator';end case;
 elsif k='call' then
  for x in select value from jsonb_array_elements(p_ast->'args') loop args=array_append(args,private.eval_custom_ast(x,p_values,p_depth+1));end loop;
  case p_ast->>'name'
   when 'SUM' then select sum(z) into v from unnest(args) z;
   when 'MIN' then select min(z) into v from unnest(args) z;
   when 'MAX' then select max(z) into v from unnest(args) z;
   when 'ABS' then v=abs(args[1]);
   when 'ROUND' then if coalesce(args[2],2)<>trunc(coalesce(args[2],2)) or coalesce(args[2],2) not between 0 and 6 then raise exception 'ROUND precision must be an integer from 0 to 6';end if;digits=coalesce(args[2],2)::integer;v=round(args[1],digits);
   else raise exception 'Unsupported function';end case;
 else raise exception 'Unsupported formula';end if;
 if abs(v)>1e15 or v::text in ('NaN','Infinity','-Infinity') then raise exception 'Formula result is too large';end if;return v;
end $$;
create function private.custom_permissions(p_resource text,p_key text,p_path text[] default '{}') returns text[] language plpgsql stable security definer set search_path='' as $$
declare f public.custom_field_definitions;d text;r text[]='{}';
begin
 if p_key=any(p_path) then raise exception 'Circular formula dependency';end if;
 select * into f from public.custom_field_definitions where resource=p_resource and key=p_key and not archived;
 if f.id is null then
  if not p_key=any(private.custom_numeric_keys(p_resource)) then raise exception 'Unknown numeric field: %',p_key;end if;
  if p_key in ('purchase_price','income','expenses','profit','tolls','fines_permits') and p_resource in ('vehicles','drivers') then return array['reports.financial.view'];
  elsif p_key in ('loan_taken','loan_paid','loan_left') then return array['loans.view'];
  elsif p_resource='trips' and p_key in ('fare','diesel','tolls','fines_permits','food','reward','service','parking','engine_oil','other','commission','total_expense','profit') then return array['trips.finance.view'];end if;return r;
 end if;
 if f.type not in ('number','currency','percentage','formula') and cardinality(p_path)>0 then raise exception 'Formula needs a numeric field: %',p_key;end if;
 if f.restricted then r=array['reports.financial.view'];end if;
 foreach d in array f.dependencies loop r=r||private.custom_permissions(p_resource,d,p_path||p_key);end loop;
 return array(select distinct x from unnest(r) x);
end $$;
create function private.validate_custom_value(p_type text,p_options text[],p_value jsonb) returns void language plpgsql immutable set search_path='' as $$
declare t text;v numeric;
begin
 if p_value is null or p_value='null'::jsonb or p_value='""'::jsonb then return;end if;t=p_value#>>'{}';
 if p_type in ('number','currency','percentage') then
  if jsonb_typeof(p_value) not in ('string','number') or t !~ '^-?(\d+(\.\d{1,6})?|\.\d{1,6})$' then raise exception 'Enter a valid number with up to 6 decimal places';end if;
  v=t::numeric;if abs(v)>1e15 then raise exception 'Number is too large';end if;
 elsif p_type='checkbox' then if jsonb_typeof(p_value)<>'boolean' then raise exception 'Checkbox value must be true or false';end if;
 elsif p_type='date' then if t!~'^\d{4}-\d{2}-\d{2}$' or (t::date)::text<>t then raise exception 'Enter a valid date';end if;
 elsif p_type='dropdown' then if not t=any(p_options) then raise exception 'Select a configured dropdown option';end if;
 elsif p_type='text' then if jsonb_typeof(p_value)<>'string' or length(t)>1000 then raise exception 'Text must be at most 1000 characters';end if;
 else raise exception 'Calculated fields cannot be entered manually';end if;
end $$;

alter table public.custom_field_definitions enable row level security;
alter table public.custom_field_values enable row level security;
alter table public.print_template_settings enable row level security;
revoke all on public.custom_field_definitions,public.custom_field_values,public.print_template_settings from public,anon,authenticated;
grant select on public.custom_field_definitions,public.custom_field_values,public.print_template_settings to authenticated;
create policy field_read on public.custom_field_definitions for select to authenticated using(private.can('settings.manage') or (private.has_capability(resource||'.view') and not exists(select 1 from unnest(required_permissions) p where not private.has_capability(p))));
create policy custom_value_read on public.custom_field_values for select to authenticated using(private.record_permission(resource,record_id,resource||'.view') and exists(select 1 from public.custom_field_definitions f where f.id=field_id and f.resource=custom_field_values.resource and not exists(select 1 from unnest(f.required_permissions) p where not private.record_permission(custom_field_values.resource,custom_field_values.record_id,p))));
create policy print_setting_read on public.print_template_settings for select to authenticated using(private.active_session());

create function public.custom_field_catalog(p_resource text,p_archived boolean default false) returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(f) order by display_order,label),'[]') from public.custom_field_definitions f where resource=p_resource and (p_archived or not archived)
$$;
create function public.save_custom_field(p_id uuid,p_version integer,p_data jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare f public.custom_field_definitions;r public.custom_field_definitions;result uuid;res text;k text;deps text[]='{}';opt text[];perms text[];
begin
 perform private.require_permission('settings.manage');perform pg_advisory_xact_lock(87413100);
 res=p_data->>'resource';k=p_data->>'key';opt=array(select jsonb_array_elements_text(coalesce(p_data->'options','[]')));
 if cardinality(opt)>40 or exists(select 1 from unnest(opt) x where length(x) not between 1 and 80) then raise exception 'Invalid dropdown options';end if;
 if p_data->>'type'='dropdown' and cardinality(opt)=0 then raise exception 'Enter dropdown options';end if;
 if p_id is not null then
  select * into f from public.custom_field_definitions where id=p_id for update;
  if f.id is null or f.version is distinct from p_version then raise exception 'Field changed; reload' using errcode='40001';end if;
  if f.resource<>res or f.key<>k or f.type<>p_data->>'type' then raise exception 'Field key, module and type are immutable; archive and create a new field';end if;
 elsif (select count(*) from public.custom_field_definitions where resource=res and not archived)>=60 then raise exception 'Maximum 60 active custom fields per module';end if;
 if p_data->>'type'='formula' then
  if p_data->'ast' is null or octet_length((p_data->'ast')::text)>20000 or coalesce(p_data->>'formula','')='' then raise exception 'Invalid formula';end if;
  deps=private.ast_refs(p_data->'ast');
 else perform private.validate_custom_value(p_data->>'type',opt,p_data->'default_value');end if;
 if p_id is null then
  insert into public.custom_field_definitions(resource,key,label,type,default_value,required,display_order,show_form,show_card,show_table,show_print,hidden,archived,restricted,options,formula,ast,dependencies,created_by)
  values(res,k,trim(p_data->>'label'),p_data->>'type',p_data->'default_value',(p_data->>'required')::boolean,(p_data->>'display_order')::integer,(p_data->>'show_form')::boolean,(p_data->>'show_card')::boolean,(p_data->>'show_table')::boolean,(p_data->>'show_print')::boolean,(p_data->>'hidden')::boolean,(p_data->>'archived')::boolean,(p_data->>'restricted')::boolean,opt,coalesce(p_data->>'formula',''),case when p_data->>'type'='formula' then p_data->'ast' end,deps,auth.uid()) returning id into result;
 else
  result=p_id;update public.custom_field_definitions set label=trim(p_data->>'label'),default_value=p_data->'default_value',required=(p_data->>'required')::boolean,display_order=(p_data->>'display_order')::integer,show_form=(p_data->>'show_form')::boolean,show_card=(p_data->>'show_card')::boolean,show_table=(p_data->>'show_table')::boolean,show_print=(p_data->>'show_print')::boolean,hidden=(p_data->>'hidden')::boolean,archived=(p_data->>'archived')::boolean,restricted=(p_data->>'restricted')::boolean,options=opt,formula=coalesce(p_data->>'formula',''),ast=case when p_data->>'type'='formula' then p_data->'ast' end,dependencies=deps,version=version+1 where id=p_id;
 end if;
 -- Recompute restrictions for dependents too. This rejects unknown, nonnumeric,
 -- archived and circular dependencies in the same database transaction.
 for r in select * from public.custom_field_definitions where resource=res and not archived loop
  perms=private.custom_permissions(res,r.key);update public.custom_field_definitions set required_permissions=perms where id=r.id;
 end loop;
 perform private.audit('custom_field.save',res,result::text,'Custom field structure updated');return result;
end $$;
create function public.save_print_template(p_kind text,p_version integer,p_orientation text,p_signatures text[]) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.require_permission('settings.manage');
 if cardinality(p_signatures)>6 or exists(select 1 from unnest(p_signatures) s where length(trim(s)) not between 1 and 80) then raise exception 'Use at most six signature labels of 1–80 characters';end if;
 update public.print_template_settings set orientation=p_orientation,signatures=p_signatures,version=version+1 where kind=p_kind and version=p_version;
 if not found then raise exception 'Print settings changed; reload' using errcode='40001';end if;
 perform private.audit('print_template.save','print',p_kind,'Layout and signature labels updated');
end $$;

alter function public.save_form(text,uuid,integer,jsonb,integer,uuid) rename to save_form_core;
alter function public.save_form_core(text,uuid,integer,jsonb,integer,uuid) set schema private;
revoke all on function private.save_form_core(text,uuid,integer,jsonb,integer,uuid) from public,anon,authenticated;
create function public.save_form(p_resource text,p_id uuid,p_version integer,p_data jsonb,p_identity_version integer default null,p_assignment uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare saved_id uuid;f public.custom_field_definitions;values jsonb;v jsonb;k text;can_write boolean;
begin
 perform pg_advisory_xact_lock_shared(87413100);
 if p_id is not null and ((p_resource='trips' and exists(select 1 from public.trips where id=p_id and archived_at is not null)) or (p_resource='maintenance' and exists(select 1 from public.maintenance_records where id=p_id and archived_at is not null))) then raise exception 'Deleted drafts cannot be edited';end if;
 values=coalesce(p_data->'custom_values','{}');if jsonb_typeof(values)<>'object' then raise exception 'Invalid custom values';end if;
 for k in select jsonb_object_keys(values) loop
  if not exists(select 1 from public.custom_field_definitions where resource=p_resource and key=k and type<>'formula' and not archived) then raise exception 'Unknown, archived or calculated custom field: %',k;end if;
 end loop;
 if p_resource='vehicles' and p_data?'address' and length(coalesce(p_data->>'address',''))>1000 then raise exception 'Address too long';end if;
 saved_id=private.save_form_core(p_resource,p_id,p_version,p_data-'custom_values'-case when p_resource='vehicles' then 'address' else '__unused' end,p_identity_version,p_assignment);
 if p_resource='vehicles' and p_data?'address' then update public.vehicles set address=p_data->>'address' where public.vehicles.id=saved_id;end if;
 for f in select * from public.custom_field_definitions where resource=p_resource and not archived and type<>'formula' loop
  can_write=not exists(select 1 from unnest(f.required_permissions) p where not private.record_permission(p_resource,saved_id,p));
  if values?f.key and not can_write then raise exception 'Custom field permission denied' using errcode='42501';end if;
  if not can_write then continue;end if;
  if values?f.key then v=values->f.key;
  else select value into v from public.custom_field_values where resource=p_resource and record_id=saved_id and field_id=f.id;if not found then v=f.default_value;end if;end if;
  if f.required and f.show_form and not f.hidden and (v is null or v='null'::jsonb or v='""'::jsonb) then raise exception '% is required',f.label;end if;
  perform private.validate_custom_value(f.type,f.options,v);
  if values?f.key or p_id is null then insert into public.custom_field_values(resource,record_id,field_id,value) values(p_resource,saved_id,f.id,v) on conflict(resource,record_id,field_id) do update set value=excluded.value,updated_at=now();end if;
 end loop;return saved_id;
end $$;

alter function public.form_record(text,uuid,date,date) rename to form_record_core;
alter function public.form_record_core(text,uuid,date,date) set schema private;
create function public.form_record(p_resource text,p_id uuid,p_from date,p_to date) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare r jsonb;vals jsonb='{}';errors jsonb='{}';f public.custom_field_definitions;v jsonb;pending text[];remaining text[];all_fields jsonb='[]';pass integer;progress boolean;stats jsonb;
begin
 r=private.form_record_core(p_resource,p_id,p_from,p_to);
 if not private.record_permission(p_resource,p_id,p_resource||'.view') then raise exception 'Record unavailable' using errcode='42501';end if;
 if p_resource='drivers' and not private.record_permission('drivers',p_id,'drivers.documents.view') then r=r-'photo_attachment_id';end if;
 if p_resource='vehicles' then
  r=r||jsonb_build_object('driver_id_label',(select d.full_name from public.vehicle_driver_assignments a join public.drivers d on d.id=a.driver_id where a.vehicle_id=p_id and a.ended_at is null));
 end if;
 if p_resource in ('vehicles','drivers') then
  select jsonb_build_object('total_km',sum(t.end_odometer-t.start_odometer)::text,'matched_km',(sum(t.end_odometer-t.start_odometer) filter(where t.fuel_litres>0))::text,'litres',(sum(t.fuel_litres) filter(where t.fuel_litres>0))::text,'average',case when count(distinct t.fuel_basis) filter(where t.fuel_litres>0)=1 then round((sum(t.end_odometer-t.start_odometer) filter(where t.fuel_litres>0))/nullif(sum(t.fuel_litres) filter(where t.fuel_litres>0),0),2)::text end)
  into stats from public.trips t where t.financial_state='Approved' and t.operational_state='Completed' and t.business_date between p_from and p_to and case when p_resource='vehicles' then t.vehicle_id=p_id else t.driver_id=p_id end;
  r=r||stats;
 end if;
 for f in select * from public.custom_field_definitions where resource=p_resource and not archived order by display_order,label loop
  if exists(select 1 from unnest(f.required_permissions) p where not private.record_permission(p_resource,p_id,p)) then continue;end if;
  all_fields=all_fields||jsonb_build_array(to_jsonb(f));
  if f.type='formula' then pending=array_append(pending,f.key);continue;end if;
  select value into v from public.custom_field_values where resource=p_resource and record_id=p_id and field_id=f.id;if not found then v=f.default_value;end if;vals=vals||jsonb_build_object(f.key,v);
 end loop;
 pending=coalesce(pending,'{}');
 for pass in 1..61 loop
  exit when cardinality(pending)=0;remaining='{}';progress=false;
  foreach v in array array(select to_jsonb(x) from unnest(pending) x) loop
   select * into f from public.custom_field_definitions where resource=p_resource and key=v#>>'{}';
   if exists(select 1 from unnest(f.dependencies) d where d=any(pending)) then remaining=array_append(remaining,f.key);continue;end if;
   begin vals=vals||jsonb_build_object(f.key,round(private.eval_custom_ast(f.ast,r||vals),6)::text);
   exception when others then vals=vals||jsonb_build_object(f.key,null);errors=errors||jsonb_build_object(f.key,case when sqlstate='22P02' then 'A referenced value must be numeric' else left(sqlerrm,160) end);end;
   progress=true;
  end loop;pending=remaining;if not progress then exit;end if;
 end loop;
 foreach v in array array(select to_jsonb(x) from unnest(pending) x) loop errors=errors||jsonb_build_object(v#>>'{}','Circular or unavailable formula dependency');end loop;
 return r||jsonb_build_object('custom_values',vals,'custom_errors',errors,'custom_fields',all_fields);
end $$;

alter function public.form_register(text,date,date,integer,integer,text,uuid,uuid) rename to form_register_core;
alter function public.form_register_core(text,date,date,integer,integer,text,uuid,uuid) set schema private;
create function public.form_register(p_resource text,p_from date,p_to date,p_page integer default 1,p_limit integer default 25,p_search text default '',p_vehicle uuid default null,p_driver uuid default null,p_status text default '',p_sort text default 'name',p_direction text default 'asc',p_include_archived boolean default false) returns jsonb language plpgsql stable security invoker set search_path='' as $$
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
 if not p_include_archived then predicate=predicate||case when p_resource in ('trips','maintenance') then ' and t.archived_at is null' else format(' and t.%I<>''Archived''',statuscol) end;end if;
 if p_resource in ('trips','maintenance') then predicate=predicate||' and ($4::uuid is null or t.vehicle_id=$4) and ($5::uuid is null or t.driver_id=$5)';
 elsif p_resource='vehicles' then predicate=predicate||' and ($4::uuid is null or t.id=$4) and ($5::uuid is null or exists(select 1 from public.vehicle_driver_assignments a where a.vehicle_id=t.id and a.driver_id=$5 and a.ended_at is null))';
 else predicate=predicate||' and ($5::uuid is null or t.id=$5) and ($4::uuid is null or exists(select 1 from public.vehicle_driver_assignments a where a.driver_id=t.id and a.vehicle_id=$4 and a.ended_at is null))';end if;
 execute format('select count(*) from public.%I t where %s',tbl,predicate) into total using pattern,p_from,p_to,p_vehicle,p_driver,p_status;
 execute format('select coalesce(jsonb_agg(id),''[]'') from(select t.id from public.%I t where %s order by t.%I %s nulls last,t.id limit %s offset %s) q',tbl,predicate,sortcol,p_direction,p_limit,(p_page-1)*p_limit) into ids using pattern,p_from,p_to,p_vehicle,p_driver,p_status;
 for item in select value from jsonb_array_elements(ids) loop rows=rows||jsonb_build_array(public.form_record(p_resource,(item#>>'{}')::uuid,p_from,p_to));end loop;
 return jsonb_build_object('rows',rows,'count',total,'page',p_page,'from',p_from,'to',p_to);
end $$;

create function public.archive_form_record(p_resource text,p_id uuid,p_version integer,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare v public.vehicles;d public.drivers;t public.trips;m public.maintenance_records;
begin
 if length(trim(p_reason)) not between 3 and 300 then raise exception 'Enter a deletion reason';end if;
 perform pg_advisory_xact_lock(87413002);perform pg_advisory_xact_lock(87413003);
 if p_resource='vehicles' then
  select * into v from public.vehicles where id=p_id for update;perform private.require_permission('vehicles.archive',p_id,v.created_by);
  if v.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
  if exists(select 1 from public.vehicle_driver_assignments where vehicle_id=p_id and ended_at is null) or exists(select 1 from public.trips where vehicle_id=p_id and operational_state in ('Planned','In Progress') and archived_at is null) then raise exception 'End the assignment and outstanding trips before deleting this vehicle';end if;
  update public.vehicles set status='Archived',version=version+1 where id=p_id;
 elsif p_resource='drivers' then
  select * into d from public.drivers where id=p_id for update;if not private.can_driver('drivers.archive',p_id,d.created_by) then raise exception 'Permission denied' using errcode='42501';end if;
  if d.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
  if exists(select 1 from public.vehicle_driver_assignments where driver_id=p_id and ended_at is null) or exists(select 1 from public.trips where driver_id=p_id and operational_state in ('Planned','In Progress') and archived_at is null) then raise exception 'End the assignment and outstanding trips before deleting this driver';end if;
  update public.drivers set employment_status='Archived',version=version+1 where id=p_id;update public.driver_duty_sessions set ended_at=now() where driver_id=p_id and ended_at is null;
 elsif p_resource='trips' then
  select * into t from public.trips where id=p_id for update;perform private.require_permission('trips.delete_draft',t.vehicle_id,t.created_by);
  if t.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
  if t.financial_state not in ('Draft','Rejected') or exists(select 1 from public.revenue_entries where trip_id=p_id) or exists(select 1 from public.expense_entries where trip_id=p_id) then raise exception 'Posted or submitted trips cannot be deleted';end if;
  perform private.open_period(t.business_date);update public.trips set archived_at=now(),operational_state='Cancelled',version=version+1 where id=p_id;
 elsif p_resource='maintenance' then
  select * into m from public.maintenance_records where id=p_id for update;perform private.require_permission('maintenance.delete_draft',m.vehicle_id,m.created_by);
  if m.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
  if m.state not in ('Draft','Review') then raise exception 'Posted maintenance cannot be deleted';end if;
  if m.business_date is not null then perform private.open_period(m.business_date);end if;update public.maintenance_records set archived_at=now(),version=version+1 where id=p_id;
 else raise exception 'Unknown form';end if;
 perform private.audit('record.archive',p_resource,p_id::text,p_reason);
end $$;

revoke all on function private.record_permission(text,uuid,text),private.custom_numeric_keys(text),private.ast_refs(jsonb,integer),private.eval_custom_ast(jsonb,jsonb,integer),private.custom_permissions(text,text,text[]),private.validate_custom_value(text,text[],jsonb) from public,anon,authenticated;
grant execute on function private.record_permission(text,uuid,text),private.eval_custom_ast(jsonb,jsonb,integer) to authenticated;
revoke all on function public.custom_field_catalog(text,boolean),public.save_custom_field(uuid,integer,jsonb),public.save_print_template(text,integer,text,text[]),public.save_form(text,uuid,integer,jsonb,integer,uuid),public.form_record(text,uuid,date,date),public.form_register(text,date,date,integer,integer,text,uuid,uuid,text,text,text,boolean),public.archive_form_record(text,uuid,integer,text) from public,anon,authenticated;
grant execute on function public.custom_field_catalog(text,boolean),public.save_custom_field(uuid,integer,jsonb),public.save_print_template(text,integer,text,text[]),public.save_form(text,uuid,integer,jsonb,integer,uuid),public.form_record(text,uuid,date,date),public.form_register(text,date,date,integer,integer,text,uuid,uuid,text,text,text,boolean),public.archive_form_record(text,uuid,integer,text) to authenticated;

create function public.print_templates() returns jsonb language sql stable security invoker set search_path='' as $$select coalesce(jsonb_agg(to_jsonb(s) order by kind),'[]') from public.print_template_settings s$$;
revoke all on function public.print_templates() from public,anon,authenticated;
grant execute on function public.print_templates() to authenticated;

alter function public.dashboard(date,date,text,numeric) rename to dashboard_core;
alter function public.dashboard_core(date,date,text,numeric) set schema private;
create function public.dashboard(p_from date,p_to date,p_basis text default 'measured',p_min_distance numeric default 100) returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare r jsonb;
begin
 r=private.dashboard_core(p_from,p_to,p_basis,p_min_distance);
 if private.has_capability('drivers.view') then r=r||jsonb_build_object('total_drivers',(select count(*) from public.drivers where employment_status<>'Archived'),'active_drivers',(select count(*) from public.drivers where employment_status='Active'),'driver_expiry_alerts',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name,'expiry',licence_expiry)),'[]') from public.drivers where employment_status='Active' and licence_expiry <= (now() at time zone 'Asia/Karachi')::date+30));end if;
 if private.has_capability('vehicles.view') then r=r||jsonb_build_object('available_vehicles',(select count(*) from public.vehicles v where status='Active' and not exists(select 1 from public.trips t where t.vehicle_id=v.id and t.operational_state='In Progress' and t.archived_at is null)),'vehicle_expiry_alerts',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',registration,'expiry',document_expiry)),'[]') from public.vehicles where status not in ('Sold','Archived') and document_expiry <= (now() at time zone 'Asia/Karachi')::date+30));end if;
 if private.has_capability('trips.view') then r=r||jsonb_build_object('active_trips',(select count(*) from public.trips where operational_state='In Progress' and archived_at is null),'completed_trips',(select count(*) from public.trips where operational_state='Completed' and archived_at is null and business_date between p_from and p_to),'pending_trips',(select count(*) from public.trips where financial_state='Submitted' and archived_at is null));end if;
 return r;
end $$;
revoke all on function public.dashboard(date,date,text,numeric) from public,anon,authenticated;
grant execute on function public.dashboard(date,date,text,numeric) to authenticated;

-- A profile photo always points to an existing, authorized private image attachment.
create function public.set_driver_photo(p_driver uuid,p_attachment uuid,p_version integer) returns integer language plpgsql security definer set search_path='' as $$
declare d public.drivers;a public.attachments;v integer;
begin
 select * into d from public.drivers where id=p_driver for update;
 if d.id is null then raise exception 'Driver unavailable' using errcode='42501';end if;
 if not private.can_driver('drivers.update',d.id,d.created_by) or not private.can_driver('drivers.documents.view',d.id,d.created_by) then raise exception 'Driver photo permission denied' using errcode='42501';end if;
 if d.version is distinct from p_version then raise exception 'Driver changed; reopen the record' using errcode='40001';end if;
 if p_attachment is not null then
  select * into a from public.attachments where id=p_attachment;
  if a.driver_id is distinct from p_driver or a.state is distinct from 'ready' or a.mime_type not in ('image/jpeg','image/png') or not private.can_attachment(p_attachment,'view') then raise exception 'Choose a ready JPEG or PNG belonging to this driver';end if;
 end if;
 update public.drivers set photo_attachment_id=p_attachment,version=version+1 where id=p_driver returning version into v;
 perform private.audit('driver.photo','drivers',p_driver::text,'Driver profile photo updated');return v;
end $$;
create function private.clear_driver_photo() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.state in ('deleting','deleted') then update public.drivers set photo_attachment_id=null,version=version+1 where photo_attachment_id=new.id;end if;return new;
end $$;
create trigger driver_photo_removed after update of state on public.attachments for each row when(old.state is distinct from new.state) execute function private.clear_driver_photo();
revoke all on function public.set_driver_photo(uuid,uuid,integer),private.clear_driver_photo() from public,anon,authenticated;
grant execute on function public.set_driver_photo(uuid,uuid,integer) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261010103000','custom_fields_cards_print',array[]::text[]);

-- Migration: 20261011100000_transport_enhancements.sql
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

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261011100000','transport_enhancements',array[]::text[]);

-- Migration: 20261011120000_password_login_only.sql
-- Retire the unused social-login provisioning entry point. Existing profiles,
-- roles, sessions, history and financial records are preserved.
-- The earlier applied migration remains unchanged for upgrade consistency.
drop function if exists public.server_google_user_sync(uuid,text,text);
notify pgrst, 'reload schema';

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261011120000','password_login_only',array[]::text[]);

-- Migration: 20261011160000_master_review.sql
-- Forward review fixes; preserve all business rows/tables/fields and historical migrations.
create or replace function public.server_session_create(p_hash text,p_user uuid,p_auth_session uuid,p_credentials text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.app_users where id=p_user and active) then raise exception 'Account unavailable' using errcode='42501';end if;
 if not exists(select 1 from auth.sessions where id=p_auth_session and user_id=p_user) then raise exception 'Invalid Auth session' using errcode='42501';end if;
 insert into private.app_sessions(token_hash,user_id,auth_session_id,credentials,expires_at)
 values(p_hash,p_user,p_auth_session,p_credentials,now()+interval '3 hours');
end $$;
-- Shorten absolute lifetime only; preserve version/refresh locks and identity.
update private.app_sessions set expires_at=least(expires_at,created_at+interval '3 hours')
where revoked_at is null and expires_at>created_at+interval '3 hours';

-- Reuse the existing drivers.remarks column, form transaction and permission checks.
create or replace function private.save_form_core(p_resource text,p_id uuid,p_version integer,p_data jsonb,p_identity_version integer default null,p_assignment uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare v public.vehicles;d public.drivers;t public.trips;m public.maintenance_records;result uuid;merged jsonb;allowed text[];k text;cat text;old_assignment public.vehicle_driver_assignments;target uuid;desired numeric;existing numeric;delta numeric;l public.trip_expense_lines;ident jsonb;
begin
 if not private.active_session() then raise exception 'Sign in required' using errcode='42501';end if;
 case p_resource
 when 'vehicles' then allowed=array['registration','manufacturer','purchase_year','purchase_price','major_maintenance_work','remarks','model','status','opening_odometer','service_interval_km','document_expiry'];
 when 'drivers' then allowed=array['vehicle_id','full_name','father_name','cnic','licence_number','mobile','emergency_contact','joining_date','leaving_date','address','licence_expiry','employment_status','remarks'];
 when 'trips' then allowed=array['business_date','vehicle_id','driver_id','cycle_number','fare','diesel','tolls','fines_permits','food','reward','service','parking','engine_oil','other','commission','start_odometer','end_odometer','fuel_litres','weight','remarks','origin','destination','route_description','cargo','fuel_basis','weight_unit'];
 when 'maintenance' then allowed=array['vehicle_id','driver_id','engine','gearbox','parts','tyres','wiring','starter','alternator','lighting','cabin','body'];
 else raise exception 'Unknown form';end case;
 if jsonb_typeof(p_data)<>'object' or exists(select 1 from jsonb_object_keys(p_data) key where not key=any(allowed)) then raise exception 'Unexpected form field';end if;
 if exists(select 1 from jsonb_each_text(p_data) e where length(e.value)>1000) then raise exception 'Field too long';end if;
 if p_resource='vehicles' then
  if p_id is not null then select * into v from public.vehicles where id=p_id for update;if v.id is null then raise exception 'Vehicle unavailable';end if;merged=to_jsonb(v)||p_data;else merged=jsonb_build_object('status','Active','opening_odometer','0')||p_data;end if;
  if p_data?'purchase_price' then perform private.require_permission('reports.financial.view',p_id,coalesce(v.created_by,auth.uid()));end if;
  result=public.save_vehicle(p_id,p_version,merged);
  update public.vehicles set purchase_year=case when p_data?'purchase_year' then nullif(p_data->>'purchase_year','')::integer else purchase_year end,major_maintenance_work=case when p_data?'major_maintenance_work' then p_data->>'major_maintenance_work' else major_maintenance_work end where id=result;
 elsif p_resource='drivers' then
  -- Match the assignment action's lock order before acquiring the driver lock.
  perform pg_advisory_xact_lock(87413002);
  if p_id is not null then select * into d from public.drivers where id=p_id for update;if d.id is null then raise exception 'Driver unavailable';end if;merged=to_jsonb(d)||p_data;else merged=jsonb_build_object('employment_status','Active')||p_data;end if;
  result=public.save_driver(p_id,p_version,merged);
  if p_data ?| array['father_name','cnic','licence_number','address','emergency_contact'] then
   select to_jsonb(i) into ident from public.driver_identity_details i where driver_id=result;
   perform public.save_driver_identity(result,p_identity_version,coalesce(ident,'{}')||p_data);
  end if;
  if p_data?'vehicle_id' then
   select * into old_assignment from public.vehicle_driver_assignments where driver_id=result and ended_at is null;
   if old_assignment.id is distinct from p_assignment then raise exception 'Assignment changed; reload' using errcode='40001';end if;
   target=nullif(p_data->>'vehicle_id','')::uuid;
   if target is distinct from old_assignment.vehicle_id then
    if old_assignment.id is not null then perform public.assign_driver(old_assignment.vehicle_id,null,'Changed through Driver form');end if;
    if target is not null then
     if exists(select 1 from public.vehicle_driver_assignments where vehicle_id=target and ended_at is null) then raise exception 'Vehicle already has an active driver';end if;
     if not private.can('vehicles.view',target,(select created_by from public.vehicles where id=target)) then raise exception 'Vehicle out of scope' using errcode='42501';end if;
     perform public.assign_driver(target,result,'Changed through Driver form');
    end if;
   end if;
  end if;
 elsif p_resource='trips' then
  perform pg_advisory_xact_lock(87413003);
  if p_id is not null then select * into t from public.trips where id=p_id for update;if t.id is null then raise exception 'Trip unavailable';end if;merged=to_jsonb(t)||p_data;else merged=jsonb_build_object('operational_state','Planned','fuel_basis','purchase_estimate','weight_unit','metric tonnes')||p_data;end if;
  if p_data ?| array['fare','diesel','tolls','fines_permits','food','reward','service','parking','engine_oil','other','commission'] then perform private.require_permission('trips.finance.view',(merged->>'vehicle_id')::uuid,coalesce(t.created_by,auth.uid()));end if;
  if nullif(merged->>'end_odometer','')::numeric < nullif(merged->>'start_odometer','')::numeric then raise exception 'End odometer must not be below start odometer';end if;
  result=public.save_trip(p_id,p_version,merged,null);
  foreach cat in array array['diesel','tolls','fines_permits','food','reward','service','parking','engine_oil','other','commission'] loop
   if not p_data?cat then continue;end if;
   desired=nullif(p_data->>cat,'')::numeric;
   if desired is null then continue;end if;
   if desired<0 or desired<>round(desired,2) then raise exception 'Invalid expense amount';end if;
   select coalesce(sum(amount),0) into existing from public.trip_expense_lines where trip_id=result and category=cat;
   delta=desired-existing;
   -- Keep original IDs/descriptions/dates and attachment associations. Increase one
   -- existing line; reduce descending-ID lines first, retaining zero-amount lines.
   if delta>0 then
    select * into l from public.trip_expense_lines where trip_id=result and category=cat order by id desc limit 1;
    if l.id is null then insert into public.trip_expense_lines(trip_id,category,business_date,amount,description) values(result,cat,(merged->>'business_date')::date,delta,'');
    else perform private.open_period(l.business_date);update public.trip_expense_lines set amount=amount+delta where id=l.id;end if;
   elsif delta<0 then
    delta=-delta;
    for l in select * from public.trip_expense_lines where trip_id=result and category=cat order by id desc for update loop
     exit when delta=0;perform private.open_period(l.business_date);
     update public.trip_expense_lines set amount=greatest(0,amount-delta) where id=l.id;
     delta=greatest(0,delta-l.amount);
    end loop;
   end if;
  end loop;
 elsif p_resource='maintenance' then
  perform pg_advisory_xact_lock(87413003);
  target=(p_data->>'vehicle_id')::uuid;
  if p_id is not null then
   select * into m from public.maintenance_records where id=p_id for update;
   if m.id is null then raise exception 'Maintenance unavailable';end if;
   perform private.require_permission('maintenance.create',m.vehicle_id,m.created_by);
   if m.version is distinct from p_version then raise exception 'Record changed; reload' using errcode='40001';end if;
   if m.state not in ('Draft','Review') then raise exception 'Posted maintenance is immutable';end if;
   if m.business_date is not null then perform private.open_period(m.business_date);end if;
   if target<>m.vehicle_id then raise exception 'Existing maintenance vehicle is fixed';end if;
  else perform private.require_permission('maintenance.create',target,auth.uid());end if;
  if not private.can('vehicles.view',target,(select created_by from public.vehicles where id=target)) then raise exception 'Vehicle out of scope' using errcode='42501';end if;
  if nullif(p_data->>'driver_id','') is not null and not private.can_driver('drivers.view',(p_data->>'driver_id')::uuid,(select created_by from public.drivers where id=(p_data->>'driver_id')::uuid)) then raise exception 'Driver out of scope' using errcode='42501';end if;
  if p_id is null then insert into public.maintenance_records(vehicle_id,driver_id,state,created_by) values(target,nullif(p_data->>'driver_id','')::uuid,'Draft',auth.uid()) returning id into result;
  else result=p_id;update public.maintenance_records set driver_id=case when p_data?'driver_id' then nullif(p_data->>'driver_id','')::uuid else driver_id end,version=version+1 where id=result;end if;
  foreach k in array array['engine','gearbox','parts','tyres','wiring','starter','alternator','lighting','cabin','body'] loop
   if p_data?k then insert into public.maintenance_components values(result,k,coalesce(p_data->>k,'')) on conflict(maintenance_id,category) do update set work_detail=excluded.work_detail;end if;
  end loop;
 end if;
 perform private.audit('form.save',p_resource,result::text,'Exact form saved atomically; sensitive values omitted');return result;
end $$;
revoke all on function private.save_form_core(text,uuid,integer,jsonb,integer,uuid) from public,anon,authenticated;

-- Existing trips_dates begins with business_date. These support record-first filters.
create index if not exists trips_approved_vehicle_date on public.trips(vehicle_id,business_date)
 where financial_state='Approved' and operational_state='Completed';
create index if not exists trips_approved_driver_date on public.trips(driver_id,business_date)
 where financial_state='Approved' and operational_state='Completed';

notify pgrst, 'reload schema';

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261011160000','master_review',array[]::text[]);

-- Migration: 20261014120000_record_lifecycle.sql
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

insert into supabase_migrations.schema_migrations(version,name,statements) values('20261014120000','record_lifecycle',array[]::text[]);

notify pgrst, 'reload schema';
commit;
