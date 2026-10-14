import {Router,type Response} from 'express';
import {normalizeDecimalInput} from '../shared/numeric-input.js';
import {z} from 'zod';
import type {AuthContext} from './session.js';
import {AppError,dbError} from './errors.js';
import {parseFormula,numericKeys,numericTypes,type CustomField} from '../shared/custom-fields.js';
import {isFormResource} from '../shared/form-contract.js';
import {formDate} from './form-validation.js';
import {recordPrintHtml} from './record-print.js';

const resource=z.enum(['vehicles','drivers','trips','maintenance']);
const definition=z.object({resource,key:z.string().regex(/^cf_[a-z][a-z0-9_]{0,45}$/),label:z.string().trim().min(1).max(80),type:z.enum(['text','number','date','currency','percentage','dropdown','checkbox','formula']),default_value:z.union([z.string().max(1000),z.number().finite(),z.boolean(),z.null()]).default(null),required:z.boolean().default(false),display_order:z.number().int().min(0).max(999).default(0),show_form:z.boolean().default(true),show_card:z.boolean().default(true),show_table:z.boolean().default(true),show_print:z.boolean().default(true),hidden:z.boolean().default(false),archived:z.boolean().default(false),restricted:z.boolean().default(false),options:z.array(z.string().trim().min(1).max(80)).max(40).default([]),formula:z.string().max(500).default('')}).strict();
function auth(res:Response){return res.locals.auth as AuthContext;}
function admin(res:Response){if(!auth(res).access.permissions.includes('settings.manage'))throw new AppError(403,'FORBIDDEN','Administrator permission is required.');}
export function customFieldsRouter(){
 const r=Router();
 r.post('/drivers/:id/photo',async(req,res)=>{const q=z.object({attachment_id:z.string().uuid().nullable(),version:z.number().int().positive()}).strict().parse(req.body),a=auth(res);if(!a.access.permissions.includes('drivers.update')||!a.access.permissions.includes('drivers.documents.view'))throw new AppError(403,'FORBIDDEN','Driver photo permission is required.');const result=await a.db.rpc('set_driver_photo',{p_driver:z.string().uuid().parse(req.params.id),p_attachment:q.attachment_id,p_version:q.version});dbError(result.error);res.json({version:result.data});});
 r.get('/drivers/:id/photo-image',async(req,res)=>{const id=z.string().uuid().parse(req.params.id),a=auth(res);if(!a.access.permissions.includes('drivers.view')||!a.access.permissions.includes('drivers.documents.view'))throw new AppError(403,'FORBIDDEN','You cannot view this driver photo.');const driver=await a.db.from('drivers').select('photo_attachment_id').eq('id',id).maybeSingle();dbError(driver.error);if(!driver.data?.photo_attachment_id)throw new AppError(404,'NOT_FOUND','No driver photo is available.');const file=await a.db.from('attachments').select('bucket_id,object_path,mime_type').eq('id',driver.data.photo_attachment_id).eq('driver_id',id).eq('state','ready').maybeSingle();dbError(file.error);if(!file.data||!['image/jpeg','image/png'].includes(file.data.mime_type))throw new AppError(404,'NOT_FOUND','No driver photo is available.');const image=await a.db.storage.from(file.data.bucket_id).download(file.data.object_path);if(image.error||!image.data)throw new AppError(503,'PHOTO_UNAVAILABLE','The photo could not be loaded.');res.type(file.data.mime_type).set('Content-Disposition','inline').send(Buffer.from(await image.data.arrayBuffer()));});
 r.get('/custom-fields/:resource',async(req,res)=>{const q=resource.parse(req.params.resource);const archived=req.query.archived==='true';if(archived)admin(res);if(!auth(res).access.permissions.includes(q+'.view')&&!auth(res).access.permissions.includes('settings.manage'))throw new AppError(403,'FORBIDDEN','You cannot view these fields.');const result=await auth(res).db.rpc('custom_field_catalog',{p_resource:q,p_archived:archived});dbError(result.error);res.json(result.data);});
 r.post('/custom-fields',async(req,res)=>{
  admin(res);const input=z.object({id:z.string().uuid().nullable(),version:z.number().int().positive().nullable(),data:definition}).strict().parse(req.body);
  const data=input.data;let ast=null;
  if(['number','currency','percentage'].includes(data.type))data.default_value=normalizeDecimalInput(data.default_value) as string|number|boolean|null;
  if(data.type==='formula'){const current=await auth(res).db.rpc('custom_field_catalog',{p_resource:data.resource,p_archived:false});dbError(current.error);const keys=[...numericKeys(data.resource),...(current.data as CustomField[]).filter(f=>numericTypes.includes(f.type)).map(f=>f.key),data.key];try{ast=parseFormula(data.formula,keys).ast;}catch(error){throw new AppError(422,'INVALID_FORMULA',(error as Error).message);}}
  const result=await auth(res).db.rpc('save_custom_field',{p_id:input.id,p_version:input.version,p_data:{...data,ast}});dbError(result.error);res.json({id:result.data});
 });
 r.get('/print-settings',async(_req,res)=>{const result=await auth(res).db.rpc('print_templates');dbError(result.error);res.json(result.data);});
 r.post('/print-settings',async(req,res)=>{admin(res);const q=z.object({kind:z.enum(['vehicles','drivers','trips','maintenance','oil','office','monthly','combined','driver-details']),version:z.number().int().positive(),orientation:z.enum(['portrait','landscape']),signatures:z.array(z.string().trim().min(1).max(80)).min(1).max(6)}).strict().parse(req.body);const result=await auth(res).db.rpc('save_print_template',{p_kind:q.kind,p_version:q.version,p_orientation:q.orientation,p_signatures:q.signatures});dbError(result.error);res.json({ok:true});});
 r.get('/print/record/:resource/:id',async(req,res)=>{
  const kind=resource.parse(req.params.resource),id=z.string().uuid().parse(req.params.id),q=z.object({from:formDate,to:formDate}).parse(req.query);if(q.to<q.from)throw new AppError(422,'INVALID_FILTER','Choose a valid date range.');
  const a=auth(res);if(!a.access.permissions.includes(kind+'.view'))throw new AppError(403,'FORBIDDEN','You cannot print this record.');
  const record=await a.db.rpc('form_record',{p_resource:kind,p_id:id,p_from:q.from,p_to:q.to});dbError(record.error);
  if(kind==='drivers'){const history:Record<string,unknown>[]=[];let page=1,count=0;do{const result=await a.db.rpc('driver_vehicle_history',{p_driver:id,p_page:page,p_limit:100});dbError(result.error);history.push(...result.data.rows);count=result.data.count;page++;}while(history.length<count);record.data={...record.data,assignment_history:history};}
  const settings=await a.db.from('business_settings').select('*').single();dbError(settings.error);
  const templates=await a.db.rpc('print_templates');dbError(templates.error);
  res.json({html:recordPrintHtml(kind,record.data,{...settings.data,from:q.from,to:q.to},templates.data.find((s:{kind:string})=>s.kind===kind))});
 });
 r.post('/forms/:resource/:id/delete',async(req,res)=>{const kind=String(req.params.resource);if(!isFormResource(kind))throw new AppError(404,'NOT_FOUND','Unknown module.');const q=z.object({version:z.number().int().positive(),reason:z.string().trim().min(3).max(300)}).strict().parse(req.body);const needed=kind==='vehicles'?'vehicles.archive':kind==='drivers'?'drivers.archive':kind+'.delete_draft';if(!auth(res).access.permissions.includes(needed))throw new AppError(403,'FORBIDDEN','You cannot delete these records.');const result=await auth(res).db.rpc('archive_form_record',{p_resource:kind,p_id:z.string().uuid().parse(req.params.id),p_version:q.version,p_reason:q.reason});dbError(result.error);await auth(res).db.rpc('refresh_alerts_after_change');res.json({ok:true});});
 return r;
}
