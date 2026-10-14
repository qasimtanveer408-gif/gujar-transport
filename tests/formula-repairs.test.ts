import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeDecimalInput} from '../shared/numeric-input.js';
import {money,numberString} from '../shared/validation.js';
import {tripFormPreview} from '../shared/trip-form.js';
import {tripPreview,pooledEfficiency,topAverageVehicle} from '../shared/calculations.js';
import {parseFormula,evaluateNode,calculateCustom,numericKeys,type CustomField} from '../shared/custom-fields.js';
import {formFixture} from './helpers/form-fixture.js';
import {validateForm} from '../server/form-validation.js';
import type {FormResource} from '../shared/form-contract.js';

const sample={fare:'80000',diesel:'29000',tolls:'3000',food:'1200',commission:'2000',other:'800',start_odometer:'144844',end_odometer:'145382',fuel_litres:'68'};
test('Human decimal inputs normalize without rounding or accepting malformed grouping',()=>{
 for(const [input,expected] of [['.50','0.50'],['80,000.25','80000.25'],[' +1,000.125 ','1000.125'],['100.','100'],['−.5','-0.5']])assert.equal(normalizeDecimalInput(input),expected);
 assert.equal(money.parse('.50'),'0.50');assert.equal(money.parse('80,000.25'),'80000.25');assert.equal(numberString.parse('1,000.125'),'1000.125');
 for(const input of ['1,23','1,00,000','NaN','Infinity','1e3','-1','0.001'])assert.equal(money.safeParse(input).success,false,input);
 assert.equal(numberString.safeParse('1.2345').success,false);
 assert.equal(normalizeDecimalInput('.'),'.');assert.equal(normalizeDecimalInput('-.'),'-.');
});
test('Trip formulas display the independently calculated example and update on edits',()=>{
 let r=tripFormPreview(sample);assert.deepEqual(r.errors,{});
 assert.deepEqual([r.values.total_expense,r.values.profit,r.values.total_km,r.values.average],['36000.00','44000.00','538.000','7.91']);
 r=tripFormPreview({...sample,diesel:'28,000',end_odometer:'145,524'});
 assert.deepEqual([r.values.total_expense,r.values.profit,r.values.total_km,r.values.average],['35000.00','45000.00','680.000','10.00']);
 assert.equal(r.values.diesel,'28,000','Editable input string is preserved');
});
test('Incomplete or invalid input affects only dependent results, never other input fields',()=>{
 const invalid=tripFormPreview({...sample,food:'.'});assert.ok(invalid.errors.food);assert.equal(invalid.values.total_expense,null);assert.equal(invalid.values.profit,null);
 assert.equal(invalid.values.total_km,'538.000');assert.equal(invalid.values.average,'7.91');assert.equal(invalid.values.food,'.');assert.equal(invalid.values.fare,'80000');
 const fare=tripFormPreview({...sample,fare:'x'});assert.equal(fare.values.total_expense,'36000.00');assert.equal(fare.values.profit,null);assert.equal(fare.values.average,'7.91');
 for(const fuel of ['0','',null,undefined])assert.equal(tripFormPreview({...sample,fuel_litres:fuel}).values.average,null);
 const odo=tripFormPreview({...sample,end_odometer:'1'});assert.ok(odo.errors.end_odometer);assert.equal(odo.values.total_km,null);assert.equal(odo.values.total_expense,'36000.00');
 assert.equal(tripFormPreview({...sample,end_odometer:''}).values.total_km,null);
});
test('Formula minus operator, formatted numeric inputs, dependencies and zero are consistent',()=>{
 assert.equal(evaluateNode(parseFormula('fare − total_expense',['fare','total_expense']).ast,{fare:'80,000.25',total_expense:'36,000'}).toString(),'44000.25');
 function field(key:string,formula?:string):CustomField{return {key,type:formula?'formula':'number',archived:false,default_value:null,ast:formula?parseFormula(formula,['cf_quantity','cf_rate','cf_total']).ast:null,dependencies:formula?parseFormula(formula,['cf_quantity','cf_rate','cf_total']).dependencies:[]} as CustomField;}
 const fields=[field('cf_balance','cf_total − 1.25'),field('cf_total','cf_quantity * cf_rate'),field('cf_quantity'),field('cf_rate')];
 let r=calculateCustom(fields,{}, {cf_quantity:'4.',cf_rate:'3.25'});assert.equal(r.values.cf_total,'13');assert.equal(r.values.cf_balance,'11.75');assert.equal(r.values.cf_quantity,'4.');
 r=calculateCustom(fields,{}, {cf_quantity:'0',cf_rate:'3.25'});assert.equal(r.values.cf_total,'0');assert.equal(r.values.cf_balance,'-1.25');
 r=calculateCustom(fields,{}, {cf_quantity:'.',cf_rate:'3.25'});assert.equal(r.values.cf_quantity,'.');assert.equal(r.values.cf_total,null);assert.ok(r.errors.cf_total);
 assert.throws(()=>tripPreview('NaN',[],'0','1','1'),/finite/);
});
test('Top average vehicle uses the existing filtered pooled metric, safely handles empty rankings',()=>{
 const rows=[{registration:'LOW',efficiency:'7.91'},{registration:'HIGH',efficiency:'10.00'},{registration:'BAD',efficiency:'Infinity'},{registration:'EMPTY',efficiency:null}];
 assert.equal(topAverageVehicle(rows)?.registration,'HIGH');assert.equal(topAverageVehicle([]),null);assert.equal(topAverageVehicle([{efficiency:'NaN'}]),null);
 const result=pooledEfficiency([{distance:'538',litres:'68',basis:'measured'},{distance:'680',litres:'68',basis:'measured'},{distance:'999',litres:'NaN',basis:'measured'},{distance:'1000',litres:'100',basis:'purchase_estimate'}],'measured');
 assert.equal(result.efficiency,'8.96');assert.equal(result.count,2);
});
test('Formula catalog matches PostgreSQL and normalized inputs survive actual saves and reopening',async t=>{
 const f=await formFixture();t.after(()=>f.db.close());
 await f.db.exec('reset role');
 for(const resource of ['vehicles','drivers','trips','maintenance'] as FormResource[]){const keys=await f.scalar<string[]>('select private.custom_numeric_keys($1)',[resource]);assert.deepEqual(numericKeys(resource).sort(),keys.sort(),resource);}
 await f.asUser();
 const data=validateForm('trips',{...f.tripData,fare:'80,000.25',start_odometer:'144,844',end_odometer:'145,382',fuel_litres:'.50'},f.permissions);
 await f.save('trips',data,f.trip,1);let saved=await f.read('trips',f.trip);
 assert.equal(saved.fare,'80000.25');assert.equal(saved.total_expense,'36000.00');assert.equal(saved.profit,'44000.25');assert.equal(saved.average,'1076.00');
 await f.save('trips',validateForm('trips',{...f.tripData,end_odometer:'145,524'},f.permissions),f.trip,2);saved=await f.read('trips',f.trip);
 assert.equal(saved.total_km,'680.000');assert.equal(saved.average,'10.00');
});
