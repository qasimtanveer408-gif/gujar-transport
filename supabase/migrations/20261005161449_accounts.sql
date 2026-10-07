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
