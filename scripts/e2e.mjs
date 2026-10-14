import {chromium} from 'playwright';
import {createServer} from 'node:http';
import {readFile,stat,mkdir} from 'node:fs/promises';
import {resolve,extname} from 'node:path';
import assert from 'node:assert/strict';
// Fixtures exist only in this test browser. Production has no mock-login path.
const server=createServer(async(req,res)=>{
 let path=resolve('dist/client','.'+new URL(req.url,'http://localhost').pathname);
 if(!path.startsWith(resolve('dist/client')+'/'))path=resolve('dist/client/index.html');
 try{if(!(await stat(path)).isFile())throw new Error();}catch{path=resolve('dist/client/index.html');}
 res.setHeader('Content-Type',({'.html':'text/html','.js':'application/javascript','.css':'text/css','.png':'image/png','.woff2':'font/woff2','.woff':'font/woff'})[extname(path)]??'application/octet-stream');
 res.end(await readFile(path));
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try{
 browser=await chromium.launch({...(process.env.PLAYWRIGHT_EXECUTABLE_PATH?{executablePath:process.env.PLAYWRIGHT_EXECUTABLE_PATH}:{}),args:['--no-sandbox','--disable-dev-shm-usage','--disable-gpu','--no-zygote','--single-process']});
 await mkdir('playwright-artifacts',{recursive:true});
 const context=await browser.newContext({viewport:{width:1440,height:1000}}),page=await context.newPage(),errors=[],requests=[];
 page.on('pageerror',e=>errors.push(e.message));let signed=false,pending=false;
 const permissions=['vehicles.view','vehicles.create','drivers.view','trips.view','reports.financial.view','reports.export','imports.manage','settings.manage'];
 const base=`http://127.0.0.1:${server.address().port}`;
 await context.route('**/api/**',async route=>{
  const p=new URL(route.request().url()).pathname;requests.push(p);let body={},status=200;
  if(p==='/api/notifications')body={rows:[],count:0,page:1,unread_count:0};
  else if(p==='/api/auth/csrf')body={csrf:'ui-test'};
  else if(p==='/api/auth/login'){
   const input=route.request().postDataJSON();
   if(input.email==='owner@example.test'&&input.password==='test-only-password'){signed=true;body={csrf:'ui-test'};}
   else{status=401;body={error:{message:'Email or password is incorrect.'}};}
  }
  else if(p==='/api/auth/logout')signed=false;
  else if(p==='/api/auth/me'){
   status=signed?200:401;body=signed?{user:{id:'test',display_name:'System Owner',email:'owner@example.test'},permissions:pending?[]:permissions,roles:pending?['Pending Access']:['Super Admin'],environment:'development',csrf:'ui-test'}:{error:{message:'Sign in'}};
  }
  else if(p==='/api/settings')body={refresh_seconds:60};
  else if(p==='/api/dashboard')body={today:'2026-10-11',refreshed_at:'2026-10-11T08:00:00Z',vehicles:0,on_duty:0,today_trips:0,vehicle_status:{},trip_series:[],fuel_ranking:[],finance:{revenue:'0.00',expenses:'0.00',operating_profit:'0.00',pending_trips:0,series:[],vehicle_ranking:[],unallocated_overhead:'0.00'}};
  else if(p.startsWith('/api/records/')||p.startsWith('/api/forms/'))body={rows:[],count:0,page:1};
  else if(['/api/lookup','/api/print-settings','/api/custom-fields/vehicles','/api/custom-fields/drivers','/api/custom-fields/trips','/api/custom-fields/maintenance','/api/alerts','/api/alert-rules','/api/imports','/api/routes'].includes(p))body=[];
  else{status=404;body={error:{message:'Missing UI fixture'}};}
  await route.fulfill({status,contentType:'application/json',body:JSON.stringify(body)});
 });
 await page.goto(base);await page.getByRole('heading',{name:'Welcome back'}).waitFor();
 assert.equal(await page.getByRole('button',{name:'Sign in with Google',exact:true}).count(),0);
 await page.screenshot({path:'playwright-artifacts/login-desktop.png',fullPage:true});
 await page.getByLabel('Email address').fill('owner@example.test');
 await page.getByLabel('Password',{exact:true}).fill('incorrect-password');
 await page.getByRole('button',{name:'Sign in',exact:true}).click();
 await page.getByRole('alert').filter({hasText:'Email or password is incorrect.'}).waitFor();
 await page.getByLabel('Password',{exact:true}).fill('test-only-password');
 await page.getByRole('button',{name:'Show password',exact:true}).click();
 assert.equal(await page.getByLabel('Password',{exact:true}).getAttribute('type'),'text');
 await page.getByRole('button',{name:'Hide password',exact:true}).click();
 await page.getByRole('button',{name:'Sign in',exact:true}).click();
 await page.getByRole('heading',{name:'WELCOME SIR ATTIQ'}).waitFor();
 await page.screenshot({path:'playwright-artifacts/dashboard-desktop.png',fullPage:true});
 await page.getByRole('button',{name:'Vehicles',exact:true}).click();
 await page.getByRole('heading',{name:'Vehicles',exact:true}).waitFor();
 await page.getByRole('button',{name:'Add vehicle',exact:true}).click();
 await page.getByRole('dialog').waitFor();await page.getByLabel('Vehicle number',{exact:true}).fill('TEST-001');
 await page.screenshot({path:'playwright-artifacts/vehicle-dialog.png',fullPage:true});
 await page.getByRole('button',{name:'Cancel',exact:true}).click();
 await page.reload();await page.getByRole('heading',{name:'Vehicles',exact:true}).waitFor();
 await page.setViewportSize({width:390,height:844});await page.goto(base);
 await page.getByRole('heading',{name:'WELCOME SIR ATTIQ'}).waitFor();
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Mobile overflow');
 await page.screenshot({path:'playwright-artifacts/dashboard-mobile.png',fullPage:true});
 await page.getByRole('button',{name:'Open navigation'}).click();
 await page.getByRole('button',{name:'CSV imports',exact:true}).click();
 await page.getByRole('heading',{name:'CSV imports',exact:true}).waitFor();
 await page.screenshot({path:'playwright-artifacts/imports-mobile.png',fullPage:true});
 await page.getByRole('button',{name:'Sign out',exact:true}).click();
 await page.getByRole('heading',{name:'Welcome back'}).waitFor();
 await page.screenshot({path:'playwright-artifacts/login-mobile.png',fullPage:true});
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 pending=true;await page.getByLabel('Email address').fill('owner@example.test');
 await page.getByLabel('Password',{exact:true}).fill('test-only-password');
 await page.getByRole('button',{name:'Sign in',exact:true}).click();
 await page.getByRole('heading',{name:'Your account is created'}).waitFor();
 assert.equal(await page.getByRole('button',{name:'Vehicles',exact:true}).count(),0);
 await page.getByRole('button',{name:'Sign out',exact:true}).click();
 await page.getByRole('heading',{name:'Welcome back'}).waitFor();
 assert.equal(requests.some(p=>p.includes('/auth/google')||p==='/api/auth/providers'),false,'Removed login routes are never requested');
 assert.deepEqual(errors,[]);
 console.log('PASS: password login/error/show-hide/logout, retained session, pending-access restrictions, nested refresh, mobile navigation and no horizontal overflow or browser exceptions. Auth is mocked.');
}finally{await browser?.close();await new Promise(r=>server.close(r));}
