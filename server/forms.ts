import {Router} from 'express';
import {z} from 'zod';
import {isFormResource} from '../shared/form-contract.js';
import {formDate,formEnvelope,validateForm} from './form-validation.js';
import type {AuthContext} from './session.js';
import {AppError,dbError} from './errors.js';
import {normalizeDecimalInput} from '../shared/numeric-input.js';
import type {CustomField} from '../shared/custom-fields.js';
export function formsRouter(){
 const r=Router();
 r.get('/forms/:resource',async(req,res)=>{
  const resource=String(req.params.resource);if(!isFormResource(resource))throw new AppError(404,'NOT_FOUND','Unknown form');
  const q=z.object({id:z.string().uuid().optional(),page:z.coerce.number().int().min(1).max(100000).default(1),search:z.string().max(100).default(''),from:formDate,to:formDate,status:z.string().max(30).default(''),sort:z.enum(['name','date','status']).default('name'),direction:z.enum(['asc','desc']).default('asc'),archived:z.enum(['true','false']).default('false')}).parse(req.query);
  if(q.to<q.from)throw new AppError(422,'INVALID_FILTER','Choose a valid date range.');
  const auth=res.locals.auth as AuthContext;if(!auth.access.permissions.includes(resource+'.view'))throw new AppError(403,'FORBIDDEN','You cannot view these records.');
  const result=await auth.db.rpc(q.id?'form_record':'form_register',q.id?{p_resource:resource,p_id:q.id,p_from:q.from,p_to:q.to}:{p_resource:resource,p_page:q.page,p_limit:25,p_search:q.search,p_from:q.from,p_to:q.to,p_status:q.status,p_sort:q.sort,p_direction:q.direction,p_include_archived:q.archived==='true'});dbError(result.error);res.json(result.data);
 });
 r.post('/forms/:resource',async(req,res)=>{
  const resource=String(req.params.resource);if(!isFormResource(resource))throw new AppError(404,'NOT_FOUND','Unknown form');const auth=res.locals.auth as AuthContext,input=formEnvelope.parse(req.body);
  const {custom_values,...base}=input.data;const data=validateForm(resource,base,auth.access.permissions);
  const custom=z.record(z.union([z.string().max(1000),z.number().finite(),z.boolean(),z.null()])).parse(custom_values??{});
  if(Object.keys(custom).length){
   const catalog=await auth.db.rpc('custom_field_catalog',{p_resource:resource,p_archived:false});dbError(catalog.error);
   for(const field of catalog.data as CustomField[])if(['number','currency','percentage'].includes(field.type)&&Object.hasOwn(custom,field.key))custom[field.key]=normalizeDecimalInput(custom[field.key]) as string|number|boolean|null;
  }
  const result=await auth.db.rpc('save_form',{p_resource:resource,p_id:input.id,p_version:input.version,p_data:{...data,custom_values:custom},p_identity_version:input.identity_version??null,p_assignment:input.assignment_id??null});dbError(result.error);await auth.db.rpc('refresh_alerts_after_change');res.json({id:result.data});
 });return r;
}
