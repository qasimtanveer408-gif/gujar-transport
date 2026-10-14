import type {User} from '@supabase/supabase-js';
import type {Client} from './supabase.js';
import {AppError,dbError} from './errors.js';
export interface ProvisionTask{id:string;email:string;display_name:string;state:string;user_id?:string;}
export async function findAuthUser(admin:Client,email:string):Promise<User|null>{
 for(let page=1;page<=10000;page++){const {data,error}=await admin.auth.admin.listUsers({page,perPage:200});if(error)throw new AppError(503,'AUTH_UNAVAILABLE','Auth administration is unavailable.');const match=data.users.find(u=>u.email?.toLowerCase()===email.toLowerCase());if(match)return match;if(data.users.length<200)return null;}
 throw new AppError(503,'DIRECTORY_LIMIT','Directory scan limit reached; contact the system administrator.');
}
export async function finishProvision(admin:Client,task:ProvisionTask,password:string){
 let user=await findAuthUser(admin,task.email);
 if(user&&user.app_metadata.gbt_provisioning_id!==task.id)throw new AppError(409,'UNRELATED_ACCOUNT','An unrelated Auth account uses that email. It was not modified.');
 if(!user){
  const created=await admin.auth.admin.createUser({email:task.email,password,email_confirm:true,app_metadata:{gbt_provisioning_id:task.id}});
  if(created.error){user=await findAuthUser(admin,task.email);if(!user||user.app_metadata.gbt_provisioning_id!==task.id)throw new AppError(422,'PROVISION_FAILED','Auth account creation failed. Check password policy and retry.');}else user=created.data.user;
 }
 if(!user)throw new AppError(503,'PROVISION_FAILED','Auth returned no account.');
 const result=await admin.rpc('server_provision_finish',{p_task:task.id,p_user:user.id});dbError(result.error);
 return user.id;
}
