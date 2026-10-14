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
