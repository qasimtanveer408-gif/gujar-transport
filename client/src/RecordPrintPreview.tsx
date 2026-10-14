import {useState,useEffect} from 'react';
import {api} from './api';
import {Modal,Loading,Alert,Icon} from './components';
import {printHtml} from './print';
export function RecordPrintPreview({resource,id,from,to,onClose}:{resource:string;id:string;from:string;to:string;onClose:()=>void}){
 const [html,setHtml]=useState(''),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 useEffect(()=>{let live=true;api<{html:string}>(`/print/record/${resource}/${id}?from=${from}&to=${to}`).then(r=>{if(live)setHtml(r.html);}).catch(e=>{if(live)setError(e.message);});return()=>{live=false;};},[resource,id,from,to]);
 return <Modal title="Print preview" onClose={onClose}><div className="dialog-body record-print-preview"><Alert message={error}/>{html?<iframe title="Record print preview" sandbox="allow-same-origin" srcDoc={html}/>:!error&&<Loading/>}</div><footer><button className="button secondary" onClick={onClose}>Close</button><button className="button primary" disabled={!html||busy} onClick={async()=>{setBusy(true);try{await printHtml(html);}catch(e){setError((e as Error).message);}finally{setBusy(false);}}}><Icon name="printer"/>{busy?'Preparing…':'Print / Save as PDF'}</button></footer></Modal>;
}

export function StaticPrintPreview({html,onClose,title='Print preview'}:{html:string;onClose:()=>void;title?:string}){const [error,setError]=useState('');return <Modal title={title} onClose={onClose}><div className="dialog-body record-print-preview"><Alert message={error}/><iframe title="Print preview" sandbox="allow-same-origin" srcDoc={html}/></div><footer><button className="button secondary" onClick={onClose}>Close</button><button className="button primary" onClick={async()=>{try{await printHtml(html);}catch(e){setError((e as Error).message);}}}><Icon name="printer"/>Print / Save as PDF</button></footer></Modal>;}
