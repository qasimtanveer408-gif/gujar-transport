-- Retire the unused social-login provisioning entry point. Existing profiles,
-- roles, sessions, history and financial records are preserved.
-- The earlier applied migration remains unchanged for upgrade consistency.
drop function if exists public.server_google_user_sync(uuid,text,text);
notify pgrst, 'reload schema';
