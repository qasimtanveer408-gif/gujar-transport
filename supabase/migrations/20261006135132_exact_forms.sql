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
