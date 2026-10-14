import { createClient } from '@supabase/supabase-js';
const noSession = { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false };
export function publicClient(c) { return createClient(c.SUPABASE_URL, c.SUPABASE_PUBLISHABLE_KEY, { auth: noSession }); }
export function userClient(c, accessToken) { return createClient(c.SUPABASE_URL, c.SUPABASE_PUBLISHABLE_KEY, { auth: noSession, global: { headers: { Authorization: `Bearer ${accessToken}` } } }); }
export function privilegedClient(c) { return createClient(c.SUPABASE_URL, c.SUPABASE_SECRET_KEY, { auth: noSession }); }
