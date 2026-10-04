import assert from 'node:assert/strict';
import {createEventsService} from '../js/events-service.js';
const calls=[];const payload={p_offer_id:'offer',p_quantity:2,p_expected_price_kurus:'123456789012',p_request_id:'stable-request'};
const client={async rpc(name,args){calls.push({name,args});return {data:{request_id:args?.p_request_id},error:null};}};
const service=createEventsService(client);await service.snapshot();await service.buy(payload);await service.buy(payload);
assert.deepEqual(calls,[{name:'market_events_snapshot',args:undefined},{name:'buy_market_offer',args:payload},{name:'buy_market_offer',args:payload}]);
const error={code:'F0002'};await assert.rejects(()=>createEventsService({async rpc(){return {error};}}).buy(payload),e=>e===error);
console.log('PASS: offer service exact server RPC, integer price string, stable retry payload and server error propagation.');
