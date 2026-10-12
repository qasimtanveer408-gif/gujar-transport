import {useEffect,useId,useState} from 'react';
import {api} from './api';
type Option={value:string;label:string};

export function Lookup({resource,value,onChange,required=false,disabled=false,label}:{resource:string;value:string;onChange:(v:string)=>void;required?:boolean;disabled?:boolean;label:string}){
 const id=useId(),[search,setSearch]=useState(''),[options,setOptions]=useState<Option[]>([]),[chosen,setChosen]=useState<Option|null>(null),[error,setError]=useState(''),[selectionError,setSelectionError]=useState('');
 useEffect(()=>{
  setSelectionError('');
  if(!value){setChosen(null);return;}
  let live=true;
  setChosen(previous=>previous?.value===value?previous:null);
  api<Option[]>(`/lookup?resource=${encodeURIComponent(resource)}&id=${encodeURIComponent(value)}`).then(rows=>{
   if(live){setChosen(rows[0]??null);if(!rows.length)setSelectionError('The selected record is unavailable.');}
  }).catch(e=>{if(live)setSelectionError(e instanceof Error?e.message:'Could not load the selected record.');});
  return()=>{live=false;};
 },[resource,value]);
 useEffect(()=>{
  let live=true;
  const timer=setTimeout(()=>{
   api<Option[]>(`/lookup?resource=${encodeURIComponent(resource)}&search=${encodeURIComponent(search)}`).then(rows=>{
    if(live){setOptions(rows);setError('');}
   }).catch(e=>{if(live)setError(e instanceof Error?e.message:'Search failed.');});
  },250);
  return()=>{live=false;clearTimeout(timer);};
 },[resource,search]);
 const selected=options.find(option=>option.value===value)??(chosen?.value===value?chosen:null);
 return <div className="lookup-field">
  <input type="search" aria-label={'Search '+label} aria-controls={id} placeholder={'Search '+label.toLowerCase()} value={search} onChange={e=>setSearch(e.target.value)} disabled={disabled}/>
  <select id={id} aria-label={label} aria-describedby={selected?id+'-selected':undefined} required={required} disabled={disabled} value={value} onChange={e=>{setChosen(options.find(option=>option.value===e.target.value)??null);onChange(e.target.value);}}>
   <option value="">Select…</option>
   {chosen&&chosen.value===value&&!options.some(option=>option.value===value)&&<option value={chosen.value}>{chosen.label}</option>}
   {options.map(option=><option key={option.value} value={option.value}>{option.label}</option>)}
  </select>
  {selected&&<small id={id+'-selected'} className="lookup-selected" role="status"><i className="bi bi-check-circle" aria-hidden="true"/>Selected: {selected.label}</small>}
  {(error||selectionError)&&<small role="alert">{error||selectionError}</small>}
  {options.length===25&&<small>Showing 25 matches. Refine your search.</small>}
 </div>;
}

export function LookupLabel({resource,value}:{resource:string;value:unknown}){
 const [label,setLabel]=useState('…');
 useEffect(()=>{if(!value){setLabel('—');return;}let active=true;api<Option[]>(`/lookup?resource=${resource}&id=${String(value)}`).then(rows=>{if(active)setLabel(rows[0]?.label??'Unavailable');}).catch(()=>{if(active)setLabel('Unavailable');});return()=>{active=false;};},[resource,value]);
 return <>{label}</>;
}
