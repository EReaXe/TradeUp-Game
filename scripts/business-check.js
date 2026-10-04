import {PGlite} from '@electric-sql/pglite';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const db=new PGlite();
try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth,public to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
 for(const name of ['001_store_onboarding','002_database_core','003_dashboard','004_wholesale','005_inventory','006_npc_sales','007_marketplace'])await db.exec(await readFile('supabase/migrations/'+name+'.sql','utf8'));
 await db.exec(await readFile('supabase/seed.sql','utf8'));
 for(const name of ['008_economy','009_market_events','010_progression','011_business'])await db.exec(await readFile('supabase/migrations/'+name+'.sql','utf8'));
 const users=[randomUUID(),randomUUID()];async function auth(i=0){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[users[i]]);await db.exec('set role authenticated');}
 for(let i=0;i<2;i++){await db.query('insert into auth.users values($1)',[users[i]]);await auth(i);await db.query('select public.complete_store_onboarding($1,$2)',['business_'+i,'Business '+i]);await db.exec('reset role');}
 const store=(await db.query('select id from public.stores where user_id=$1',[users[0]])).rows[0].id;
 const snap=async()=> (await db.query('select public.my_business() data')).rows[0].data;
 const action=async(kind,code='upgrade',tier=0,key=randomUUID())=>(await db.query('select public.business_action($1,$2,$3,$4) data',[kind,code,tier,key])).rows[0].data;
 await auth();let state=await snap();assert.equal(state.warehouse_capacity,50);assert.equal(state.brand_value,0);assert.equal(state.roles.length,6);
 await assert.rejects(()=>action('campaign','social'),e=>e.code==='B0005');await assert.rejects(()=>action('hire','sales'),e=>e.code==='B0005');await assert.rejects(()=>action('office'),e=>e.code==='B0005');
 const request=randomUUID(),receipt=await action('warehouse','upgrade',0,request);assert.equal(receipt.cost_kurus,'250000');assert.equal(receipt.balance_after_kurus,'750000');assert.equal(receipt.xp_reward,100);assert.equal(receipt.warehouse_capacity,250);
 assert.deepEqual(await action('warehouse','upgrade',0,request),receipt);await assert.rejects(()=>action('office','upgrade',0,request),e=>e.code==='B0002');await assert.rejects(()=>action('warehouse','upgrade',0),e=>e.code==='B0003');
 state=await snap();assert.equal(state.business_assets_kurus,'125000');let dashboard=(await db.query('select public.my_dashboard() data')).rows[0].data;assert.equal(dashboard.operating_costs_kurus,'125000');assert.equal(dashboard.net_profit_kurus,'-125000');
 await db.exec('reset role');await db.query('update public.stores set level=15,xp=19600,cash_kurus=10000000 where id=$1',[store]);await auth();
 await action('office');state=await snap();assert.equal(state.employee_slots,3);assert.equal(state.brand_value,5);
 const adRequest=randomUUID(),ad=await action('campaign','social',0,adRequest);assert.equal(ad.cost_kurus,'25000');assert.ok(new Date(ad.ends_at)>new Date());
 assert.deepEqual(await action('campaign','social',0,adRequest),ad);await assert.rejects(()=>action('campaign','search'),e=>e.code==='B0006');
 const employee=await action('hire','sales');assert.equal(employee.cost_kurus,'20000');await assert.rejects(()=>action('hire','sales'),e=>e.code==='B0007');await action('hire','warehouse');await action('hire','analyst');await assert.rejects(()=>action('hire','logistics'),e=>e.code==='B0008');
 state=await snap();assert.equal(state.employees,3);assert.equal(state.effects.employee_conversion_bps,1800);assert.equal(state.effects.ad_traffic_bps,1000);assert.equal(state.brand_value,6);
 await action('fire','warehouse');state=await snap();assert.equal(state.employees,2);assert.equal(state.effects.employee_conversion_bps,1500);
 // Server-derived expiry removes bonuses even without visiting the company screen.
 await db.exec('reset role');const future=(await db.query("select public.business_effects($1,clock_timestamp()+interval '25 hours') data",[store])).rows[0].data;
 assert.equal(future.employee_conversion_bps,0);assert.equal(future.ad_traffic_bps,0);assert.equal(future.brand_price_bps,10120);
 const plain={brand_price_bps:10000,employee_conversion_bps:0,ad_traffic_bps:0,ad_conversion_bps:0};
 const probability=async(e,demand=50)=>(await db.query('select public.business_npc_probability($1,10000,10000,50,$2) p',[demand,e])).rows[0].p;
 assert.equal(Number(await probability(plain)),0.375);assert.ok(Number(await probability(state.effects))>0.375);assert.equal(Number(await probability(state.effects,0)),0);assert.equal(Number(await probability({...state.effects,brand_price_bps:12000,employee_conversion_bps:10000},100)),1);
 await db.query("update public.store_employees set paid_until=clock_timestamp()-interval '1 second' where store_id=$1",[store]);await auth();state=await snap();assert.equal(state.employees,0);await action('hire','sales');assert.equal((await snap()).employees,1);
 // Salary/advertising consume real cash; failures roll every economic change back.
 await db.exec('reset role');await db.exec(`create function public.fail_business_ledger() returns trigger language plpgsql as $$begin if new.idempotency_key like 'business:%' then raise exception 'rollback test';end if;return new;end;$$;create trigger fail_business_ledger before insert on public.transactions for each row execute function public.fail_business_ledger();`);
 const before={};for(const table of ['stores','transactions','business_receipts','store_xp_events','store_employees','store_campaigns'])before[table]=(await db.query('select * from public.'+table+' order by 1')).rows;
 await auth();await assert.rejects(()=>action('warehouse','upgrade',1),e=>e.code==='P0001');await db.exec('reset role');for(const table of Object.keys(before))assert.deepEqual((await db.query('select * from public.'+table+' order by 1')).rows,before[table]);await db.exec('drop trigger fail_business_ledger on public.transactions');
 await db.query('update public.stores set cash_kurus=0 where id=$1',[store]);await auth();await assert.rejects(()=>action('warehouse','upgrade',1),e=>e.code==='W0005');assert.deepEqual(await action('warehouse','upgrade',0,request),receipt);
 await auth(1);assert.equal((await db.query('select count(*)::int n from public.business_receipts')).rows[0].n,0);await assert.rejects(()=>db.query('select public.business_effects($1,now())',[store]),e=>e.code==='42501');await assert.rejects(()=>db.query('select public.my_dashboard_phase7()'),e=>e.code==='42501');
 for(const table of ['business_receipts','store_campaigns','store_employees','business_warehouses'])await assert.rejects(()=>db.exec('delete from public.'+table),e=>e.code==='42501');
 await db.exec('reset role');await assert.rejects(()=>db.exec("update public.business_receipts set code='bad'"),e=>e.code==='55000');
 // Actual NPC sale path still respects reservations, atomic COGS, XP and cooldown.
 const product=(await db.query("select id from public.products where name='Gel Pen Set'")).rows[0].id;
 await db.query('insert into public.inventory(store_id,product_id,quantity,reserved_quantity,average_cost_kurus) values($1,$2,2,1,50)',[store,product]);
 await db.query('update public.products set demand=100 where id=$1',[product]);
 await db.query("update public.stores set last_npc_tick_at=clock_timestamp()-interval '61 seconds' where id=$1",[store]);
 await auth();await db.query('select public.set_npc_listing($1,100,true)',[product]);let sale=(await db.query('select public.process_npc_sales() data')).rows[0].data;assert.equal(sale.sold,1);assert.equal(sale.profit_kurus,'50');assert.equal((await db.query('select public.process_npc_sales() data')).rows[0].data.sold,0);
 await db.exec('reset role');const inventory=(await db.query('select quantity,reserved_quantity from public.inventory where store_id=$1 and product_id=$2',[store,product])).rows[0];assert.deepEqual(inventory,{quantity:1,reserved_quantity:1});
 await db.query("update public.stores set last_npc_tick_at=clock_timestamp()-interval '1 day' where id=$1",[store]);await auth();assert.equal((await db.query('select public.process_npc_sales() data')).rows[0].data.sold,0);
 await db.exec('reset role');await db.exec('alter table public.store_campaigns disable trigger campaign_immutable');await db.query("update public.store_campaigns set starts_at=clock_timestamp()-interval '2 hours',ends_at=clock_timestamp()-interval '1 hour' where store_id=$1",[store]);await db.exec('alter table public.store_campaigns enable trigger campaign_immutable');
 await db.query('update public.stores set cash_kurus=10000000,brand_value=99 where id=$1',[store]);await auth();assert.equal((await snap()).active_campaign,null);assert.deepEqual(await action('campaign','social',0,adRequest),ad);await action('campaign','brand');assert.equal((await snap()).brand_value,100);
 await db.exec('reset role');
 const stored=(await db.query('select * from public.stores order by id')).rows;await db.exec(await readFile('supabase/migrations/011_business.sql','utf8'));assert.deepEqual((await db.query('select * from public.stores order by id')).rows,stored);
 await db.exec('set role anon');await assert.rejects(()=>db.query('select public.my_business()'),e=>e.code==='42501');
 console.log('PASS: business upgrades/assets/net profit, server level/cash/tier gates, idempotent receipts, paid employee slots/renewal/fire, ad overlap/expiry, real NPC probability modifiers/zero demand/cap, RLS/private RPC denial, migration replay, atomic ledger rollback.');
}catch(error){console.error(error.message,error.code);process.exitCode=1;}finally{await db.close();}
