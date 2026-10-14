import { config as dotenv } from 'dotenv';
import { z } from 'zod';
import { resolve } from 'node:path';
dotenv({path:resolve(process.cwd(),'.env'),override:false});
const boolean = z.enum(['true','false']).default('false').transform(v=>v==='true');
const schema=z.object({
 APP_ENV:z.enum(['development','local-live','production']).default('development'),
 NODE_ENV:z.enum(['development','test','production']).default('development'),
 PORT:z.coerce.number().int().min(1).max(65535).default(5000),
 APP_URL:z.string().url(), ALLOWED_ORIGINS:z.string().min(1),
 BUSINESS_TIMEZONE:z.literal('Asia/Karachi').default('Asia/Karachi'), CURRENCY:z.literal('PKR').default('PKR'),
 SUPABASE_URL:z.string().url(),SUPABASE_PUBLISHABLE_KEY:z.string().min(20),SUPABASE_SECRET_KEY:z.string().min(20),
 SESSION_ENCRYPTION_KEY:z.string().regex(/^[0-9a-f]{64}$/i,'Must be 64 hexadecimal characters'),
 ADMIN_BOOTSTRAP_ENABLED:boolean,ADMIN_EMAIL:z.string().email().optional(),ADMIN_PASSWORD:z.string().optional(),
 ALLOW_LIVE_DATABASE_ACCESS:boolean,LOG_LEVEL:z.enum(['info','error']).default('info'),
 TRUST_PROXY_HOPS:z.coerce.number().int().min(0).max(2).default(0)
});
export type Config=z.infer<typeof schema>;
export function parseConfig(source:Record<string,string|undefined>):Config {
 const parsed=schema.safeParse(source);
 if(!parsed.success) throw new Error('Configuration required: '+parsed.error.issues.map(i=>`${i.path.join('.')}: ${i.message}`).join('; '));
 const c=parsed.data;const origin=new URL(c.APP_URL);
 if(origin.pathname!=='/'||origin.search||origin.hash||origin.username||origin.password)throw new Error('APP_URL must be a plain origin');
 const origins=c.ALLOWED_ORIGINS.split(',').map(x=>x.trim());
 if(origins.some(x=>new URL(x).origin!==x)||!origins.includes(origin.origin))throw new Error('ALLOWED_ORIGINS must contain exact origins including APP_URL');
 if(c.SUPABASE_PUBLISHABLE_KEY===c.SUPABASE_SECRET_KEY)throw new Error('Public and privileged keys must be distinct');
 if(c.SUPABASE_PUBLISHABLE_KEY.startsWith('sb_secret_'))throw new Error('A privileged key cannot be a publishable key');
 if(c.APP_ENV!=='development'&&(!c.ALLOW_LIVE_DATABASE_ACCESS||origin.protocol!=='https:'||origins.some(x=>!x.startsWith('https://'))))throw new Error('Live profiles require explicit access and HTTPS for every origin');
 if(c.APP_ENV==='development' && c.ALLOW_LIVE_DATABASE_ACCESS)throw new Error('Use the explicit local-live profile for live access');
 if(c.APP_ENV==='production'&&c.NODE_ENV!=='production')throw new Error('Production requires NODE_ENV=production');
 const supa=new URL(c.SUPABASE_URL);
 if(supa.protocol!=='https:'&&!(c.APP_ENV==='development'&&['localhost','127.0.0.1'].includes(supa.hostname)))throw new Error('Supabase must use HTTPS except isolated local development');
 return c;
}
export function readConfig():Config{return parseConfig(process.env);}
export function cookieName(c:Config){return c.APP_ENV==='development'?'gbt_dev_session':c.APP_ENV==='local-live'?'__Host-gbt_local_live':'__Host-gbt_session';}
