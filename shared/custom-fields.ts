import {Decimal} from 'decimal.js';
import {formContract,type FormResource} from './form-contract.js';
import {normalizeDecimalInput} from './numeric-input.js';

export type FormulaNode={kind:'number';value:string}|{kind:'field';key:string}|{kind:'unary';op:string;arg:FormulaNode}|{kind:'binary';op:string;left:FormulaNode;right:FormulaNode}|{kind:'call';name:string;args:FormulaNode[]};
export type CustomField={id:string;resource:FormResource;key:string;label:string;type:'text'|'number'|'date'|'currency'|'percentage'|'dropdown'|'checkbox'|'formula';default_value:unknown;required:boolean;display_order:number;show_form:boolean;show_card:boolean;show_table:boolean;show_print:boolean;hidden:boolean;archived:boolean;restricted:boolean;options:string[];formula:string;ast:FormulaNode|null;dependencies:string[];required_permissions:string[];version:number};
export const numericTypes=['number','currency','percentage','formula'];
export function numericKeys(resource:FormResource){
 const extra:Partial<Record<FormResource,string[]>>={vehicles:['current_odometer','expenses','profit','matched_km'],drivers:['income','expenses','profit','matched_km']};
 return [...new Set([...formContract[resource].fields.filter(f=>['decimal','year'].includes(f.type)).map(f=>f.key),...(extra[resource]??[])])];
}

