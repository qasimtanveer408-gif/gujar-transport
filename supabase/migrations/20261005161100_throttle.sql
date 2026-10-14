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
