import {PGlite} from '@electric-sql/pglite';
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const db=new PGlite();
try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 grant usage on schema auth,public to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
 for(const name of ['001_store_onboarding','002_database_core','003_dashboard','004_wholesale','005_inventory','006_npc_sales','007_marketplace'])await db.exec(await readFile('supabase/migrations/'+name+'.sql','utf8'));
 await db.exec(await readFile('supabase/seed.sql','utf8'));
 const sql=await readFile('supabase/migrations/008_economy.sql','utf8');await db.exec(sql);
 const uid='11111111-1111-4111-8111-111111111111',id='00000000-0000-4000-8000-000000000001';
 await db.query('insert into auth.users values($1)',[uid]);
 async function user(value=uid,role='authenticated'){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[value]);await db.exec('set role '+role);}
 await user();await db.query("select public.complete_store_onboarding('economy','Economy Store')");
 let initial=(await db.query('select public.market_snapshot($1,$2) data',[id,'24H'])).rows[0].data;
 assert.equal(initial.products.length,50);assert.equal(initial.categories.length,8);assert.equal(initial.history.length,1);
 assert.equal((await db.query('select public.process_market_tick() data')).rows[0].data.updated,false);
 for(const query of ['update public.products set demand=100','update public.economy_clock set last_tick_at=now()-interval \'1 day\'','insert into public.price_history select * from public.price_history','select * from public.product_economy'])await assert.rejects(()=>db.exec(query),e=>e.code==='42501');
 await assert.rejects(()=>db.query('select public.market_snapshot($1,$2)',[id,'99D']),e=>e.code==='E0001');
 await assert.rejects(()=>db.query('select public.market_snapshot($1,$2)',['99999999-9999-4999-8999-999999999999','24H']),e=>e.code==='W0002');
 await user('', 'anon');await assert.rejects(()=>db.query('select public.process_market_tick()'),e=>e.code==='42501');
 await user('');await assert.rejects(()=>db.query('select public.process_market_tick()'),e=>e.code==='28000');
 await user('22222222-2222-4222-8222-222222222222');await assert.rejects(()=>db.query('select public.process_market_tick()'),e=>e.code==='W0001');
 await db.exec('reset role');await db.query('update public.products set system_stock=0 where id=$1',[id]);
 const cash=(await db.query('select sum(cash_kurus)::text value from public.stores')).rows[0].value;
 const ledger=(await db.query('select count(*)::int value from public.transactions')).rows[0].value;
 for(let i=0;i<35;i++){
  await db.exec("reset role;update public.economy_clock set last_tick_at=now()-interval '1 day'");
  const before=(await db.query('select id,market_price_kurus::text market,wholesale_price_kurus::text wholesale,system_stock from public.products order by id')).rows;
  await user();const tick=(await db.query('select public.process_market_tick() data')).rows[0].data;assert.equal(tick.updated,true);assert.equal(tick.tick,i+1);
  assert.equal((await db.query('select public.process_market_tick() data')).rows[0].data.updated,false);
  await db.exec('reset role');
  const after=(await db.query('select p.id,p.market_price_kurus::text market,p.wholesale_price_kurus::text wholesale,p.demand,p.supply,p.system_stock,e.reference_market_kurus::text baseline from public.products p join public.product_economy e on e.product_id=p.id order by p.id')).rows;
  for(let j=0;j<after.length;j++){for(const key of ['market','wholesale']){const old=BigInt(before[j][key]),next=BigInt(after[j][key]);assert.ok(next*100n>=old*95n&&next*100n<=old*105n);}assert.ok(BigInt(after[j].market)*2n>=BigInt(after[j].baseline)&&BigInt(after[j].market)<=BigInt(after[j].baseline)*2n);assert.ok(after[j].demand>=0&&after[j].demand<=100);assert.ok(after[j].supply>=0&&after[j].supply<=100);}
  if(i===0){assert.equal(after[0].system_stock,125);assert.ok(BigInt(after[0].market)>BigInt(before[0].market));
   await user();await assert.rejects(()=>db.query('select public.buy_wholesale($1,1,$2,$3)',[id,before[0].wholesale,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa']),e=>e.code==='W0007');await db.exec('reset role');}
 }
 assert.equal((await db.query('select count(*)::int n from public.price_history')).rows[0].n,1800);
 assert.equal((await db.query('select sum(cash_kurus)::text value from public.stores')).rows[0].value,cash);
 assert.equal((await db.query('select count(*)::int value from public.transactions')).rows[0].value,ledger);
 const before=(await db.query('select * from public.economy_clock')).rows;await db.exec(sql);assert.deepEqual((await db.query('select * from public.economy_clock')).rows,before);
 assert.equal((await db.query('select count(*)::int n from public.price_history')).rows[0].n,1800);
 // A failed history write must roll back prices, replenishment and the clock together.
 await db.exec(`create function public.fail_history() returns trigger language plpgsql as $$begin raise exception 'test history failure';end;$$;
 create trigger fail_history before insert on public.price_history for each row execute function public.fail_history();
 update public.economy_clock set last_tick_at=now()-interval '1 day';`);
 const stockBefore=(await db.query('select * from public.products order by id')).rows;
 const clockBefore=(await db.query('select * from public.economy_clock')).rows;
 await user();await assert.rejects(()=>db.query('select public.process_market_tick()'),e=>e.code==='P0001');await db.exec('reset role');
 assert.deepEqual((await db.query('select * from public.products order by id')).rows,stockBefore);assert.deepEqual((await db.query('select * from public.economy_clock')).rows,clockBefore);
 await db.exec('drop trigger fail_history on public.price_history');
 // Sparse histories only include real rows, with latest value per UTC bucket.
 await db.query("update public.price_history set recorded_at=now()-case tick when 0 then interval '30 minutes' when 1 then interval '6 hours' when 2 then interval '2 days' when 3 then interval '8 days' else interval '40 days' end where product_id=$1",[id]);
 await user();for(const [window,length] of [['1H',1],['24H',2],['7D',3],['30D',4]]){const snapshot=(await db.query('select public.market_snapshot($1,$2) data',[id,window])).rows[0].data;assert.equal(snapshot.history.length,length);assert.equal(snapshot.selected_product,id);}
 await db.exec('reset role');const expected=(await db.query('select round(avg((p.market_price_kurus::numeric/e.reference_market_kurus-1)*100),2)::text pct from public.products p join public.product_economy e on e.product_id=p.id where category=\'Technology\'')).rows[0].pct;
 await user();const snapshot=(await db.query('select public.market_snapshot() data')).rows[0].data;assert.equal(Number(snapshot.categories.find(item=>item.category==='Technology').change_pct),Number(expected));
 await db.exec("reset role;update public.economy_clock set last_tick_at=now()-interval '1 day'");await db.query('update public.products set active=false where id=$1',[id]);
 const inactive=(await db.query('select * from public.products where id=$1',[id])).rows;
 await user();await db.query('select public.process_market_tick()');await assert.rejects(()=>db.query('select public.market_snapshot($1)',[id]),e=>e.code==='W0002');await db.exec('reset role');assert.deepEqual((await db.query('select * from public.products where id=$1',[id])).rows,inactive);
 console.log('PASS: economy cooldown, no offline catch-up, 35-step price bounds, capped supplier refill, demand/supply ranges, real price history windows, category trends, cash/ledger conservation, RLS/auth, migration replay and atomic rollback.');
}finally{await db.close();}
