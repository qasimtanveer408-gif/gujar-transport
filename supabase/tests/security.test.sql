begin;
select plan(5);
select ok(not has_function_privilege('anon','public.my_access()','EXECUTE'),'No anonymous access RPC');
select ok(not has_function_privilege('authenticated','public.server_session_read(text)','EXECUTE'),'Sessions server-only');
select ok(not has_function_privilege('authenticated','public.server_bootstrap_begin(text)','EXECUTE'),'Bootstrap server-only');
select ok(not has_table_privilege('authenticated','private.app_sessions','SELECT'),'Private sessions denied');
select ok(not has_table_privilege('authenticated','public.revenue_entries','INSERT'),'Direct ledger writes denied');
select * from finish();
rollback;
