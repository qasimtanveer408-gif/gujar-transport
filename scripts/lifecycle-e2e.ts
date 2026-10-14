// Actual compiled React + Express + isolated PostgreSQL. Only sign-in and the
// external Storage/Auth providers are substituted; no hosted database is used.
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {mkdir,writeFile} from 'node:fs/promises';
import {createServer} from 'node:net';
import {chromium} from 'playwright';
import {createApp} from '../server/app.js';
import {parseConfig} from '../server/config.js';
import {formFixture} from '../tests/helpers/form-fixture.js';
import type {Client} from '../server/supabase.js';
import type {SessionService,AuthContext} from '../server/session.js';
const fixture=await formFixture();
const quote=(s:string)=>{if(!/^[a-z_]+$/.test(s))throw new Error('Test identifier rejected');return '"'+s+'"';};
const result=async(sql:string,args:unknown[]=[])=>{try{return {data:(await fixture.db.query(sql,args)).rows,error:null};}catch(e){const x=e as {code:string;message:string};return {data:null,error:{code:x.code,message:x.message}};}};
const db={
 rpc:async(name:string,args:Record<string,unknown>={})=>{const entries=Object.entries(args);const r=await result(`select public.${quote(name)}(${entries.map(([k],i)=>`${quote(k)} => $${i+1}`).join(',')}) data`,entries.map(([,v])=>typeof v==='object'&&v!==null?JSON.stringify(v):v));return {data:r.data?.[0]?.data,error:r.error};},
 from:(table:string)=>{
  let columns='*',order='',limit='',single=false;const conditions:string[]=[],values:unknown[]=[];
  const query={select:(cols:string)=>{columns=cols;return query;},eq:(col:string,value:unknown)=>{values.push(value);conditions.push(`${quote(col)}=$${values.length}`);return query;},is:(col:string)=>{conditions.push(`${quote(col)} is null`);return query;},neq:(col:string,value:unknown)=>{values.push(value);conditions.push(`${quote(col)}<>$${values.length}`);return query;},order:(col:string,opts?:{ascending?:boolean})=>{order=` order by ${quote(col)} ${opts?.ascending===false?'desc':'asc'}`;return query;},limit:(n:number)=>{limit=` limit ${Number(n)}`;return query;},single:()=>{single=true;return query;},maybeSingle:()=>{single=true;return query;},then:async(resolve:(v:unknown)=>unknown)=>{const r=await result(`select ${columns} from public.${quote(table)} ${conditions.length?'where '+conditions.join(' and '):''}${order}${limit}`,values);return resolve({...r,data:single?r.data?.[0]??null:r.data});}};return query;
 }
} as unknown as Client;
const admin={rpc:async(name:string)=>({data:name==='server_deletion_jobs'?[]:true,error:null})} as unknown as Client;
const userId=await fixture.scalar<string>('select auth.uid()');
const sessions={authenticate:async()=>({db,access:{user:{id:userId,display_name:'TEST Administrator',email:'test@example.test'},permissions:fixture.permissions,roles:['Super Admin']},csrf:'TEST-csrf'} as AuthContext)} as SessionService;
const socket=createServer();socket.listen(0,'127.0.0.1');await new Promise<void>(r=>socket.once('listening',r));const address=socket.address();if(!address||typeof address==='string')throw new Error();const port=address.port;await new Promise<void>(r=>socket.close(()=>r()));
const base=`http://127.0.0.1:${port}`;
const c=parseConfig({APP_ENV:'development',APP_URL:base,ALLOWED_ORIGINS:base,SUPABASE_URL:'https://example.supabase.co',SUPABASE_PUBLISHABLE_KEY:'TEST-publishable-key-only',SUPABASE_SECRET_KEY:'TEST-secret-key-only',SESSION_ENCRYPTION_KEY:randomBytes(32).toString('hex')});
const server=createApp(c,{admin,sessions}).listen(port,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));
const browser=await chromium.launch({...(process.env.PLAYWRIGHT_EXECUTABLE_PATH?{executablePath:process.env.PLAYWRIGHT_EXECUTABLE_PATH}:{}),args:['--no-sandbox','--disable-gpu','--disable-dev-shm-usage','--single-process']});
const page=await browser.newPage({viewport:{width:1440,height:1000},reducedMotion:'reduce'}),errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));
const dialog=()=>page.getByRole('dialog').last();
const screenshots=process.env.LIFECYCLE_SCREENSHOTS;
async function noOverlappingButtons(){const overlap=await page.locator('.record-card-actions,.gbt-dialog footer,.row-actions').evaluateAll(groups=>groups.flatMap(g=>{const bs=[...g.querySelectorAll('button')].filter(b=>b.offsetWidth>0).map(b=>({text:b.textContent,box:b.getBoundingClientRect()}));const errors=[];for(let i=0;i<bs.length;i++)for(let j=i+1;j<bs.length;j++){const a=bs[i].box,b=bs[j].box;if(Math.min(a.right,b.right)-Math.max(a.left,b.left)>1&&Math.min(a.bottom,b.bottom)-Math.max(a.top,b.top)>1)errors.push(bs[i].text+' / '+bs[j].text);}return errors;}));assert.deepEqual(overlap,[]);}
try{
 await page.goto(base+'/vehicles');await page.getByRole('heading',{name:'TEST-001',exact:true}).waitFor();await noOverlappingButtons();
 if(screenshots){await mkdir(screenshots,{recursive:true});await page.screenshot({path:screenshots+'/vehicles-desktop.png',fullPage:true});}
 await page.getByRole('button',{name:'Edit',exact:true}).click();await dialog().getByRole('button',{name:'Save changes',exact:true}).waitFor();await noOverlappingButtons();
 // A lifecycle confirmation opened inside an edit form must not submit that editor.
 await dialog().getByRole('button',{name:'Archive',exact:true}).click();await dialog().getByLabel('Reason').fill('TEST archive from edit form');await dialog().getByRole('button',{name:'Archive record',exact:true}).click();await dialog().getByRole('button',{name:'Done',exact:true}).click();
 assert.ok((await fixture.read('vehicles',fixture.vehicle)).archived_at);
 await page.goto(base+'/archives');await page.getByRole('button',{name:'Restore',exact:true}).click();await dialog().getByLabel('Reason').fill('TEST restore after editor');await dialog().getByRole('button',{name:'Restore record',exact:true}).click();await dialog().getByRole('button',{name:'Done',exact:true}).click();
 await page.goto(base+'/vehicles');await page.getByRole('heading',{name:'TEST-001',exact:true}).waitFor();
 await page.getByRole('button',{name:'Delete',exact:true}).click();await dialog().getByLabel('Reason').fill('TEST archive before deletion');await dialog().getByRole('button',{name:'Archive and continue',exact:true}).click();await dialog().getByLabel('Type DELETE to confirm').waitFor();await noOverlappingButtons();
 // Cancel the permanent step: archive must persist, original financial data remains.
 await dialog().getByRole('button',{name:'Cancel',exact:true}).click();await page.getByRole('heading',{name:'No vehicles found',exact:true}).waitFor();
 assert.ok((await fixture.read('vehicles',fixture.vehicle)).archived_at);assert.equal(Number(await fixture.scalar('select count(*) from public.trips')),1);
 await page.goto(base+'/archives');await page.getByRole('button',{name:'Restore',exact:true}).waitFor();await page.getByRole('button',{name:'Restore',exact:true}).click();await dialog().getByLabel('Reason').fill('TEST restore');await dialog().getByRole('button',{name:'Restore record',exact:true}).click();await dialog().getByRole('button',{name:'Done',exact:true}).click();
 await page.goto(base+'/vehicles');await page.getByRole('heading',{name:'TEST-001',exact:true}).waitFor();await page.setViewportSize({width:390,height:844});await noOverlappingButtons();
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth+1),'No page-wide overflow on mobile');
 if(screenshots)await page.screenshot({path:screenshots+'/vehicles-mobile.png',fullPage:true});
 await page.getByRole('button',{name:'Delete',exact:true}).click();await dialog().getByLabel('Reason').fill('TEST permanent delete');await dialog().getByRole('button',{name:'Archive and continue',exact:true}).click();await dialog().getByLabel('Type DELETE to confirm').fill('DELETE');await dialog().getByLabel('I reviewed the linked records and want to delete them.').check();await noOverlappingButtons();
 if(screenshots)await page.screenshot({path:screenshots+'/delete-mobile.png',fullPage:true});
 await dialog().getByRole('button',{name:'Delete permanently',exact:true}).click();await dialog().getByRole('button',{name:'Done',exact:true}).click();assert.equal(Number(await fixture.scalar('select count(*) from public.vehicles')),0);assert.equal(Number(await fixture.scalar('select count(*) from public.trips')),0);assert.equal(Number(await fixture.scalar('select count(*) from public.drivers')),1);
 await page.goto(base+'/periods');await page.getByRole('button',{name:'Delete',exact:true}).waitFor();await page.getByRole('button',{name:'Delete',exact:true}).click();await dialog().getByLabel('Reason').fill('TEST remove accounting period');await dialog().getByRole('button',{name:'Archive and continue',exact:true}).click();await dialog().getByLabel('Type DELETE to confirm').fill('DELETE');await dialog().getByLabel('I reviewed the linked records and want to delete them.').check();await dialog().getByRole('button',{name:'Delete permanently',exact:true}).click();await dialog().getByRole('button',{name:'Done',exact:true}).click();assert.equal(Number(await fixture.scalar('select count(*) from public.accounting_periods')),0);
 assert.deepEqual(errors,[]);await mkdir('verification/lifecycle',{recursive:true});await writeFile('verification/lifecycle/browser.json',JSON.stringify({status:'passed',viewports:['1440x1000','390x844'],checks:['Actual browser archive/cancel/restore/delete workflow against isolated PostgreSQL','Vehicle purge removes linked trip, retains unrelated driver','Accounting period deleted through its form','Edit form and record buttons do not overlap','No page-wide mobile overflow','No browser JavaScript errors'],externalServices:'Supabase Auth and Storage simulated; no hosted project used'},null,2));console.log('PASS lifecycle browser + PostgreSQL workflows and responsive layouts');
}catch(error){if(screenshots){await page.screenshot({path:screenshots+'/failure.png',fullPage:true});await writeFile(screenshots+'/failure.txt',await page.locator('body').innerText());}throw error;}
finally{await browser.close();await new Promise<void>(r=>server.close(()=>r()));await fixture.db.close();}
