export class AppError extends Error { constructor(public status:number,public code:string,message:string){super(message);} }
export function dbError(error:{code?:string;message:string}|null){
 if(!error)return;
 if(error.code==='42501')throw new AppError(403,'FORBIDDEN','You do not have permission for this action.');
 if(error.code==='40001'||error.code==='23505')throw new AppError(409,'CONFLICT','This record changed or already exists. Reload and try again.');
 if(error.code==='23503'||error.code==='23514'||error.code?.startsWith('22'))throw new AppError(422,'INVALID_DATA','The values or linked records are not valid.');
 if(error.code==='P0001')throw new AppError(422,'RULE_VIOLATION',error.message.slice(0,200));
 throw new AppError(503,'DATABASE_UNAVAILABLE','The data service is unavailable or its schema needs updating.');
}
