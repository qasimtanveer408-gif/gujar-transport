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
