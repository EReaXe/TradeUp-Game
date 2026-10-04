import {PGlite} from '@electric-sql/pglite';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const db=new PGlite();
try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth,public to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
 for(const name of ['001_store_onboarding','002_database_core','003_dashboard','004_wholesale','005_inventory','006_npc_sales','007_marketplace'])await db.exec(await readFile('supabase/migrations/'+name+'.sql','utf8'));
 await db.exec(await readFile('supabase/seed.sql','utf8'));
 for(const name of ['008_economy','009_market_events','010_progression'])await db.exec(await readFile('supabase/migrations/'+name+'.sql','utf8'));
 const users=[randomUUID(),randomUUID()];
 async function auth(i=0){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[users[i]]);await db.exec('set role authenticated');}
 for(let i=0;i<2;i++){await db.query('insert into auth.users values($1)',[users[i]]);await auth(i);await db.query('select public.complete_store_onboarding($1,$2)',['progress_'+i,'Progress '+i]);await db.exec('reset role');}
 const store=(await db.query('select id from public.stores where user_id=$1',[users[0]])).rows[0].id;
 const product=(await db.query("select id,wholesale_price_kurus::text price from public.products where name='Gel Pen Set'")).rows[0];
 const snapshot=async()=> (await db.query('select public.my_progression() data')).rows[0].data;
 await auth();assert.equal((await snapshot()).xp,'0');
 await assert.rejects(()=>db.query('select public.create_marketplace_listing($1,1,20000,$2)',[product.id,randomUUID()]),e=>e.code==='G0001');
 await assert.rejects(()=>db.query('select public.sync_store_progression($1)',[store]),e=>e.code==='42501');
 await assert.rejects(()=>db.query('select public.create_marketplace_listing_phase7($1,1,20000,$2)',[product.id,randomUUID()]),e=>e.code==='42501');
 let state=await snapshot(),mission=state.missions.find(x=>x.code==='daily_buy');
 await assert.rejects(()=>db.query('select public.claim_progression_mission($1,$2)',['daily_buy',mission.period_start]),e=>e.code==='G0003');
 await db.query('select public.buy_wholesale($1,10,$2,$3)',[product.id,product.price,randomUUID()]);
 const receipt=(await db.query('select public.claim_progression_mission($1,$2) data',['daily_buy',mission.period_start])).rows[0].data;
 assert.equal(receipt.xp_reward,100);assert.equal(receipt.cash_reward_kurus,'2500');
 assert.deepEqual((await db.query('select public.claim_progression_mission($1,$2) data',['daily_buy',mission.period_start])).rows[0].data,receipt);
 await assert.rejects(()=>db.query("select public.claim_progression_mission('daily_buy',date '2000-01-01')"),e=>e.code==='G0004');
 await db.exec('reset role');
 async function sale(quantity=1,cost=100,amount=200){await db.query(`insert into public.transactions(user_id,store_id,type,amount_kurus,balance_after_kurus,reference_id,idempotency_key,sale_quantity,cost_of_goods_kurus) values($1,$2,'NPC_SALE',$3,1000000,$4,$5,$6,$7)`,[users[0],store,amount,product.id,'test:'+randomUUID(),quantity,cost]);}
 await sale();await sale(1,300,200);await sale(1,null,200);
 await auth();state=await snapshot();assert.equal(state.xp,'160');assert.equal(state.level,2);assert.ok(state.titles.some(x=>x.code==='founder'));
 assert.deepEqual((await snapshot()).xp,state.xp);
 await db.query("select public.set_active_title('founder')");assert.equal((await snapshot()).active_title,'Founder');
 await assert.rejects(()=>db.query("select public.set_active_title('billionaire')"),e=>e.code==='G0005');
 await db.query('select public.set_active_title(null)');assert.equal((await snapshot()).active_title,null);
 await db.exec('reset role');for(let i=0;i<25;i++)await sale(100,100,200);
 assert.equal((await db.query("select sum(amount)::int n from public.store_xp_events where store_id=$1 and kind='SALE'",[store])).rows[0].n,2000);
 await auth();state=await snapshot();assert.ok(state.level>=5);const xp=state.xp;assert.equal((await snapshot()).xp,xp);
 // A failed reward ledger insert must leave cash, XP, titles and receipt untouched.
 const sellPeriod=state.missions.find(x=>x.code==='daily_sell').period_start;
 await db.exec('reset role');await db.exec(`create function public.fail_mission_ledger() returns trigger language plpgsql as $$begin if new.idempotency_key like 'mission:%' then raise exception 'test reward rollback';end if;return new;end;$$;create trigger fail_mission_ledger before insert on public.transactions for each row execute function public.fail_mission_ledger();`);
 const before={};for(const table of ['stores','mission_claims','store_titles','store_xp_events','transactions'])before[table]=(await db.query('select * from public.'+table+' order by 1')).rows;
 await auth();await assert.rejects(()=>db.query("select public.claim_progression_mission('daily_sell',$1)",[sellPeriod]),e=>e.code==='P0001');
 await db.exec('reset role');for(const table of Object.keys(before))assert.deepEqual((await db.query('select * from public.'+table+' order by 1')).rows,before[table]);await db.exec('drop trigger fail_mission_ledger on public.transactions');await auth();
 const request=randomUUID(),listing=(await db.query('select public.create_marketplace_listing($1,1,20000,$2) id',[product.id,request])).rows[0].id;
 await db.exec('reset role');await db.query('update public.stores set level=1 where id=$1',[store]);await auth();
 assert.equal((await db.query('select public.create_marketplace_listing($1,1,20000,$2) id',[product.id,request])).rows[0].id,listing);
 await db.query('select public.cancel_marketplace_listing($1)',[listing]);
 await auth(1);assert.equal((await db.query('select count(*)::int n from public.mission_claims')).rows[0].n,0);assert.equal((await snapshot()).xp,'0');
 for(const table of ['store_xp_events','mission_claims','store_titles','store_achievements'])await assert.rejects(()=>db.exec('delete from public.'+table),e=>e.code==='42501');
 await db.exec('reset role');await assert.rejects(()=>db.exec('update public.store_xp_events set amount=1'),e=>e.code==='55000');
 await db.exec(await readFile('supabase/migrations/010_progression.sql','utf8'));await auth();assert.equal((await snapshot()).xp,xp);
 console.log('PASS: progression migration/replay, XP cap and profitable-sale trigger, achievement idempotency, mission reward/retry/period checks, titles, ownership/RLS, private RPC denial, level gate and legacy cancellation/retry.');
}catch(error){console.error(error.message,error.code);process.exitCode=1;}finally{await db.close();}
