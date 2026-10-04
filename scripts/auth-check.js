import assert from 'node:assert/strict';
import {createAuthService,authError} from '../js/auth-service.js';
// Test doubles only. Production always uses the real Supabase client.
const calls=[];
const user={id:'test-user'};
const store={user_id:user.id,username:'tester',store_name:'Test Store'};
const auth={
 getUser:async()=>({data:{user},error:null}),
 signInWithPassword:async input=>{calls.push(input);return {data:{user},error:null};},
 signUp:async input=>{calls.push(input);return {data:{user,session:null},error:null};},
 signOut:async input=>{calls.push(input);return {error:null};}
};
const client={auth,from:name=>{assert.equal(name,'stores');return {select:columns=>{assert.equal(columns,'user_id,store_name,created_at');return {eq:(key,value)=>{assert.equal(key,'user_id');assert.equal(value,user.id);return {maybeSingle:async()=>({data:store,error:null})};}};}};},rpc:async(name,input)=>{assert.equal(name,'complete_store_onboarding');assert.deepEqual(input,{p_username:'tester',p_store_name:'Test Store'});return {data:store,error:null};}};
const service=createAuthService(client);
assert.deepEqual(await service.user(),user);
await service.login('a@example.com','secret'); assert.deepEqual(calls.pop(),{email:'a@example.com',password:'secret'});
const registration=await service.register('a@example.com','secret','http://localhost:3000/login.html');
assert.equal(registration.session,null);assert.equal(calls.pop().options.emailRedirectTo,'http://localhost:3000/login.html');
assert.deepEqual(await service.store(user.id),store);
assert.deepEqual(await service.createStore('tester','Test Store'),store);
await service.logout(); assert.deepEqual(calls.pop(),{scope:'local'});
for(const code of ['invalid_credentials','email_not_confirmed','23505','PGRST202']) assert.ok(authError({code}).length>0);
const rejected={code:'invalid_credentials'};
auth.signInWithPassword=async()=>({data:null,error:rejected});
await assert.rejects(()=>service.login('a@example.com','bad'),error=>error===rejected);
client.rpc=async()=>({data:null,error:{code:'23505'}});
await assert.rejects(()=>service.createStore('tester','Test Store'),error=>error.code==='23505');
auth.signOut=async()=>({error:{status:500}});
await assert.rejects(()=>service.logout(),error=>error.status===500);
console.log('PASS: auth requests, email-confirmation branch, identity RPC, errors and logout. These are isolated service tests, not live Supabase verification.');
