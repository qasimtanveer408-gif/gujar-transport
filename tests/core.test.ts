import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {tripPreview,pooledEfficiency,businessDate,csv} from '../shared/calculations.js';
import {encrypt,decrypt,hash} from '../server/crypto.js';
import {validateDocument} from '../server/documents.js';
import {parseConfig,cookieName} from '../server/config.js';
test('PKR 44,000 profit and 7.91 km/L with decimal-safe rounding',()=>{assert.deepEqual(tripPreview('80000',['29000','3000','1200','2000','800'],'144844','145382','68'),{distance:'538.000',expenses:'36000.00',profit:'44000.00',efficiency:'7.91'});assert.equal(tripPreview('0',[],'0','100','0').efficiency,null);assert.throws(()=>tripPreview('0',[],'100','0','10'));});
test('pooled fuel uses matched totals and one basis',()=>{const r=pooledEfficiency([{distance:'100',litres:'10',basis:'measured'},{distance:'500',litres:'100',basis:'measured'},{distance:'999',litres:null,basis:'measured'},{distance:'999',litres:'10',basis:'purchase_estimate'}],'measured');assert.equal(r.efficiency,'5.45');assert.equal(r.count,2);});
test('Karachi midnight changes the business date',()=>{assert.equal(businessDate(new Date('2026-10-05T18:59:59Z')),'2026-10-05');assert.equal(businessDate(new Date('2026-10-05T19:00:00Z')),'2026-10-06');});
test('CSV neutralizes formulas and escapes embedded quotes',()=>{const out=csv([{a:'=1+1',b:'line,"quoted"'}],['a','b']);assert.match(out,/'=1\+1/);assert.match(out,/line,""quoted""/);});
test('encrypted credentials are bound to their session and reject tampering',()=>{const k=randomBytes(32).toString('hex'),h=hash('opaque'),e=encrypt(k,{a:'test only'},h);assert.deepEqual(decrypt(k,e,h),{a:'test only'});assert.throws(()=>decrypt(k,e,'wrong session'));const b=Buffer.from(e,'base64url');b[b.length-1]^=1;assert.throws(()=>decrypt(k,b.toString('base64url'),h));});
test('document signature and active PDF rejection',()=>{assert.throws(()=>validateDocument(Buffer.from('<script>bad()</script>'),'file.png','image/png'));assert.throws(()=>validateDocument(Buffer.from('%PDF-1.7 /JavaScript'),'file.pdf','application/pdf'));});
test('live environment requires explicit access, HTTPS and distinct cookie profile',()=>{const v={APP_ENV:'development',APP_URL:'http://localhost:5173',ALLOWED_ORIGINS:'http://localhost:5173',SUPABASE_URL:'https://example.supabase.co',SUPABASE_PUBLISHABLE_KEY:'test-public-value-only',SUPABASE_SECRET_KEY:'test-private-value-only',SESSION_ENCRYPTION_KEY:randomBytes(32).toString('hex')};assert.equal(cookieName(parseConfig(v)),'gbt_dev_session');assert.throws(()=>parseConfig({...v,ALLOW_LIVE_DATABASE_ACCESS:'true'}));assert.throws(()=>parseConfig({...v,APP_ENV:'production',NODE_ENV:'production'}));});

import {parseCsv} from '../shared/csv-import.js';
test('CSV parser preserves multiline quotes and rejects bad headers',()=>{assert.deepEqual(parseCsv('a,b\nName,"Line 1\nLine 2"'),[{a:'Name',b:'Line 1\nLine 2'}]);assert.throws(()=>parseCsv('a,a\nx,y'));assert.throws(()=>parseCsv('a\n"bad'));});
