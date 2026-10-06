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
