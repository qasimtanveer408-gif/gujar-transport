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
