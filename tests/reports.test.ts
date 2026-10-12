import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import ExcelJS from 'exceljs';
import {reportsRouter} from '../server/reports.js';

test('report HTTP exports produce safe CSV and readable XLSX with the supplied logo (mock database)',async t=>{
 const rows=[{registration:'=1+1',purchase_price:'44000.00',remarks:'Line, "quoted"'}];
 const app=express();
 app.use((_req,res,next)=>{res.locals.auth={access:{permissions:['vehicles.view','reports.export','reports.financial.view']},db:{rpc:async()=>({data:rows,error:null}),from:()=>({select:()=>({single:async()=>({data:{business_name:'Gujjar Brother Transport',contact_email:'attiqgujjar360gb@gmail.com',phone_1:'03481201249',phone_2:'03003486360',phone_3:'03002676328',currency:'PKR',timezone:'Asia/Karachi'},error:null})})})}};next();});
 app.use('/api',reportsRouter());const server=app.listen(0,'127.0.0.1');
 await new Promise<void>(r=>server.once('listening',r));t.after(()=>new Promise<void>(r=>server.close(()=>r())));
 const address=server.address();if(!address||typeof address==='string')throw new Error('Missing server address');
 const url=`http://127.0.0.1:${address.port}/api/reports?kind=vehicles&from=2026-10-01&to=2026-10-31&format=`;
 const csv=await fetch(url+'csv');assert.equal(csv.status,200);const text=await csv.text();assert.match(text,/'=1\+1/);assert.match(text,/44000\.00/);assert.match(text,/Line, ""quoted""/);
 const xlsx=await fetch(url+'xlsx');assert.equal(xlsx.status,200);assert.match(xlsx.headers.get('content-type')??'',/spreadsheetml/);
 const book=new ExcelJS.Workbook();await book.xlsx.load(await xlsx.arrayBuffer());const sheet=book.getWorksheet('Full-field register')!;
 assert.equal(sheet.getCell('A1').value,'Gujjar Brother Transport');assert.equal(sheet.getCell('A5').value,"'=1+1");assert.equal(sheet.getRow(5).getCell(Array.from({length:sheet.columnCount},(_,i)=>sheet.getRow(4).getCell(i+1).value).indexOf('Purchase price (PKR)')+1).value,44000);assert.equal(sheet.getImages().length,1);assert.ok(sheet.autoFilter);
});
