// Compiled BFF and real browser, mocked remote Auth/SQL only; never live data.
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {mkdir,writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';
import {createApp} from '../dist/server/app.js';
import {parseConfig} from '../dist/server/config.js';
import {AppError} from '../dist/server/errors.js';
const config=parseConfig({APP_ENV:'development',APP_URL:'http://localhost:5173',ALLOWED_ORIGINS:'http://localhost:5173',SUPABASE_URL:'https://example.supabase.co',SUPABASE_PUBLISHABLE_KEY:'test-publishable-key-only',SUPABASE_SECRET_KEY:'test-secret-key-only',SESSION_ENCRYPTION_KEY:randomBytes(32).toString('hex')});
let signed=false,expires=0;
const db={rpc:async name=>({data:name==='dashboard'?{today:'2026-10-11',refreshed_at:new Date().toISOString(),vehicles:1,vehicle_status:{Active:1}}:name==='notification_center'?{rows:[],count:0,page:1,unread_count:0}:[],error:null}),from:()=>({select:()=>({single:async()=>({data:{refresh_seconds:60},error:null})})})};
const sessions={
 login:async()=>{signed=true;expires=Date.now()+2500;return {raw:'TEST-session',csrf:'TEST-csrf'};},
 authenticate:async raw=>{if(raw!=='TEST-session'||!signed||Date.now()>=expires)throw new AppError(401,'SESSION_EXPIRED','Sign in again.');return {db,access:{user:{id:'test',email:'test@example.test',display_name:'TEST Staff'},roles:['Viewer'],permissions:['vehicles.view']},session:{expires_at:new Date(expires).toISOString()},csrf:'TEST-csrf'};},
 logout:async()=>{signed=false;return {remoteSignOutVerified:true};}
};
const admin={rpc:async()=>({data:true,error:null})};
const app=createApp(config,{sessions,admin});
// The dynamically assigned local port is the test's exact allowed Origin.
const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
const base='http://127.0.0.1:'+server.address().port;
// Auth routes must use that same Origin; rebuild with it instead of relaxing checks.
await new Promise(r=>server.close(r));config.APP_URL=base;config.ALLOWED_ORIGINS=base;
const bound=createApp(config,{sessions,admin}).listen(Number(new URL(base).port),'127.0.0.1');await new Promise(r=>bound.once('listening',r));
const browser=await chromium.launch({...(process.env.PLAYWRIGHT_EXECUTABLE_PATH?{executablePath:process.env.PLAYWRIGHT_EXECUTABLE_PATH}:{}),args:['--no-sandbox','--disable-gpu','--single-process']});
const page=await browser.newPage({reducedMotion:'reduce'}),errors=[],requests=[];
page.on('pageerror',e=>errors.push(e.message));page.on('request',req=>requests.push(new URL(req.url()).pathname));
try{
 await page.goto(base);const button=page.getByRole('button',{name:'Sign in',exact:true});await button.waitFor();
 assert.ok(!requests.some(p=>/(Dashboard|ExactFormsPage|ReportsPage|AdminPages)-/.test(p)),'Protected pages must not load at login');
 const initialScripts=requests.filter(p=>p.endsWith('.js'));
 await button.hover();assert.equal(await button.evaluate(el=>getComputedStyle(el).transform),'none');
 await page.emulateMedia({reducedMotion:'no-preference'});await page.waitForFunction(()=>!matchMedia('(prefers-reduced-motion: reduce)').matches);await page.mouse.move(0,0);await button.hover();
 // Allow the 160ms CSS transition to settle before comparing its matrix.
 await page.waitForTimeout(220);
 const hoverCapabilities=await button.evaluate(el=>({eligible:matchMedia('(hover:hover) and (pointer:fine)').matches,transform:getComputedStyle(el).transform,duration:getComputedStyle(el).transitionDuration}));
 assert.ok(hoverCapabilities.duration.includes('0.16s'),'CSS feedback must be lightweight');
 if(hoverCapabilities.eligible)assert.notEqual(hoverCapabilities.transform,'none');
 else assert.equal(hoverCapabilities.transform,'none','Touch surfaces must not shift on hover');
 await page.emulateMedia({reducedMotion:'reduce'});
 await page.getByLabel('Email address').fill('test@example.test');await page.getByLabel('Password',{exact:true}).fill('TEST-password');await button.click();
 await page.getByRole('heading',{name:'WELCOME SIR ATTIQ',exact:true}).waitFor();
 assert.ok(requests.some(p=>/Dashboard-/.test(p)),'Dashboard is loaded after sign-in');
 await page.locator('button.stat-card').first().hover();assert.equal(await page.locator('button.stat-card').first().evaluate(el=>getComputedStyle(el).transform),'none');
 await page.getByRole('button',{name:'Sign in',exact:true}).waitFor();
 await page.getByRole('alert').filter({hasText:'Your session ended'}).waitFor();assert.equal(await page.locator('.workspace-content').count(),0);
 assert.deepEqual(errors,[]);
 await mkdir('verification/master-update',{recursive:true});await writeFile('verification/master-update/browser-performance.json',JSON.stringify({status:'passed',initialScripts,hoverCapabilities,checks:['Protected page chunks deferred until sign-in','Hover feedback honors pointer capabilities','Reduced motion disables movement on buttons/cards','Server-reported expiry returns to login','No JavaScript errors'],scope:'Compiled BFF/local browser; remote Auth and SQL mocked'},null,2));
 console.log('PASS compiled-browser: lazy loading, hover/reduced motion and server-timed expiry with protected data hidden');
}finally{await browser.close();await new Promise(r=>bound.close(r));}
