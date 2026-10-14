let csrf='';
type ErrorDetails={code?:string;requestId?:string;databaseCode?:string};
export class ApiError extends Error{constructor(message:string,public status:number,public details:ErrorDetails={}){super(message);}}
export async function refreshCsrf(){const r=await fetch('/api/auth/csrf',{credentials:'same-origin'});if(!r.ok)throw new ApiError('Cannot connect to the application. Please retry.',r.status);csrf=(await r.json() as {csrf:string}).csrf;return csrf;}
export async function api<T>(path:string,method='GET',body?:unknown):Promise<T>{
 const mutate=method!=='GET';if(mutate&&!csrf)await refreshCsrf();
 let response:Response;try{response=await fetch('/api'+path,{method,credentials:'same-origin',headers:{...(body!==undefined?{'Content-Type':'application/json'}:{}),...(mutate?{'X-CSRF-Token':csrf}:{})},body:body===undefined?undefined:JSON.stringify(body)});}catch{throw new ApiError('Connection lost. Check your internet connection and retry.',0);}
 const data=await response.json() as {error?:{message:string}&ErrorDetails;csrf?:string};if(!response.ok){if(response.status===401&&!path.startsWith('/auth/')){csrf='';window.dispatchEvent(new Event('gbt:session-ended'));}throw new ApiError(data.error?.message??'Request failed.',response.status,data.error);}if(data.csrf)csrf=data.csrf;return data as T;
}
export async function uploadFile(file:File,resource:string,id:string){if(!csrf)await refreshCsrf();const r=await fetch(`/api/documents/upload?resource=${encodeURIComponent(resource)}&id=${encodeURIComponent(id)}&name=${encodeURIComponent(file.name)}`,{method:'POST',credentials:'same-origin',headers:{'Content-Type':file.type,'X-CSRF-Token':csrf},body:file});const result=await r.json() as {error?:{message:string}&ErrorDetails};if(!r.ok)throw new ApiError(result.error?.message??'Upload failed.',r.status,result.error);return result;}
