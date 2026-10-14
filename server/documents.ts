import {Router,raw} from 'express';
import {z} from 'zod';
import {uuid} from '../shared/validation.js';
import type {AuthContext} from './session.js';
import {AppError,dbError} from './errors.js';
const resource=z.enum(['vehicles','drivers','trips','maintenance','office-expenses']);
const sourceColumns={vehicles:'vehicle_id',drivers:'driver_id',trips:'trip_id',maintenance:'maintenance_id','office-expenses':'office_expense_id'};
export function validateDocument(buffer:Buffer,name:string,mime:string){
 if(buffer.length===0||buffer.length>10485760)throw new AppError(422,'FILE_SIZE','Files must be between 1 byte and 10 MB.');
 let expected='';if(buffer.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])))expected='image/png';
 else if(buffer[0]===255&&buffer[1]===216&&buffer[2]===255)expected='image/jpeg';
 else if(buffer.subarray(0,5).toString()==='%PDF-')expected='application/pdf';
 const ext=name.split('.').at(-1)?.toLowerCase();
 if(!expected||mime!==expected||!({ 'image/png':['png'],'image/jpeg':['jpg','jpeg'],'application/pdf':['pdf']}[expected]?.includes(ext??'')))throw new AppError(422,'FILE_TYPE','The file content, extension, and MIME type must match a PNG, JPEG, or PDF.');
 if(expected==='application/pdf'&&/\/(JavaScript|JS|Launch|EmbeddedFile)\b/i.test(buffer.toString('latin1')))throw new AppError(422,'ACTIVE_PDF','PDF documents containing scripts, launch actions, or embedded files are not accepted.');
 return expected;
}
export function documentsRouter(){const router=Router();
 router.get('/documents',async(req,res)=>{const q=z.object({resource,id:uuid}).parse(req.query);const db=(res.locals.auth as AuthContext).db;const result=await db.from('attachments').select('id,original_name,mime_type,size_bytes,state,created_at,archived_at,version').eq(sourceColumns[q.resource],q.id).neq('state','deleted').order('created_at',{ascending:false});dbError(result.error);res.json(result.data);});
 router.post('/documents/upload',raw({type:['image/jpeg','image/png','application/pdf'],limit:'10mb'}),async(req,res)=>{
  const q=z.object({resource,id:uuid,name:z.string().min(1).max(160).regex(/^[^\r\n/\\]+$/)}).parse(req.query);if(!Buffer.isBuffer(req.body))throw new AppError(422,'FILE_TYPE','Send a PNG, JPEG, or PDF file.');const mime=validateDocument(req.body,q.name,req.get('content-type')?.split(';')[0]??'');const db=(res.locals.auth as AuthContext).db;
  const reserved=await db.rpc('reserve_attachment',{p_resource:q.resource,p_record:q.id,p_name:q.name,p_mime:mime,p_size:req.body.length});dbError(reserved.error);const record=reserved.data as {id:string;bucket_id:string;object_path:string};
  const upload=await db.storage.from(record.bucket_id).upload(record.object_path,req.body,{contentType:mime,upsert:false,cacheControl:'0'});
  if(upload.error)throw new AppError(503,'UPLOAD_FAILED','Upload failed. The pending upload will be cleaned up; retry with the file.');
  const finish=await db.rpc('finalize_attachment',{p_id:record.id});if(finish.error)throw new AppError(503,'UPLOAD_PENDING','File transferred but finalization failed. Contact an administrator with the request ID before retrying.');
  res.status(201).json({id:record.id});
 });
 router.get('/documents/:id/link',async(req,res)=>{const db=(res.locals.auth as AuthContext).db;const record=await db.from('attachments').select('bucket_id,object_path,original_name').eq('id',uuid.parse(req.params.id)).eq('state','ready').maybeSingle();dbError(record.error);if(!record.data)throw new AppError(404,'NOT_FOUND','Document unavailable.');const signed=await db.storage.from(record.data.bucket_id).createSignedUrl(record.data.object_path,60,{download:record.data.original_name});if(signed.error)throw new AppError(503,'DOWNLOAD_FAILED','Could not create a download link.');res.json({url:signed.data.signedUrl,expires_in:60});});
 router.post('/documents/:id/delete',async(req,res)=>{const db=(res.locals.auth as AuthContext).db;const id=uuid.parse(req.params.id);const begun=await db.rpc('delete_attachment_state',{p_id:id,p_finish:false});dbError(begun.error);const record=begun.data as {bucket_id:string;object_path:string};const result=await db.storage.from(record.bucket_id).remove([record.object_path]);if(result.error)throw new AppError(503,'DELETE_PENDING','The deletion is pending. Retry to finish removing the file.');const finish=await db.rpc('delete_attachment_state',{p_id:id,p_finish:true});dbError(finish.error);res.json({ok:true});});
 return router;
}
