/** Canonicalize human-entered decimals without rounding or hiding invalid grouping. */
export function normalizeDecimalInput(value:unknown):unknown{
 if(typeof value!=='string')return value;
 let text=value.trim().replace(/^−/,'-');
 if(/^[+-]?\d{1,3}(?:,\d{3})+(?:\.\d*)?$/.test(text))text=text.replaceAll(',','');
 if(/^\+(?:\d+(?:\.\d*)?|\.\d+)$/.test(text))text=text.slice(1);
 text=text.replace(/^(-?)\.(?=\d)/,(_match,sign:string)=>sign+'0.').replace(/^(-?\d+)\.$/,'$1');
 return text;
}
