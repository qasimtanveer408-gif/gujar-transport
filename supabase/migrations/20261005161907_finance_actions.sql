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
