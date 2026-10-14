import {createClient} from '@supabase/supabase-js';
import type {Config} from './config.js';
const noSession={persistSession:false,autoRefreshToken:false,detectSessionInUrl:false};
export function publicClient(c:Config){return createClient(c.SUPABASE_URL,c.SUPABASE_PUBLISHABLE_KEY,{auth:noSession});}
export function userClient(c:Config,accessToken:string){return createClient(c.SUPABASE_URL,c.SUPABASE_PUBLISHABLE_KEY,{auth:noSession,global:{headers:{Authorization:`Bearer ${accessToken}`}}});}
export function privilegedClient(c:Config){return createClient(c.SUPABASE_URL,c.SUPABASE_SECRET_KEY,{auth:noSession});}
export type Client=ReturnType<typeof userClient>;
