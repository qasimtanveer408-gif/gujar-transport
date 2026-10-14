import {randomUUID} from 'node:crypto';
import type {Config} from './config.js';
import {decrypt,encrypt,hash,token,csrfFor} from './crypto.js';
import type {User} from '@supabase/supabase-js';
import {publicClient,privilegedClient,userClient,type Client} from './supabase.js';
import {AppError,dbError} from './errors.js';
export interface Credentials{access_token:string;refresh_token:string;expires_at:number;}
export interface SessionRow{token_hash:string;user_id:string;auth_session_id:string;credentials:string;expires_at:string;version:number;refresh_owner:string|null;}
export interface Access{user:{id:string;email:string;display_name:string};permissions:string[];roles:string[];}
export interface AuthContext{db:Client;access:Access;session:SessionRow;csrf:string;credentials:Credentials;}
export type Broker={rpc:(name:string,args:Record<string,unknown>)=>Promise<{data:unknown;error:{code?:string;message:string}|null}>};
export async function refreshCredentials(c:Config,broker:Broker,row:SessionRow,refresh:(value:string)=>Promise<Credentials>):Promise<Credentials>{
 for(let attempt=0;attempt<50;attempt++){
  const credentials=decrypt<Credentials>(c.SESSION_ENCRYPTION_KEY,row.credentials,row.token_hash);
  if(credentials.expires_at>Date.now()/1000+90)return credentials;
  const owner=randomUUID();const claim=await broker.rpc('server_session_claim',{p_hash:row.token_hash,p_version:row.version,p_owner:owner});dbError(claim.error);
  if(claim.data===true){
   try{
    const fresh=await refresh(credentials.refresh_token);
    const result=await broker.rpc('server_session_rotate',{p_hash:row.token_hash,p_version:row.version,p_owner:owner,p_credentials:encrypt(c.SESSION_ENCRYPTION_KEY,fresh,row.token_hash)});dbError(result.error);
    if(result.data!==true)throw new AppError(401,'SESSION_EXPIRED','Sign in again.');
    return fresh;
   }catch(error){await broker.rpc('server_session_revoke',{p_hash:row.token_hash});throw error;}
  }
  await new Promise(resolve=>setTimeout(resolve,100));
  const result=await broker.rpc('server_session_read',{p_hash:row.token_hash});dbError(result.error);
  if(!result.data)throw new AppError(401,'SESSION_EXPIRED','Sign in again.');row=result.data as SessionRow;
 }
 throw new AppError(503,'SESSION_BUSY','Your session is refreshing. Please retry.');
}
export function createSessionService(c:Config){
 const admin=privilegedClient(c);
 const broker:Broker={rpc:async(name,args)=>{const {data,error}=await admin.rpc(name,args);return {data,error};}};
 async function persist(user:User,credentials:Credentials){
   const claims=JSON.parse(Buffer.from(credentials.access_token.split('.')[1],'base64url').toString()) as {session_id?:string;sub?:string};
   if(claims.sub!==user.id||!claims.session_id)throw new AppError(401,'INVALID_LOGIN','Invalid session.');
   const raw=token(),tokenHash=hash(raw);
   const result=await broker.rpc('server_session_create',{p_hash:tokenHash,p_user:user.id,p_auth_session:claims.session_id,p_credentials:encrypt(c.SESSION_ENCRYPTION_KEY,credentials,tokenHash)});
   if(result.error){await admin.auth.admin.signOut(credentials.access_token,'local');throw new AppError(403,'ACCOUNT_UNAVAILABLE','Your account has not been enabled for this application. Contact an administrator.');}
   return {raw,csrf:csrfFor(c.SESSION_ENCRYPTION_KEY,tokenHash)};
 }
 return {
  async login(email:string,password:string){
   const auth=publicClient(c);const {data,error}=await auth.auth.signInWithPassword({email,password});
   if(error||!data.session)throw new AppError(401,'INVALID_LOGIN','Email or password is incorrect, or the account is unavailable.');
   // Verify with Auth before reading a claim. Decoding alone is never authorization.
   const verified=await auth.auth.getUser(data.session.access_token);
   if(verified.error||!verified.data.user||verified.data.user.id!==data.user.id)throw new AppError(401,'INVALID_LOGIN','Sign in could not be verified.');
   return persist(verified.data.user,{access_token:data.session.access_token,refresh_token:data.session.refresh_token,expires_at:data.session.expires_at??0});
  },
  async authenticate(raw:string):Promise<AuthContext>{
   if(!/^[A-Za-z0-9_-]{43}$/.test(raw))throw new AppError(401,'SIGN_IN_REQUIRED','Sign in to continue.');
   const result=await broker.rpc('server_session_read',{p_hash:hash(raw)});dbError(result.error);
   if(!result.data)throw new AppError(401,'SESSION_EXPIRED','Your session ended. Sign in again.');
   const row=result.data as SessionRow;
   if(!Number.isFinite(Date.parse(row.expires_at))||Date.parse(row.expires_at)<=Date.now())throw new AppError(401,'SESSION_EXPIRED','Your session ended. Sign in again.');
   const credentials=await refreshCredentials(c,broker,row,async refresh_token=>{
    const auth=publicClient(c);const {data,error}=await auth.auth.refreshSession({refresh_token});
    if(error||!data.session)throw new AppError(401,'SESSION_EXPIRED','Your session ended. Sign in again.');
    return {access_token:data.session.access_token,refresh_token:data.session.refresh_token,expires_at:data.session.expires_at??0};
   });
   const verified=await publicClient(c).auth.getUser(credentials.access_token);
   if(verified.error||verified.data.user?.id!==row.user_id){await broker.rpc('server_session_revoke',{p_hash:row.token_hash});throw new AppError(401,'SESSION_EXPIRED','Sign in again.');}
   const db=userClient(c,credentials.access_token);const access=await db.rpc('my_access');dbError(access.error);
   return {db,access:access.data as Access,session:row,credentials,csrf:csrfFor(c.SESSION_ENCRYPTION_KEY,row.token_hash)};
  },
  async logout(context:AuthContext){
   const result=await broker.rpc('server_session_revoke',{p_hash:context.session.token_hash});dbError(result.error);
   // Local DB revocation blocks already-issued JWTs immediately through every policy.
   const resultAuth=await admin.auth.admin.signOut(context.credentials.access_token,'local');
   return {remoteSignOutVerified:!resultAuth.error};
  }
 };
}
export type SessionService=ReturnType<typeof createSessionService>;
