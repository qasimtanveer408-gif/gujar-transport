import {readConfig,cookieName} from '../server/config.js';
try{const c=readConfig();console.info({valid:true,profile:c.APP_ENV,origin:c.APP_URL,supabaseHost:new URL(c.SUPABASE_URL).hostname,cookie:cookieName(c),bootstrapEnabled:c.ADMIN_BOOTSTRAP_ENABLED,setupPasswordPresent:Boolean(c.ADMIN_PASSWORD)});}catch(e){console.error(e instanceof Error?e.message:'Invalid environment');process.exitCode=1;}
