import {enhancementsRouter} from './enhancements.js';
import {referenceReportsRouter} from './reference-reports.js';
import {customFieldsRouter} from './custom-fields.js';
import {formsRouter} from './forms.js';
import express,{type Request,type Response,type NextFunction} from 'express';
import helmet from 'helmet';
import {parse as parseCookie,serialize} from 'cookie';
import {randomUUID} from 'node:crypto';
import {resolve} from 'node:path';
import {existsSync} from 'node:fs';
import {ZodError,z} from 'zod';
import {type Config,cookieName} from './config.js';
import {createSessionService,type SessionService,type AuthContext} from './session.js';
import {csrfFor,hash,same,token} from './crypto.js';
import {privilegedClient,type Client} from './supabase.js';
import {AppError,dbError} from './errors.js';
import {SESSION_TTL_SECONDS} from '../shared/session-policy.js';
import {finishProvision,type ProvisionTask} from './provision.js';
import {operationsRouter} from './operations.js';
import {reportsRouter} from './reports.js';
import {documentsRouter} from './documents.js';
import {domainRouter} from './domain.js';
import {accessInput,loginInput,roleInput,settingsInput,userInput,uuid} from '../shared/validation.js';

export function requireRight(res:Response,permission:string){const context=res.locals.auth as AuthContext;if(!context.access.permissions.includes(permission))throw new AppError(403,'FORBIDDEN','You do not have permission for this action.');return context;}
export function context(res:Response){return res.locals.auth as AuthContext;}
export function cookies(c:Config,raw:string,maxAge=SESSION_TTL_SECONDS){return serialize(cookieName(c),raw,{httpOnly:true,secure:c.APP_ENV!=='development'||c.APP_URL.startsWith('https:'),sameSite:'strict',path:'/',maxAge});}
export const pageQuery=z.object({page:z.coerce.number().int().min(1).max(100000).default(1),search:z.string().max(100).default('')});
export function createApp(c:Config,options:{sessions?:SessionService;admin?:Client;staticDir?:string}={}){
 const app=express(), sessions=options.sessions??createSessionService(c),admin=options.admin??privilegedClient(c);
 const origins=new Set(c.ALLOWED_ORIGINS.split(',').map(s=>s.trim()));const preCookie=c.APP_ENV==='development'?'gbt_dev_csrf':'__Host-gbt_csrf';
 app.disable('x-powered-by');app.set('trust proxy',c.TRUST_PROXY_HOPS);
 app.use(helmet({contentSecurityPolicy:{directives:{defaultSrc:["'self'"],scriptSrc:["'self'"],styleSrc:["'self'","'unsafe-inline'"],imgSrc:["'self'","data:"],fontSrc:["'self'"],connectSrc:["'self'"],objectSrc:["'none'"],frameAncestors:["'none'"],upgradeInsecureRequests:c.APP_ENV==='development'?null:[]}},strictTransportSecurity:c.APP_ENV==='development'?false:undefined}));
 app.use((req,res,next)=>{res.locals.requestId=randomUUID();res.setHeader('X-Request-ID',res.locals.requestId);if(req.path.startsWith('/api')){res.setHeader('Cache-Control','no-store');res.setHeader('X-Robots-Tag','noindex, nofollow');}next();});
 app.use(express.json({limit:'256kb',strict:true}));
 app.use('/api',(req,res,next)=>{
  const origin=req.get('origin');
  if(origin&&!origins.has(origin))return next(new AppError(403,'ORIGIN_DENIED','This website origin is not allowed.'));
  if(!['GET','HEAD','OPTIONS'].includes(req.method)&&(!origin||!origins.has(origin)))return next(new AppError(403,'ORIGIN_REQUIRED','A matching website origin is required.'));
  if(req.method==='OPTIONS'){if(origin)res.setHeader('Access-Control-Allow-Origin',origin);res.setHeader('Vary','Origin');res.setHeader('Access-Control-Allow-Credentials','true');res.setHeader('Access-Control-Allow-Headers','Content-Type, X-CSRF-Token');res.setHeader('Access-Control-Allow-Methods','GET, POST, PATCH');res.sendStatus(204);return;}
  if(origin){res.setHeader('Access-Control-Allow-Origin',origin);res.setHeader('Access-Control-Allow-Credentials','true');res.setHeader('Vary','Origin');}
  next();
 });
 // This is a private staff application; never advertise customer records to crawlers.
 app.get('/robots.txt',(_req,res)=>res.type('text/plain').send(`User-agent: *\nDisallow: /\nSitemap: ${new URL('/sitemap.xml',c.APP_URL).href}\n`));
 app.get('/sitemap.xml',(_req,res)=>res.type('application/xml').send('<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"></urlset>'));
 app.get('/api/health',(_req,res)=>res.json({status:'ok',application:'Gujjar Brother Transport',environment:c.APP_ENV,serviceConnectivity:'not_checked'}));
 app.get('/api/auth/csrf',async(req,res)=>{
  const parsed=parseCookie(req.headers.cookie??'');const raw=parsed[cookieName(c)];
  if(raw){try{const auth=await sessions.authenticate(raw);res.json({csrf:auth.csrf});return;}catch(error){if(!(error instanceof AppError)||![401,403].includes(error.status))throw error;}}
  const random=token();const signed=random+'.'+csrfFor(c.SESSION_ENCRYPTION_KEY,'login:'+random);
  res.setHeader('Set-Cookie',serialize(preCookie,signed,{httpOnly:true,secure:c.APP_ENV!=='development'||c.APP_URL.startsWith('https:'),sameSite:'strict',path:'/',maxAge:600}));res.json({csrf:signed});
 });
 app.post('/api/auth/login',async(req,res)=>{
  const saved=parseCookie(req.headers.cookie??'')[preCookie]??'', supplied=req.get('x-csrf-token')??'';
  const [random,signature]=saved.split('.');
  if(!random||!signature||!same(saved,supplied)||!same(signature,csrfFor(c.SESSION_ENCRYPTION_KEY,'login:'+random)))throw new AppError(403,'CSRF_FAILED','Refresh the page and try again.');
  const input=loginInput.parse(req.body);
  for(const [key,limit,seconds] of [[hash('ip:'+req.ip),30,900],[hash('email:'+input.email.toLowerCase()),8,900]] as const){const limited=await admin.rpc('server_throttle',{p_key:key,p_limit:limit,p_seconds:seconds});dbError(limited.error);if(!limited.data)throw new AppError(429,'RATE_LIMIT','Too many sign-in attempts. Try again in 15 minutes.');}
  const result=await sessions.login(input.email,input.password);res.setHeader('Set-Cookie',[cookies(c,result.raw),serialize(preCookie,'',{httpOnly:true,secure:c.APP_ENV!=='development'||c.APP_URL.startsWith('https:'),sameSite:'strict',path:'/',maxAge:0})]);res.json({csrf:result.csrf});
 });
 const secure=express.Router();
 secure.use(async(req,res,next)=>{
  try{res.locals.auth=await sessions.authenticate(parseCookie(req.headers.cookie??'')[cookieName(c)]??'');}catch(error){if(error instanceof AppError&&error.status===401)res.setHeader('Set-Cookie',cookies(c,'',0));throw error;}
  const auth=context(res);
  if(!auth.access.permissions.length&&!['/auth/me','/auth/logout','/auth/logout-all'].includes(req.path))throw new AppError(403,'ACCESS_PENDING','Your account is created. Ask an administrator to assign your role.');
  if(!['GET','HEAD'].includes(req.method)&&!same(req.get('x-csrf-token')??'',auth.csrf))throw new AppError(403,'CSRF_FAILED','Refresh the page and try again.');
  const limited=await admin.rpc('server_throttle',{p_key:'api:'+auth.access.user.id,p_limit:240,p_seconds:60});dbError(limited.error);if(!limited.data)throw new AppError(429,'RATE_LIMIT','Please wait a minute before retrying.');
  next();
 });
 secure.get('/auth/me',(_req,res)=>res.json({...context(res).access,csrf:context(res).csrf,environment:c.APP_ENV,session_expires_at:context(res).session?.expires_at??null}));
 secure.post('/auth/logout',async(_req,res)=>{const result=await sessions.logout(context(res));res.setHeader('Set-Cookie',cookies(c,'',0));res.json({ok:true,...result});});
 secure.post('/auth/logout-all',async(_req,res)=>{const result=await context(res).db.rpc('revoke_my_sessions');dbError(result.error);res.setHeader('Set-Cookie',cookies(c,'',0));res.json({ok:true});});
 secure.get('/connection',async(_req,res)=>{const result=await context(res).db.rpc('my_access');dbError(result.error);res.json({database:'connected',authentication:'verified',time:new Date().toISOString()});});
 secure.get('/settings',async(_req,res)=>{const result=await context(res).db.from('business_settings').select('business_name,contact_email,phone_1,phone_2,phone_3,address,currency,timezone,period_start_day,period_confirmed,refresh_seconds,version').single();dbError(result.error);res.json(result.data);});
 secure.patch('/settings',async(req,res)=>{const auth=requireRight(res,'settings.manage');const {version,...data}=settingsInput.parse(req.body);const result=await auth.db.rpc('save_business_settings',{p_data:data,p_version:version});dbError(result.error);res.json({ok:true});});
 secure.get('/users',async(req,res)=>{const auth=requireRight(res,'users.view');const {page,search}=pageQuery.parse(req.query);let query=auth.db.from('app_users').select('id,email,display_name,active,version,created_at,user_roles(role_id)',{count:'exact'}).order('created_at',{ascending:false});if(search)query=query.ilike('display_name',`%${search.replace(/[%_\\]/g,'\\$&')}%`);const result=await query.range((page-1)*25,page*25-1);dbError(result.error);res.json({rows:result.data,count:result.count,page});});
 secure.post('/users',async(req,res)=>{const auth=requireRight(res,'users.create');const input=userInput.parse(req.body);const begun=await auth.db.rpc('begin_user_provisioning',{p_email:input.email,p_name:input.display_name,p_role:input.role_id});dbError(begun.error);const id=await finishProvision(admin,begun.data as ProvisionTask,input.password);res.status(201).json({id});});
 secure.patch('/users/:id',async(req,res)=>{const auth=requireRight(res,'users.disable');const input=accessInput.parse(req.body);const result=await auth.db.rpc('set_user_access',{p_user:uuid.parse(req.params.id),p_active:input.active,p_role:input.role_id,p_version:input.version,p_reason:input.reason});dbError(result.error);res.json({ok:true});});
 secure.get('/roles',async(_req,res)=>{const auth=context(res);if(!['roles.view','users.view','users.create'].some(p=>auth.access.permissions.includes(p)))throw new AppError(403,'FORBIDDEN','Permission denied.');const result=await auth.db.from('roles').select('id,name,reserved,version').order('name');dbError(result.error);res.json(result.data);});
 secure.get('/permissions',async(_req,res)=>{const auth=requireRight(res,'roles.view');const result=await auth.db.from('permissions').select('code,description').order('code');dbError(result.error);res.json(result.data);});
 secure.get('/roles/:id/grants',async(req,res)=>{const auth=requireRight(res,'roles.view');const result=await auth.db.from('role_permissions').select('permission_code,scope').eq('role_id',uuid.parse(req.params.id));dbError(result.error);res.json(result.data);});
 secure.post('/roles',async(req,res)=>{const auth=requireRight(res,'roles.manage');const input=roleInput.parse(req.body);const result=await auth.db.rpc('save_role',{p_id:input.id,p_name:input.name,p_version:input.version,p_grants:input.grants});dbError(result.error);res.json({id:result.data});});
 secure.get('/audit',async(req,res)=>{const auth=requireRight(res,'audit.view');const {page,search}=pageQuery.parse(req.query);let query=auth.db.from('audit_logs').select('id,actor_id,action,record_type,record_id,summary,created_at',{count:'exact'}).order('id',{ascending:false});if(search)query=query.ilike('action',`%${search.replace(/[%_\\]/g,'\\$&')}%`);const result=await query.range((page-1)*25,page*25-1);dbError(result.error);res.json({rows:result.data,count:result.count,page});});
 secure.use(customFieldsRouter());
 secure.use(formsRouter());
 secure.use(domainRouter());
 secure.use(documentsRouter());
 secure.use(reportsRouter());
 secure.use(referenceReportsRouter());
 secure.use(operationsRouter());
 secure.use(enhancementsRouter());
 app.use('/api',secure);
 app.use('/api',(_req,res)=>res.status(404).json({error:{code:'NOT_FOUND',message:'API route not found.',requestId:res.locals.requestId}}));
 const staticDir=options.staticDir??resolve(process.cwd(),'dist/client');
 if(existsSync(resolve(staticDir,'index.html'))){
  app.use(express.static(staticDir,{index:false,dotfiles:'deny',maxAge:0,setHeaders:(res,file)=>{
   const name=file.replaceAll('\\','/');
   // Only Vite fingerprinted assets are immutable. Brand/vendor files revalidate.
   res.setHeader('Cache-Control',name.includes('/assets/')?'public, max-age=31536000, immutable':name.endsWith('.html')?'no-cache':'public, max-age=3600, must-revalidate');
   if(name.endsWith('.html'))res.setHeader('X-Robots-Tag','noindex, nofollow');
  }}));
  app.get('/{*path}',(_req,res)=>{res.setHeader('Cache-Control','no-cache');res.setHeader('X-Robots-Tag','noindex, nofollow');res.sendFile(resolve(staticDir,'index.html'));});
 }
 app.use((error:unknown,_req:Request,res:Response,_next:NextFunction)=>{
  const isValidation=error instanceof ZodError;
  const status=isValidation?422:error instanceof AppError?error.status:400=== (error as {status?:number})?.status?400:500;
  const code=isValidation?'VALIDATION_ERROR':error instanceof AppError?error.code:status===400?'BAD_REQUEST':'INTERNAL_ERROR';
  const message=isValidation?error.issues.map(i=>`${i.path.join('.')}: ${i.message}`).join('; '):error instanceof AppError?error.message:'The request could not be completed.';
  // Never log request bodies, credentials, headers, query strings, or raw provider errors.
  if(status>=500)console.error(JSON.stringify({requestId:res.locals.requestId,code,status}));
  res.status(status).json({error:{code,message,requestId:res.locals.requestId}});
 });
 return app;
}
