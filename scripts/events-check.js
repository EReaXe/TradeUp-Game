import {PGlite} from '@electric-sql/pglite';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const db=new PGlite();
try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth,public to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
 for(const name of ['001_store_onboarding','002_database_core','003_dashboard','004_wholesale','005_inventory','006_npc_sales','007_marketplace'])await db.exec(await readFile('supabase/migrations/'+name+'.sql','utf8'));
 await db.exec(await readFile('supabase/seed.sql','utf8'));await db.exec(await readFile('supabase/migrations/008_economy.sql','utf8'));
 const migration=await readFile('supabase/migrations/009_market_events.sql','utf8');await db.exec(migration);
 const users=['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222'];
 const drop='00000000-0000-4000-8000-000000000101';
 async function auth(uid=users[0],role='authenticated'){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);await db.exec('set role '+role);}
 for(let i=0;i<users.length;i++){await db.query('insert into auth.users values($1)',[users[i]]);await auth(users[i]);await db.query('select public.complete_store_onboarding($1,$2)',['events_'+i,'Events '+i]);await db.exec('reset role');}
 const store=(await db.query('select id from public.stores where user_id=$1',[users[0]])).rows[0].id;
 await auth();let snapshot=(await db.query('select public.market_events_snapshot() data')).rows[0].data;
 assert.equal(snapshot.events.length,2);assert.equal(snapshot.offers.length,4);assert.equal(snapshot.receipts.length,0);
 assert.equal((await db.query('select public.wholesale_catalog() data')).rows[0].data.length,50);
 const flash=snapshot.offers.find(o=>o.kind==='FLASH_DEAL'&&new Date(o.starts_at)<=new Date(snapshot.as_of));
 const limited=snapshot.offers.find(o=>o.kind==='LIMITED_DROP'&&new Date(o.starts_at)<=new Date(snapshot.as_of));
 const future=snapshot.offers.find(o=>new Date(o.starts_at)>new Date(snapshot.as_of));
 const price=BigInt(flash.price_kurus);assert.equal(price,BigInt(flash.original_price_kurus)*70n/100n);
 async function purchase(offer,quantity=1,request=randomUUID(),expected=offer.price_kurus){return (await db.query('select public.buy_market_offer($1,$2,$3,$4) data',[offer.id,quantity,expected,request])).rows[0].data;}
 for(const sql of ['update public.market_events set supply_bps=1','update public.market_offers set remaining_quantity=100','update public.market_schedule set anchor_at=now()','delete from public.market_drop_products'])await assert.rejects(()=>db.exec(sql),e=>e.code==='42501');
 await assert.rejects(()=>db.query('select public.ensure_market_schedule(now())'),e=>e.code==='42501');
 await assert.rejects(()=>purchase(future),e=>e.code==='F0002');await assert.rejects(()=>purchase(flash,0),e=>e.code==='F0001');
 await assert.rejects(()=>purchase(flash,101),e=>e.code==='F0003');await assert.rejects(()=>purchase(flash,1,randomUUID(),'1'),e=>e.code==='W0007');
 await assert.rejects(()=>db.query('select public.buy_wholesale($1,1,180000,$2)',[drop,randomUUID()]),e=>e.code==='W0004');
 await db.exec('reset role');const stockBefore=(await db.query('select system_stock from public.products where id=$1',[flash.product_id])).rows[0].system_stock;
 await db.query('insert into public.inventory(store_id,product_id,quantity,average_cost_kurus) values($1,$2,1,10000)',[store,flash.product_id]);
 await db.query('update public.products set wholesale_price_kurus=wholesale_price_kurus+100 where id=$1',[flash.product_id]);
 await auth();const request=randomUUID(),receipt=await purchase(flash,2,request);assert.equal(receipt.total_kurus,(price*2n).toString());
 assert.deepEqual(await purchase(flash,2,request),receipt);await assert.rejects(()=>purchase(flash,1,request),e=>e.code==='W0008');
 const dropReceipt=await purchase(limited);assert.equal(dropReceipt.product_id,drop);
 assert.equal(receipt.unit_price_kurus,flash.price_kurus);
 await db.exec('reset role');assert.equal((await db.query('select system_stock from public.products where id=$1',[drop])).rows[0].system_stock,0);
 assert.equal((await db.query('select average_cost_kurus::text cost from public.inventory where store_id=$1 and product_id=$2',[store,flash.product_id])).rows[0].cost,((10000n+price*2n+1n)/3n).toString());
 assert.equal((await db.query('select system_stock from public.products where id=$1',[flash.product_id])).rows[0].system_stock,stockBefore-2);
 assert.equal((await db.query('select remaining_quantity from public.market_offers where id=$1',[limited.id])).rows[0].remaining_quantity,24);
 assert.equal((await db.query('select quantity from public.inventory where store_id=$1 and product_id=$2',[store,drop])).rows[0].quantity,1);
 const offersBefore=(await db.query('select * from public.market_offers order by id')).rows;await db.exec(migration);assert.deepEqual((await db.query('select * from public.market_offers order by id')).rows,offersBefore);
 await db.query("update public.market_offers set ends_at=clock_timestamp()-interval '1 second',starts_at=clock_timestamp()-interval '1 hour' where id=$1",[flash.id]);await auth();
 assert.deepEqual(await purchase(flash,2,request),receipt);await assert.rejects(()=>purchase(flash),e=>e.code==='F0002');
 // Purchases validate actual supplier stock, cash and capacity on the server.
 await db.exec('reset role');await db.query("update public.market_offers set ends_at=now()+interval '1 hour' where id=$1",[flash.id]);await db.query('update public.products set system_stock=0 where id=$1',[flash.product_id]);await auth();await assert.rejects(()=>purchase(flash),e=>e.code==='F0003');
 await db.exec('reset role');await db.query('update public.products set system_stock=100 where id=$1',[flash.product_id]);await db.query('update public.stores set cash_kurus=0 where id=$1',[store]);await auth();await assert.rejects(()=>purchase(flash),e=>e.code==='W0005');
 await db.exec('reset role');await db.query('update public.stores set cash_kurus=1000000,warehouse_capacity=4 where id=$1',[store]);await auth();await assert.rejects(()=>purchase(flash),e=>e.code==='W0006');
 await db.exec('reset role');await db.query('update public.stores set warehouse_capacity=50 where id=$1',[store]);
 // Ledger failure rolls back balance, supplier stock, offer quota, inventory and receipt.
 await db.exec(`create function public.fail_offer_ledger() returns trigger language plpgsql as $$begin if new.idempotency_key like 'offer:%' then raise exception 'test ledger failure';end if;return new;end;$$;
 create trigger fail_offer_ledger before insert on public.transactions for each row execute function public.fail_offer_ledger();`);
 const before={};for(const table of ['stores','products','market_offers','inventory','market_offer_receipts'])before[table]=(await db.query('select * from public.'+table)).rows;
 await auth();await assert.rejects(()=>purchase(flash),e=>e.code==='P0001');await db.exec('reset role');for(const table of Object.keys(before))assert.deepEqual((await db.query('select * from public.'+table)).rows,before[table]);await db.exec('drop trigger fail_offer_ledger on public.transactions');
 // An owned limited item can be listed and transferred through Marketplace.
 await auth();const listing=(await db.query('select public.create_marketplace_listing($1,1,252000,$2) id',[drop,randomUUID()])).rows[0].id;
 await auth(users[1]);assert.equal((await db.query('select count(*)::int n from public.market_offer_receipts')).rows[0].n,0);await db.query('select public.buy_marketplace_listing($1,1,252000,$2)',[listing,randomUUID()]);
 assert.equal((await db.query('select public.my_inventory() data')).rows[0].data.items.find(item=>item.product_id===drop).quantity,1);
 await db.exec('reset role');await assert.rejects(()=>db.exec('update public.market_offer_receipts set quantity=1'),e=>e.code==='55000');
 // Event modifiers are temporal, preserve price caps, and never refill limited stock.
 await db.exec("update public.economy_clock set last_tick_at=now()-interval '1 day';update public.products set system_stock=0 where category='Technology'");
 await auth();await db.query('select public.process_market_tick()');await db.exec('reset role');
 const technology=(await db.query("select p.*,e.reference_market_kurus,e.reference_supply from public.products p join public.product_economy e on e.product_id=p.id where category='Technology'")).rows;
 assert.equal(technology[0].system_stock,82);assert.ok(technology[0].market_price_kurus<=technology[0].reference_market_kurus*1.05);
 assert.equal((await db.query('select system_stock from public.products where id=$1',[drop])).rows[0].system_stock,0);
 // Ended and future category events must be ignored at the tick timestamp.
 await db.exec("update public.market_events set starts_at=now()-interval '2 hours',ends_at=now()-interval '1 hour' where slot=0;update public.economy_clock set last_tick_at=now()-interval '1 day'");await auth();await db.query('select public.process_market_tick()');await db.exec('reset role');
 assert.equal((await db.query("select system_stock from public.products where category='Technology' order by id limit 1")).rows[0].system_stock,207);
 await db.exec("update public.market_events set category='Gaming',starts_at=now()-interval '1 minute',ends_at=now()+interval '40 minutes',supply_bps=10000,demand_bps=14500,price_bps=10000 where slot=0;update public.economy_clock set last_tick_at=now()-interval '1 day'");
 await auth();await db.query('select public.process_market_tick()');await db.exec('reset role');
 const demand=(await db.query("select p.demand,e.reference_demand,c.tick from public.products p join public.product_economy e on e.product_id=p.id cross join public.economy_clock c where p.category='Gaming' order by p.id limit 1")).rows[0];
 const expectedDemand=Math.min(100,Math.round(demand.reference_demand*(1+0.20*Math.sin(demand.tick/6+7.1))*1.45));assert.equal(demand.demand,expectedDemand);
 // Long gaps generate only current/next batches, never every missed hour.
 const quota=(await db.query('select remaining_quantity from public.market_offers where id=$1',[limited.id])).rows[0].remaining_quantity;
 await db.exec("update public.market_schedule set anchor_at=anchor_at-interval '10 days';update public.economy_clock set last_tick_at=now()-interval '10 days'");await auth();await db.query('select public.process_market_tick()');await db.exec('reset role');
 assert.equal((await db.query('select count(*)::int n from public.market_events')).rows[0].n,4);assert.equal((await db.query('select remaining_quantity from public.market_offers where id=$1',[limited.id])).rows[0].remaining_quantity,quota);
 await auth('', 'anon');await assert.rejects(()=>db.query('select public.market_events_snapshot()'),e=>e.code==='42501');await auth('');await assert.rejects(()=>purchase(limited),e=>e.code==='28000');
 console.log('PASS: event schedule/expiry/modifiers and price caps, no offline batches, fixed flash price, offer timing/stock/funds/capacity/auth/RLS, idempotency after expiry, atomic ledger rollback, limited stock isolation and Marketplace resale.');
}finally{await db.close();}
