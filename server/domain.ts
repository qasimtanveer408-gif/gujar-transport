import {Router,type Response} from 'express';
import {z} from 'zod';
import {modules} from '../shared/modules.js';
import {uuid,version,reason,money,numberString} from '../shared/validation.js';
import type {AuthContext} from './session.js';
import {AppError,dbError} from './errors.js';
function auth(res:Response){return res.locals.auth as AuthContext;}
function right(res:Response,p:string){if(!auth(res).access.permissions.includes(p))throw new AppError(403,'FORBIDDEN','You do not have permission for this action.');return auth(res);}
const date=z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(v=>{const d=new Date(v+'T00:00:00Z');return Number.isFinite(d.getTime())&&d.toISOString().slice(0,10)===v;},'Use a valid calendar date');const optionalDate=z.union([date,z.literal(''),z.null()]).optional();
const inputEnvelope=z.object({id:uuid.nullable().default(null),version:version.nullable().default(null),data:z.record(z.unknown()),lines:z.array(z.unknown()).max(100).nullable().optional(),oil:z.record(z.unknown()).nullable().optional(),key:uuid.optional()}).strict();
export function validateData(resource:string,input:Record<string,unknown>,editing=false){
 const spec=modules[resource];if(!spec)throw new AppError(404,'NOT_FOUND','Unknown module.');
 const shape:Record<string,z.ZodTypeAny>={};
 for(const f of spec.fields){let rule:z.ZodTypeAny=f.lookup?uuid:f.options?z.enum(f.options as [string,...string[]]):f.type==='decimal'?numberString:f.type==='date'?date:z.string().trim().max(f.type==='textarea'?1000:300);
  if(f.type==='decimal'&&['fare','amount','quoted_freight','commission'].includes(f.key))rule=money;
  if(!f.required)rule=z.union([rule,z.literal(''),z.null()]).optional();else if(!f.lookup&&!f.options&&f.type!=='date'&&f.type!=='decimal')rule=z.string().trim().min(1).max(300);
  if(editing&&resource==='trips'&&f.key==='fare')rule=rule.optional();
  shape[f.key]=rule;
 }
 return z.object(shape).strict().parse(input);
}
const lineInput=z.object({category:z.string().max(60),amount:money,business_date:date,description:z.string().max(300).default('')}).strict();
const itemInput=z.object({kind:z.enum(['Parts','Labour','Other']),description:z.string().min(1).max(300),amount:money,part_identifier:z.string().max(100).optional(),tyre_position:z.string().max(30).optional(),warranty_until:optionalDate}).strict();
const oilInput=z.object({specification:z.string().min(1).max(100),quantity_litres:numberString,previous_date:optionalDate,previous_odometer:z.union([numberString,z.literal('')]).optional(),next_due_odometer:z.union([numberString,z.literal('')]).optional()}).strict();
const extraPermissions:Record<string,string>={'loan-transactions':'loans.view',revenue:'reports.financial.view',expenses:'reports.financial.view',cash:'reports.financial.view'};
export function domainRouter(){
 const router=Router();
 router.get('/lookup',async(req,res)=>{
  const input=z.object({resource:z.enum(['vehicles','drivers','companies','trips','roles']),search:z.string().max(100).default(''),id:uuid.optional()}).parse(req.query);
  const tables={vehicles:['vehicles','registration','vehicles.view'],drivers:['drivers','full_name','drivers.view'],companies:['companies','name','vehicles.view'],trips:['trips','trip_number','trips.view'],roles:['roles','name','roles.view']} as const;
  const [table,label,p]=tables[input.resource];right(res,p);let query=auth(res).db.from(table).select(`id,${label}`).order(label).limit(25);if(input.id)query=query.eq('id',input.id);else if(input.search)query=query.ilike(label,`%${input.search.replace(/[%_\\]/g,'\\$&')}%`);const result=await query;dbError(result.error);res.json((result.data??[]).map(r=>({value:r.id,label:(r as unknown as Record<string,unknown>)[label]})));
 });
 router.get('/records/:resource',async(req,res)=>{
  const resource=String(req.params.resource),spec=modules[resource];const p=spec?.permission??extraPermissions[resource];if(!p)throw new AppError(404,'NOT_FOUND','Unknown module.');right(res,p);
  const q=z.object({page:z.coerce.number().int().min(1).max(100000).default(1),search:z.string().max(100).default(''),from:date.optional(),to:date.optional(),vehicle:uuid.optional(),driver:uuid.optional()}).parse(req.query);
  const result=await auth(res).db.rpc('list_records',{p_resource:resource,p_search:q.search,p_page:q.page,p_limit:25,p_from:q.from??null,p_to:q.to??null,p_vehicle:q.vehicle??null,p_driver:q.driver??null});dbError(result.error);res.json(result.data);
 });
 router.post('/records/:resource',async(req,res)=>{
  const resource=String(req.params.resource),spec=modules[resource];if(!spec?.createPermission)throw new AppError(404,'NOT_FOUND','Unknown module.');const input=inputEnvelope.parse(req.body);const permission=input.id?spec.editPermission:spec.createPermission;
  if(resource==='trips'&&input.id&&auth(res).access.permissions.includes('trips.update_own_draft')){/* Database checks ownership. */}else if(permission)right(res,permission);else throw new AppError(403,'IMMUTABLE','This record cannot be edited.');
  const data=validateData(resource,input.data,Boolean(input.id));let rpc='';let args:Record<string,unknown>={p_id:input.id,p_version:input.version,p_data:data};
  switch(resource){
   case 'vehicles':rpc='save_vehicle';break;
   case 'companies':rpc='save_company';args={p_name:data.name};break;
   case 'drivers':rpc='save_driver';break;
   case 'trips':rpc='save_trip';args.p_lines=input.lines===null?null:z.array(lineInput).parse(input.lines??[]);break;
   case 'maintenance':rpc='save_maintenance';args.p_items=z.array(itemInput).parse(input.lines??[]);args.p_oil=input.oil?oilInput.parse(input.oil):null;break;
   case 'office-expenses':rpc='save_office_expense';break;
   case 'bookings':rpc='save_booking';args={p_data:data};break;
   case 'periods':rpc='create_period';args={p_name:data.name,p_start:data.start_date,p_end:data.end_date};break;
   case 'loans':rpc='loan_transaction';args={p_loan:null,p_driver:data.driver_id,p_date:data.business_date,p_kind:data.kind,p_amount:data.amount,p_reference:data.reference,p_due:data.due_date||null,p_key:uuid.parse(input.key)};break;
   case 'earnings':rpc='accrue_earning';args={p_driver:data.driver_id,p_date:data.business_date,p_kind:data.kind,p_amount:data.amount,p_rule:data.rule_snapshot,p_key:uuid.parse(input.key)};break;
   case 'payments':rpc='settle_driver_payment';args={p_driver:data.driver_id,p_date:data.business_date,p_reference:data.reference,p_allocations:z.array(z.object({earning_id:uuid,amount:money}).strict()).min(1).max(100).parse(input.lines),p_key:uuid.parse(input.key)};break;
   default:throw new AppError(404,'NOT_FOUND','Unknown module.');
  }
  const result=await auth(res).db.rpc(rpc,args);dbError(result.error);const refreshed=await auth(res).db.rpc('refresh_alerts_after_change');if(refreshed.error)res.setHeader('X-Alerts-Pending','true');res.status(input.id?200:201).json({id:result.data});
 });
 router.post('/records/:resource/:id/action',async(req,res)=>{
  const resource=String(req.params.resource),id=uuid.parse(req.params.id);const input=z.object({action:z.string().max(30),version,reason:z.string().max(300).default(''),key:uuid}).strict().parse(req.body);let rpc='';let args:Record<string,unknown>={p_id:id,p_version:input.version,p_key:input.key};
  if(resource==='trips'&&input.action==='complete'){rpc='complete_form_trip';args={p_id:id,p_version:input.version};}
  else if(resource==='trips'&&['submit','approve','reject','void'].includes(input.action)){right(res,'trips.'+input.action);rpc='trip_action';args={p_trip:id,p_action:input.action,p_version:input.version,p_reason:input.reason,p_key:input.key};}
  else if(resource==='office-expenses'&&['approve','void'].includes(input.action)){right(res,'expenses.'+input.action);rpc='expense_action';args.p_action=input.action;args.p_reason=input.reason;}
  else if(resource==='maintenance'&&input.action==='approve'){right(res,'maintenance.approve');rpc='approve_maintenance';}
  else if(resource==='bookings'&&input.action==='approve'){right(res,'bookings.approve');rpc='approve_booking';}
  else if(resource==='periods'&&['close','reopen'].includes(input.action)){right(res,'accounts.'+input.action);rpc=input.action+'_period';args={p_period:id,p_version:input.version,p_reason:reason.parse(input.reason)};}
  else throw new AppError(422,'INVALID_ACTION','Action is not available.');
  const result=await auth(res).db.rpc(rpc,args);dbError(result.error);const refreshed=await auth(res).db.rpc('refresh_alerts_after_change');if(refreshed.error)res.setHeader('X-Alerts-Pending','true');res.json({ok:true});
 });
 router.get('/trips/:id/finance',async(req,res)=>{right(res,'trips.finance.view');const result=await auth(res).db.rpc('trip_finance',{p_trip:uuid.parse(req.params.id)});dbError(result.error);res.json(result.data);});
 router.get('/maintenance/:id/details',async(req,res)=>{right(res,'maintenance.view');const id=uuid.parse(req.params.id);const items=await auth(res).db.from('maintenance_items').select('id,kind,description,amount::text,part_identifier,tyre_position,warranty_until').eq('maintenance_id',id);dbError(items.error);const oil=await auth(res).db.from('oil_changes').select('specification,quantity_litres::text,previous_date,previous_odometer::text,next_due_odometer::text').eq('maintenance_id',id).maybeSingle();dbError(oil.error);res.json({items:items.data,oil:oil.data});});
 router.get('/drivers/:id/statement',async(req,res)=>{const result=await auth(res).db.rpc('driver_statement',{p_driver:uuid.parse(req.params.id)});dbError(result.error);res.json(result.data);});
 router.get('/drivers/:id/identity',async(req,res)=>{right(res,'drivers.identity.view');const result=await auth(res).db.from('driver_identity_details').select('father_name,cnic,licence_number,address,emergency_contact,version').eq('driver_id',uuid.parse(req.params.id)).maybeSingle();dbError(result.error);res.json(result.data);});
 router.post('/drivers/:id/identity',async(req,res)=>{right(res,'drivers.identity.manage');const {version:v,...data}=z.object({version:version.nullable(),father_name:z.string().max(120),cnic:z.string().max(30),licence_number:z.string().max(50),address:z.string().max(300),emergency_contact:z.string().max(100)}).strict().parse(req.body);const result=await auth(res).db.rpc('save_driver_identity',{p_driver:uuid.parse(req.params.id),p_version:v,p_data:data});dbError(result.error);const refreshed=await auth(res).db.rpc('refresh_alerts_after_change');if(refreshed.error)res.setHeader('X-Alerts-Pending','true');res.json({ok:true});});
 router.get('/drivers/:id/duty',async(req,res)=>{right(res,'drivers.view');const result=await auth(res).db.from('driver_duty_sessions').select('id,started_at,ended_at').eq('driver_id',uuid.parse(req.params.id)).order('started_at',{ascending:false}).limit(50);dbError(result.error);res.json(result.data);});
 router.post('/drivers/:id/duty',async(req,res)=>{right(res,'duty.manage');const data=z.object({on_duty:z.boolean()}).strict().parse(req.body);const result=await auth(res).db.rpc('set_driver_duty',{p_driver:uuid.parse(req.params.id),p_on_duty:data.on_duty});dbError(result.error);const refreshed=await auth(res).db.rpc('refresh_alerts_after_change');if(refreshed.error)res.setHeader('X-Alerts-Pending','true');res.json({ok:true});});
 router.get('/vehicles/:id/assignments',async(req,res)=>{right(res,'vehicles.view');const result=await auth(res).db.from('vehicle_driver_assignments').select('id,driver_id,started_at,ended_at,remarks').eq('vehicle_id',uuid.parse(req.params.id)).order('started_at',{ascending:false}).limit(100);dbError(result.error);res.json(result.data);});
 router.post('/vehicles/:id/assignment',async(req,res)=>{right(res,'assignments.manage');const data=z.object({driver_id:uuid.nullable(),reason}).strict().parse(req.body);const result=await auth(res).db.rpc('assign_driver',{p_vehicle:uuid.parse(req.params.id),p_driver:data.driver_id,p_reason:data.reason});dbError(result.error);const refreshed=await auth(res).db.rpc('refresh_alerts_after_change');if(refreshed.error)res.setHeader('X-Alerts-Pending','true');res.json({ok:true});});
 router.post('/users/:id/vehicle-scope',async(req,res)=>{right(res,'users.roles');const data=z.object({vehicle_id:uuid,enabled:z.boolean()}).strict().parse(req.body);const result=await auth(res).db.rpc('set_vehicle_scope',{p_user:uuid.parse(req.params.id),p_vehicle:data.vehicle_id,p_enabled:data.enabled});dbError(result.error);const refreshed=await auth(res).db.rpc('refresh_alerts_after_change');if(refreshed.error)res.setHeader('X-Alerts-Pending','true');res.json({ok:true});});
 router.get('/users/:id/vehicle-scopes',async(req,res)=>{right(res,'users.view');const result=await auth(res).db.from('user_vehicle_scopes').select('vehicle_id').eq('user_id',uuid.parse(req.params.id));dbError(result.error);res.json(result.data);});
 router.post('/loans/:id/repay',async(req,res)=>{right(res,'loans.repay');const input=z.object({driver_id:uuid,business_date:date,amount:money,reference:z.string().min(2).max(100),key:uuid}).strict().parse(req.body);const result=await auth(res).db.rpc('loan_transaction',{p_loan:uuid.parse(req.params.id),p_driver:input.driver_id,p_date:input.business_date,p_kind:'Repayment',p_amount:input.amount,p_reference:input.reference,p_due:null,p_key:input.key});dbError(result.error);const refreshed=await auth(res).db.rpc('refresh_alerts_after_change');if(refreshed.error)res.setHeader('X-Alerts-Pending','true');res.json({ok:true});});
 router.get('/dashboard',async(req,res)=>{const input=z.object({from:date,to:date,basis:z.enum(['measured','tank_reconciled','purchase_estimate']).default('measured'),min_distance:z.coerce.number().nonnegative().max(1000000).default(100)}).parse(req.query);const result=await auth(res).db.rpc('dashboard',{p_from:input.from,p_to:input.to,p_basis:input.basis,p_min_distance:input.min_distance});dbError(result.error);res.json(result.data);});
 return router;
}
