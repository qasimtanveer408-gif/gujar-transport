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
