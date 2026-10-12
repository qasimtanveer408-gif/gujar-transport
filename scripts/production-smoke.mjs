// Validate the compiled server locally with fake credentials and no remote calls.
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {mkdir,writeFile} from 'node:fs/promises';
import {createApp} from '../dist/server/app.js';
import {parseConfig} from '../dist/server/config.js';
const config=parseConfig({APP_ENV:'production',NODE_ENV:'production',APP_URL:'https://transport.example.test',ALLOWED_ORIGINS:'https://transport.example.test',SUPABASE_URL:'https://example.supabase.co',SUPABASE_PUBLISHABLE_KEY:'test-publishable-key-only',SUPABASE_SECRET_KEY:'test-privileged-key-only',SESSION_ENCRYPTION_KEY:randomBytes(32).toString('hex'),ALLOW_LIVE_DATABASE_ACCESS:'true'});
const originalFetch=globalThis.fetch,remoteRequests=[];
globalThis.fetch=async(input,options)=>{if(new URL(String(input)).hostname!=='127.0.0.1'){remoteRequests.push(String(input));throw new Error('Remote calls are forbidden in this smoke test.');}return originalFetch(input,options);};
const server=createApp(config).listen(0,'127.0.0.1');await new Promise(resolve=>server.once('listening',resolve));
const address=server.address();if(!address||typeof address==='string')throw new Error('No test address');const base=`http://127.0.0.1:${address.port}`;
try{
 const health=await fetch(base+'/api/health');assert.equal(health.status,200);assert.equal((await health.json()).environment,'production');
 assert.match(health.headers.get('content-security-policy')??'',/connect-src 'self'/);assert.match(health.headers.get('strict-transport-security')??'',/max-age=/);assert.equal(health.headers.has('x-powered-by'),false);
 const nested=await fetch(base+'/trips');assert.equal(nested.status,200);const html=await nested.text();assert.match(html,/id="root"/);
 const asset=html.match(/src="([^"]+\.js)"/)?.[1];assert.ok(asset);assert.equal((await fetch(base+asset)).status,200);assert.equal((await fetch(base+'/brand/logo.png')).status,200);
 const protectedRoute=await fetch(base+'/api/auth/me');assert.equal(protectedRoute.status,401);assert.match(protectedRoute.headers.get('cache-control')??'',/no-store/);
 const csrf=await fetch(base+'/api/auth/csrf');assert.equal(csrf.status,200);const cookie=csrf.headers.getSetCookie()[0];assert.match(cookie,/^__Host-gbt_csrf=/);assert.match(cookie,/Secure/);assert.match(cookie,/HttpOnly/);assert.match(cookie,/SameSite=Strict/);
 assert.equal((await fetch(base+'/api/auth/login',{method:'POST',headers:{Origin:'https://evil.example.test'}})).status,403);
 assert.equal((await fetch(base+'/api/auth/login',{method:'POST',headers:{Origin:config.APP_URL}})).status,403);
 assert.equal((await fetch(base+'/api/health',{method:'OPTIONS',headers:{Origin:config.APP_URL}})).status,204);
 const hidden=await fetch(base+'/.env');assert.match(hidden.headers.get('content-type')??'',/text\/html/);assert.ok(!(await hidden.text()).includes('SUPABASE_SECRET_KEY'));
 assert.deepEqual(remoteRequests,[]);
 const result={date:'2026-10-11',status:'passed',checks:['Compiled nested pages and client assets','Brand logo','API health and protected-route rejection','Production CSP/HSTS and no technology header','Secure HttpOnly Strict pre-login cookie','Foreign-origin rejection and missing-CSRF rejection','Exact-origin preflight','Environment file not served'],remoteRequests:remoteRequests.length,scope:'Local compiled-server smoke only; HTTPS deployment and hosted Auth/database are not tested.'};
 await mkdir('verification/ui-review',{recursive:true});await writeFile('verification/ui-review/production-smoke.json',JSON.stringify(result,null,2));
 console.log('PASS compiled production smoke: static pages/assets, protected API, Origin/CSRF, CSP/HSTS, Secure/HttpOnly cookies and no remote requests');
}finally{globalThis.fetch=originalFetch;await new Promise(resolve=>server.close(resolve));}
