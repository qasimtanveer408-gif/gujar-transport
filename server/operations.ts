import {Router} from 'express';
import {z} from 'zod';
import type {AuthContext} from './session.js';
import {AppError,dbError} from './errors.js';
import {validateData} from './domain.js';
import {parseCsv} from '../shared/csv-import.js';
import {csv} from '../shared/calculations.js';
import {modules} from '../shared/modules.js';
export function operationsRouter(){const router=Router();
<<<<<<< HEAD
 router.get('/alerts',async(_req,res)=>{const r=await (res.locals.auth as AuthContext).db.from('notifications').select('id,type,message,action_link,created_at,notification_reads(read_at)').is('resolved_at',null).is('archived_at',null).order('created_at',{ascending:false}).limit(100);dbError(r.error);res.json(r.data);});
=======
 router.get('/alerts',async(_req,res)=>{const r=await (res.locals.auth as AuthContext).db.from('notifications').select('id,type,message,action_link,created_at,notification_reads(read_at)').is('resolved_at',null).order('created_at',{ascending:false}).limit(100);dbError(r.error);res.json(r.data);});
>>>>>>> 2aef45882bd9ec54781d025e3620f1f2677a5c83
 router.post('/alerts/reconcile',async(_req,res)=>{dbError((await (res.locals.auth as AuthContext).db.rpc('reconcile_alerts')).error);res.json({ok:true});});
 router.post('/alerts/:id/read',async(req,res)=>{dbError((await (res.locals.auth as AuthContext).db.rpc('mark_notification_read',{p_id:z.string().uuid().parse(req.params.id)})).error);res.json({ok:true});});
 router.get('/alert-rules',async(_req,res)=>{const r=await (res.locals.auth as AuthContext).db.from('alert_rules').select('code,threshold::text,enabled,version').order('code');dbError(r.error);res.json(r.data);});
 router.post('/alert-rules',async(req,res)=>{const r=z.object({code:z.string().max(50),threshold:z.coerce.number().nonnegative().max(1e8),enabled:z.boolean(),version:z.number().int().positive()}).strict().parse(req.body);dbError((await (res.locals.auth as AuthContext).db.rpc('save_alert_rule',{p_code:r.code,p_threshold:r.threshold,p_enabled:r.enabled,p_version:r.version})).error);res.json({ok:true});});
 router.use('/imports',(_req,res,next)=>{if(!(res.locals.auth as AuthContext).access.permissions.includes('imports.manage'))throw new AppError(403,'FORBIDDEN','Import permission required.');next();});
 router.get('/imports/template',(req,res)=>{const resource=z.enum(['vehicles','drivers']).parse(req.query.resource);res.type('text/csv').setHeader('Content-Disposition',`attachment; filename="${resource}-template.csv"`);res.send(csv([],modules[resource].fields.filter(f=>!f.lookup).map(f=>f.key)));});
<<<<<<< HEAD
 router.get('/imports',async(_req,res)=>{const r=await (res.locals.auth as AuthContext).db.from('import_batches').select('id,resource,original_reference,state,created_at,archived_at,version').is('archived_at',null).order('created_at',{ascending:false}).limit(25);dbError(r.error);res.json(r.data);});
=======
 router.get('/imports',async(_req,res)=>{const r=await (res.locals.auth as AuthContext).db.from('import_batches').select('id,resource,original_reference,state,created_at').order('created_at',{ascending:false}).limit(25);dbError(r.error);res.json(r.data);});
>>>>>>> 2aef45882bd9ec54781d025e3620f1f2677a5c83
 router.post('/imports/preview',async(req,res)=>{const input=z.object({resource:z.enum(['vehicles','drivers']),reference:z.string().min(3).max(200),csv:z.string().max(200000)}).strict().parse(req.body);let rows:Record<string,string>[];try{rows=parseCsv(input.csv);}catch(e){throw new AppError(422,'CSV_INVALID',e instanceof Error?e.message:'Invalid CSV');}const clean:Record<string,unknown>[]=[],errors:{row:number;message:string}[]=[],seen=new Set<string>();for(const [i,row]of rows.entries()){try{const data=validateData(input.resource,row);const key=input.resource==='vehicles'?String(data.registration).replace(/\s/g,'').toUpperCase():String(data.full_name).trim().toLowerCase()+'|'+String(data.mobile).replace(/\D/g,'');if(seen.has(key))throw new Error('Duplicate within CSV');seen.add(key);clean.push(data);}catch(e){errors.push({row:i+2,message:e instanceof Error?e.message:'Invalid row'});}}if(errors.length){res.json({rows,errors,batch_id:null});return;}const r=await (res.locals.auth as AuthContext).db.rpc('prepare_import',{p_resource:input.resource,p_reference:input.reference,p_rows:clean});dbError(r.error);res.json({rows:clean,errors:[],batch_id:r.data});});
 router.post('/imports/:id/commit',async(req,res)=>{const r=await (res.locals.auth as AuthContext).db.rpc('commit_import',{p_batch:z.string().uuid().parse(req.params.id)});dbError(r.error);res.json({count:r.data.length});});return router;
}
