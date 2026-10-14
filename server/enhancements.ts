import {Router} from 'express';
import {z} from 'zod';
import {formDate} from './form-validation.js';
import type {AuthContext} from './session.js';
import {AppError,dbError} from './errors.js';
export function enhancementsRouter(){
 const r=Router();
 r.get('/drivers/:id/history',async(req,res)=>{
  const q=z.object({page:z.coerce.number().int().min(1).max(100000).default(1)}).parse(req.query),a=res.locals.auth as AuthContext;
  const result=await a.db.rpc('driver_vehicle_history',{p_driver:z.string().uuid().parse(req.params.id),p_page:q.page,p_limit:25});dbError(result.error);res.json(result.data);
 });
 r.post('/drivers/:id/transfer',async(req,res)=>{
  const q=z.object({vehicle_id:z.string().uuid().nullable(),assignment_id:z.string().uuid().nullable(),assigned_date:formDate,reason:z.string().trim().max(300).default('')}).strict().parse(req.body),a=res.locals.auth as AuthContext;
  if(!a.access.permissions.includes('assignments.manage'))throw new AppError(403,'FORBIDDEN','Vehicle assignment permission is required.');
  const result=await a.db.rpc('transfer_driver',{p_driver:z.string().uuid().parse(req.params.id),p_vehicle:q.vehicle_id,p_date:q.assigned_date,p_reason:q.reason,p_assignment:q.assignment_id});dbError(result.error);await a.db.rpc('refresh_alerts_after_change');res.json({id:result.data});
 });
 r.get('/routes',async(req,res)=>{
<<<<<<< HEAD
  const q=z.object({search:z.string().max(100).default(''),page:z.coerce.number().int().min(1).max(100000).default(1),archived:z.enum(['true','false']).default('false')}).parse(req.query),a=res.locals.auth as AuthContext;
  if(!a.access.permissions.some(p=>['trips.view','bookings.view'].includes(p)))throw new AppError(403,'FORBIDDEN','Route view permission is required.');
  let query=a.db.from('routes').select('id,origin,destination,version,archived,archived_at',{count:'exact'}).order('origin').order('destination');
  if(q.archived!=='true')query=query.eq('archived',false).is('archived_at',null);
=======
  const q=z.object({search:z.string().max(100).default(''),page:z.coerce.number().int().min(1).max(100000).default(1)}).parse(req.query),a=res.locals.auth as AuthContext;
  if(!a.access.permissions.some(p=>['trips.view','bookings.view'].includes(p)))throw new AppError(403,'FORBIDDEN','Route view permission is required.');
  let query=a.db.from('routes').select('id,origin,destination,version',{count:'exact'}).eq('archived',false).order('origin').order('destination');
>>>>>>> d1a492683f98713288c02ce0dbffae1d235f6a40
  // Two independent search columns are combined by the database, with quoted
  // filter syntax to keep punctuation in city names from changing the query.
  if(q.search){const term=q.search.replace(/[\\%_]/g,'\\$&').replace(/"/g,'\\"');query=query.or(`origin.ilike."%${term}%",destination.ilike."%${term}%"`);}
  const result=await query.range((q.page-1)*25,q.page*25-1);dbError(result.error);res.json({rows:result.data,count:result.count,page:q.page});
 });
 r.post('/routes',async(req,res)=>{
  const q=z.object({id:z.string().uuid().nullable().default(null),version:z.number().int().positive().nullable().default(null),origin:z.string().trim().min(1).max(120),destination:z.string().trim().min(1).max(120),archived:z.boolean().default(false)}).strict().parse(req.body),a=res.locals.auth as AuthContext;
  const result=await a.db.rpc('save_route',{p_id:q.id,p_version:q.version,p_origin:q.origin,p_destination:q.destination,p_archived:q.archived});dbError(result.error);res.json({id:result.data});
 });
 r.get('/notifications',async(req,res)=>{
  const q=z.object({status:z.enum(['all','read','unread']).default('all'),page:z.coerce.number().int().min(1).max(100000).default(1)}).parse(req.query);
  const result=await (res.locals.auth as AuthContext).db.rpc('notification_center',{p_status:q.status,p_page:q.page});dbError(result.error);res.json(result.data);
 });
 return r;
}