/** A bounded arithmetic grammar, shared by the editor and server. No JavaScript evaluation. */
export function parseFormula(source:string,allowed:string[]):{ast:FormulaNode;dependencies:string[]}{
 const s=source.trim().replace(/^=/,'').replaceAll('×','*').replaceAll('÷','/').replaceAll('−','-');
 if(!s||s.length>500)throw new Error('Enter a formula of 1–500 characters.');
 const tokens:string[]=[];let pos=0;
 while(pos<s.length){if(/\s/.test(s[pos])){pos++;continue;}const m=/^(?:\d+(?:\.\d+)?|\.\d+|[A-Za-z_][A-Za-z_0-9]*|[+*/%(),-])/.exec(s.slice(pos));if(!m)throw new Error(`Unsupported formula character at position ${pos+1}.`);tokens.push(m[0]);pos+=m[0].length;if(tokens.length>160)throw new Error('Formula is too complex.');}
 let i=0,depth=0;const deps=new Set<string>();
 function expr(min=0):FormulaNode{
  if(++depth>32)throw new Error('Formula nesting is too deep.');
  const token=tokens[i++];let node:FormulaNode;
  if(token==='+'||token==='-')node={kind:'unary',op:token,arg:expr(3)};
  else if(token==='('){node=expr();if(tokens[i++]!==')')throw new Error('Close every opening parenthesis.');}
  else if(token&&/^(\d|\.)/.test(token)){if(new Decimal(token).abs().gt('1000000000000000'))throw new Error('Formula constant is too large.');node={kind:'number',value:token};}
  else if(token&&/^[A-Za-z_]/.test(token)){
   if(tokens[i]==='('){const name=token.toUpperCase();if(!['SUM','MIN','MAX','ABS','ROUND'].includes(name))throw new Error('Use SUM, MIN, MAX, ABS or ROUND.');i++;const args:FormulaNode[]=[];if(tokens[i]!==')'){do{args.push(expr());if(tokens[i]!==',')break;i++;}while(true);}if(tokens[i++]!==')')throw new Error('Close the function parentheses.');if(!args.length||args.length>20||name==='ABS'&&args.length!==1||name==='ROUND'&&![1,2].includes(args.length))throw new Error(`Invalid number of arguments for ${name}.`);node={kind:'call',name,args};}
   else {if(!allowed.includes(token))throw new Error(`Unknown numeric field: ${token}.`);deps.add(token);node={kind:'field',key:token};}
  }else throw new Error('The formula needs a number, numeric field or parentheses.');
  while(i<tokens.length){const op=tokens[i],priority=['*','/','%'].includes(op)?2:['+','-'].includes(op)?1:0;if(priority===0||priority<min)break;i++;node={kind:'binary',op,left:node,right:expr(priority+1)};}
  depth--;return node;
 }
 const ast=expr();if(i!==tokens.length)throw new Error('Check the operators and parentheses in the formula.');return {ast,dependencies:[...deps]};
}
export function evaluateNode(ast:FormulaNode,values:Record<string,unknown>,depth=0):Decimal{
 if(depth>32)throw new Error('Circular or overly complex formula.');let v:Decimal;
 const run=(n:FormulaNode)=>evaluateNode(n,values,depth+1);
 if(ast.kind==='number')v=new Decimal(ast.value);
 else if(ast.kind==='field'){const input=normalizeDecimalInput(values[ast.key]);if(input===null||input===undefined||input==='')throw new Error(`Enter a value for ${ast.key}.`);try{v=new Decimal(String(input));}catch{throw new Error(`${ast.key} must be numeric.`);}}
 else if(ast.kind==='unary')v=ast.op==='-'?run(ast.arg).neg():run(ast.arg);
 else if(ast.kind==='binary'){const a=run(ast.left),b=run(ast.right);if((ast.op==='/'||ast.op==='%')&&b.isZero())throw new Error('Cannot divide by zero.');v=ast.op==='+'?a.plus(b):ast.op==='-'?a.minus(b):ast.op==='*'?a.times(b):ast.op==='/'?a.div(b):a.mod(b);}
 else {const a=ast.args.map(run);if(ast.name==='ROUND'){const digits=a[1]?.toNumber()??2;if(!Number.isInteger(digits)||digits<0||digits>6)throw new Error('ROUND precision must be an integer from 0 to 6.');v=a[0].toDecimalPlaces(digits);}else v=ast.name==='ABS'?a[0].abs():ast.name==='MIN'?Decimal.min(...a):ast.name==='MAX'?Decimal.max(...a):a.reduce((s,x)=>s.plus(x),new Decimal(0));}
 if(!v.isFinite()||v.abs().gt('1000000000000000'))throw new Error('Formula result is too large.');return v;
}
export function calculateCustom(fields:CustomField[],base:Record<string,unknown>,input:Record<string,unknown>){
 const values:Record<string,unknown>={...base},result:Record<string,unknown>={},errors:Record<string,string>={},state=new Map<string,number>();const active=fields.filter(f=>!f.archived);
 function calc(key:string):unknown{if(state.get(key)===1)throw new Error('Circular formula dependency.');if(state.get(key)===2)return values[key];const field=active.find(f=>f.key===key);if(!field)return values[key];state.set(key,1);try{if(field.type==='formula'){for(const dep of field.dependencies??[])if(active.some(f=>f.key===dep))calc(dep);if(!field.ast)throw new Error('Formula is not configured.');values[key]=evaluateNode(field.ast,values).toDecimalPlaces(6).toString();}else values[key]=Object.hasOwn(input,key)?input[key]:field.default_value;result[key]=values[key];}catch(e){values[key]=null;result[key]=null;errors[key]=(e as Error).message;}state.set(key,2);return values[key];}
 for(const f of active)calc(f.key);return {values:result,errors};
}
export function customValue(field:CustomField,value:unknown,error?:unknown){if(error)return String(error);if(value===null||value===undefined||value==='')return '—';if(field.type==='checkbox')return value?'Yes':'No';if(field.type==='date')return String(value).split('-').reverse().join('/');if(numericTypes.includes(field.type)){const v=Number(normalizeDecimalInput(value));if(!Number.isFinite(v))return '—';return (field.type==='currency'?'Rs ':'')+v.toLocaleString('en-PK',{maximumFractionDigits:field.type==='currency'?2:6})+(field.type==='percentage'?'%':'');}return String(value);}
