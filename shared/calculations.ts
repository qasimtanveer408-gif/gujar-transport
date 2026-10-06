import {Decimal} from 'decimal.js';
Decimal.set({precision:32,rounding:Decimal.ROUND_HALF_UP});
export function tripPreview(fare:string,expenses:string[],start:string,end:string,litres:string|null){
 const distance=new Decimal(end).minus(start);if(distance.isNegative())throw new Error('End odometer must not be below start odometer');
 const total=expenses.reduce((a,b)=>a.plus(b),new Decimal(0));
 return {distance:distance.toFixed(3),expenses:total.toFixed(2),profit:new Decimal(fare).minus(total).toFixed(2),efficiency:litres&&new Decimal(litres).gt(0)?distance.div(litres).toFixed(2):null};
}
export function pooledEfficiency(rows:{distance:string;litres:string|null;basis:string}[],basis:string){
 const matched=rows.filter(r=>r.basis===basis&&r.litres&&new Decimal(r.litres).gt(0)&&new Decimal(r.distance).gte(0));
 const distance=matched.reduce((a,b)=>a.plus(b.distance),new Decimal(0)),litres=matched.reduce((a,b)=>a.plus(b.litres!),new Decimal(0));
 return {distance:distance.toFixed(3),litres:litres.toFixed(3),efficiency:litres.gt(0)?distance.div(litres).toFixed(2):null,count:matched.length};
}
export function businessDate(timestamp:Date=new Date()){return new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Karachi',year:'numeric',month:'2-digit',day:'2-digit'}).format(timestamp);}
export function safeCell(value:unknown){const s=value==null?'':String(value);return /^[\s]*[=+@-]/.test(s)?`'${s}`:s;}
export function csv(rows:Record<string,unknown>[],columns:string[]){const quote=(s:unknown)=>'"'+safeCell(s).replaceAll('"','""')+'"';return '\uFEFF'+[columns.map(quote).join(','),...rows.map(row=>columns.map(k=>quote(row[k])).join(','))].join('\r\n');}
