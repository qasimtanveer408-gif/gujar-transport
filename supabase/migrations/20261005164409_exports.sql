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
