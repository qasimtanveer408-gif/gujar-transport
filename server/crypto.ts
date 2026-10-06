import {createCipheriv,createDecipheriv,createHash,createHmac,randomBytes,timingSafeEqual} from 'node:crypto';
export function token(){return randomBytes(32).toString('base64url');}
export function hash(value:string){return createHash('sha256').update(value).digest('hex');}
export function same(a:string,b:string){const x=Buffer.from(a),y=Buffer.from(b);return x.length===y.length&&timingSafeEqual(x,y);}
export function csrfFor(key:string,value:string){return createHmac('sha256',Buffer.from(key,'hex')).update('csrf:'+value).digest('base64url');}
export function encrypt(key:string,data:unknown,aad:string){const iv=randomBytes(12);const cipher=createCipheriv('aes-256-gcm',Buffer.from(key,'hex'),iv);cipher.setAAD(Buffer.from(aad));const bytes=Buffer.concat([cipher.update(JSON.stringify(data),'utf8'),cipher.final()]);return Buffer.concat([iv,cipher.getAuthTag(),bytes]).toString('base64url');}
export function decrypt<T>(key:string,ciphertext:string,aad:string):T {const b=Buffer.from(ciphertext,'base64url');if(b.length<29)throw new Error('Invalid encrypted session');const decipher=createDecipheriv('aes-256-gcm',Buffer.from(key,'hex'),b.subarray(0,12));decipher.setAAD(Buffer.from(aad));decipher.setAuthTag(b.subarray(12,28));return JSON.parse(Buffer.concat([decipher.update(b.subarray(28)),decipher.final()]).toString('utf8')) as T;}
