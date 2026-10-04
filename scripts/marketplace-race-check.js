import EmbeddedPostgres from 'embedded-postgres';
import {readFile,mkdir} from 'node:fs/promises';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const root=path.resolve('.test-db-race');const databaseDir=path.join(root,'run-'+randomUUID());
assert.ok(databaseDir.startsWith(root+path.sep));await mkdir(root,{recursive:true});
const cluster=new EmbeddedPostgres({databaseDir,user:'race_test',password:randomUUID(),port:55439,persistent:true,createPostgresUser:false,initdbFlags:['--locale=C','--encoding=UTF8'],postgresFlags:['-h','127.0.0.1'],onLog:()=>{},onError:()=>{}});
let admin,a,b,started=false;
try{
 await cluster.initialise();await cluster.start();started=true;
 admin=cluster.getPgClient('postgres','127.0.0.1');a=cluster.getPgClient('postgres','127.0.0.1');b=cluster.getPgClient('postgres','127.0.0.1');
 await Promise.all([admin.connect(),a.connect(),b.connect()]);
 await admin.query(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 grant usage on schema auth,public to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
 for(const name of ['001_store_onboarding','002_database_core','003_dashboard','004_wholesale','005_inventory','006_npc_sales','007_marketplace'])await admin.query(await readFile('supabase/migrations/'+name+'.sql','utf8'));
 await admin.query(await readFile('supabase/seed.sql','utf8'));
 const users=[randomUUID(),randomUUID(),randomUUID()];
 const product='00000000-0000-4000-8000-000000000001';
 for(let i=0;i<3;i++){await admin.query('insert into auth.users values($1)',[users[i]]);await admin.query("select set_config('request.jwt.claim.sub',$1,false)",[users[i]]);await admin.query('select public.complete_store_onboarding($1,$2)',['race_'+i,'Race Store '+i]);}
 const stores=[];for(const uid of users)stores.push((await admin.query('select id from public.stores where user_id=$1',[uid])).rows[0].id);
 async function auth(client,uid){await client.query('reset role');await client.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);await client.query('set role authenticated');}
 async function listing(){await admin.query('insert into public.inventory(store_id,product_id,quantity,average_cost_kurus) values($1,$2,1,1000) on conflict(store_id,product_id) do update set quantity=inventory.quantity+1',[stores[0],product]);await admin.query("select set_config('request.jwt.claim.sub',$1,false)",[users[0]]);return (await admin.query('select public.create_marketplace_listing($1,1,10000,$2) id',[product,randomUUID()])).rows[0].id;}
 async function purchase(client,id,key){return client.query('select public.buy_marketplace_listing($1,1,10000,$2) data',[id,key]);}
 async function lockObserved(){for(let i=0;i<100;i++){const result=await admin.query('select wait_event_type from pg_stat_activity where pid=$1',[b.processID]);if(result.rows[0]?.wait_event_type==='Lock')return;await new Promise(resolve=>setTimeout(resolve,10));}throw new Error('Second session never blocked on a PostgreSQL lock');}
 const id=await listing();await auth(a,users[1]);await auth(b,users[2]);
 await a.query('begin');const won=await purchase(a,id,randomUUID());
 const losing=purchase(b,id,randomUUID()).then(value=>({value}),error=>({error}));await lockObserved();await a.query('commit');assert.equal((await losing).error?.code,'M0005');
 assert.equal(won.rows[0].data.fee_kurus,'500');assert.equal((await admin.query('select quantity from public.marketplace_listings where id=$1',[id])).rows[0].quantity,0);
 // Duplicate request in a separate session must return the exact receipt, not another transfer.
 const second=await listing();const key=randomUUID();await auth(b,users[1]);await a.query('begin');const original=await purchase(a,second,key);
 const retry=purchase(b,second,key);await lockObserved();await a.query('commit');assert.deepEqual((await retry).rows[0].data,original.rows[0].data);
 assert.equal((await admin.query('select count(*)::int n from public.marketplace_receipts')).rows[0].n,2);
 // Two distinct listings compete for the same buyer's final warehouse slot.
 const third=await listing();const fourth=await listing();await admin.query('update public.stores set warehouse_capacity=3 where id=$1',[stores[1]]);
 await a.query('begin');await purchase(a,third,randomUUID());const full=purchase(b,fourth,randomUUID()).then(value=>({value}),error=>({error}));await lockObserved();await a.query('commit');assert.equal((await full).error?.code,'W0006');
 // Cancel wins while a buyer waits: reserved units released exactly once, purchase rejected.
 await admin.query('update public.stores set warehouse_capacity=50 where id=$1',[stores[1]]);await auth(a,users[0]);await a.query('begin');await a.query('select public.cancel_marketplace_listing($1)',[fourth]);
 const cancelled=purchase(b,fourth,randomUUID()).then(value=>({value}),error=>({error}));await lockObserved();await a.query('commit');assert.equal((await cancelled).error?.code,'M0005');
 assert.equal((await admin.query('select reserved_quantity from public.inventory where store_id=$1 and product_id=$2',[stores[0],product])).rows[0].reserved_quantity,0);
 assert.equal((await admin.query('select count(*)::int n from public.marketplace_receipts')).rows[0].n,3);
 const cash=(await admin.query('select sum(cash_kurus)::text n from public.stores')).rows[0].n;assert.equal(cash,'2998500');
 // Economy uses a global clock: simultaneous callers advance it exactly once.
 await admin.query(await readFile('supabase/migrations/008_economy.sql','utf8'));
 await admin.query("update public.economy_clock set last_tick_at=now()-interval '1 day'");
 await auth(a,users[0]);await auth(b,users[1]);await a.query('begin');
 const market=await a.query('select public.process_market_tick() data');assert.equal(market.rows[0].data.updated,true);
 const duplicateTick=b.query('select public.process_market_tick() data');await lockObserved();await a.query('commit');
 assert.equal((await duplicateTick).rows[0].data.updated,false);
 assert.equal((await admin.query('select tick from public.economy_clock')).rows[0].tick,'1');
 assert.equal((await admin.query('select count(*)::int n from public.price_history where tick=1')).rows[0].n,50);
 assert.equal((await admin.query('select sum(cash_kurus)::text n from public.stores')).rows[0].n,cash);
 // Wholesale holds its product lock while economy waits; no lost supplier decrement.
 await admin.query('update public.products set system_stock=100 where id=$1',[product]);
 await auth(a,users[1]);await a.query('begin');
 const price=(await admin.query('select wholesale_price_kurus::text p,system_stock from public.products where id=$1',[product])).rows[0];
 await a.query('select public.buy_wholesale($1,1,$2,$3)',[product,price.p,randomUUID()]);
 await admin.query("update public.economy_clock set last_tick_at=now()-interval '1 day'");
 const waitingMarket=b.query('select public.process_market_tick() data');await lockObserved();await a.query('commit');
 assert.equal((await waitingMarket).rows[0].data.updated,true);
 assert.equal((await admin.query('select system_stock from public.products where id=$1',[product])).rows[0].system_stock,224);
 console.log('PASS: economy independent-session global cooldown and wholesale/product-lock contention, one history batch, no lost stock updates.');
 await admin.query(await readFile('supabase/migrations/009_market_events.sql','utf8'));
 const offer=(await admin.query("select * from public.market_offers where kind='FLASH_DEAL' and starts_at<=now() order by starts_at limit 1")).rows[0];
 await admin.query('update public.market_offers set remaining_quantity=1 where id=$1',[offer.id]);
 await auth(a,users[0]);await auth(b,users[2]);await a.query('begin');
 const offerRequest=randomUUID();const bought=await a.query('select public.buy_market_offer($1,1,$2,$3) data',[offer.id,offer.price_kurus,offerRequest]);
 const exhausted=b.query('select public.buy_market_offer($1,1,$2,$3)',[offer.id,offer.price_kurus,randomUUID()]).then(value=>({value}),error=>({error}));await lockObserved();await a.query('commit');assert.equal((await exhausted).error?.code,'F0003');
 assert.equal((await admin.query('select remaining_quantity from public.market_offers where id=$1',[offer.id])).rows[0].remaining_quantity,0);
 // A concurrent same-request retry returns one receipt even after the offer sells out.
 await auth(b,users[0]);await a.query('begin');const firstRetry=await a.query('select public.buy_market_offer($1,1,$2,$3) data',[offer.id,offer.price_kurus,offerRequest]);
 const secondRetry=b.query('select public.buy_market_offer($1,1,$2,$3) data',[offer.id,offer.price_kurus,offerRequest]);await lockObserved();await a.query('commit');assert.deepEqual((await secondRetry).rows[0].data,firstRetry.rows[0].data);assert.deepEqual(firstRetry.rows[0].data,bought.rows[0].data);
 // A request started before expiry must still fail if the product lock delays it past expiry.
 await auth(b,users[2]);await admin.query("update public.market_offers set remaining_quantity=1,ends_at=clock_timestamp()+interval '500 milliseconds' where id=$1",[offer.id]);
 await a.query('begin');await admin.query('reset role');
 // Use a privileged transaction to hold the product, not an artificial client clock.
 await a.query('reset role');await a.query('select id from public.products where id=$1 for update',[offer.product_id]);
 const expired=b.query('select public.buy_market_offer($1,1,$2,$3)',[offer.id,offer.price_kurus,randomUUID()]).then(value=>({value}),error=>({error}));await lockObserved();
 const beganBeforeEnd=(await admin.query('select a.xact_start<o.ends_at before_expiry from pg_stat_activity a cross join public.market_offers o where a.pid=$1 and o.id=$2',[b.processID,offer.id])).rows[0].before_expiry;assert.equal(beganBeforeEnd,true);
 await new Promise(resolve=>setTimeout(resolve,700));
 assert.equal((await admin.query('select clock_timestamp()>ends_at expired from public.market_offers where id=$1',[offer.id])).rows[0].expired,true);
 await a.query('commit');assert.equal((await expired).error?.code,'F0002');
 assert.equal((await admin.query('select count(*)::int n from public.market_offer_receipts')).rows[0].n,1);
 console.log('PASS: offers independent-session last-unit race, concurrent idempotent retries and server-time expiry after lock contention.');
 await admin.query(await readFile('supabase/migrations/010_progression.sql','utf8'));
 await admin.query('update public.stores set warehouse_capacity=1000,cash_kurus=10000000');
 const supplier=(await admin.query('select wholesale_price_kurus from public.products where id=$1',[product])).rows[0];
 await auth(a,users[0]);await a.query('select public.buy_wholesale($1,10,$2,$3)',[product,supplier.wholesale_price_kurus,randomUUID()]);
 const progress=(await a.query('select public.my_progression() data')).rows[0].data;
 const period=progress.missions.find(m=>m.code==='daily_buy').period_start;
 await auth(b,users[0]);await a.query('begin');
 const reward=(await a.query("select public.claim_progression_mission('daily_buy',$1) data",[period])).rows[0].data;
 const rewardRetry=b.query("select public.claim_progression_mission('daily_buy',$1) data",[period]);await lockObserved();await a.query('commit');
 assert.deepEqual((await rewardRetry).rows[0].data,reward);
 assert.equal((await admin.query("select count(*)::int n from public.transactions where store_id=$1 and idempotency_key like 'mission:daily_buy:%'",[stores[0]])).rows[0].n,1);
 await admin.query('update public.stores set level=5,xp=1600');
 const forward=await listing();
 await admin.query('insert into public.inventory(store_id,product_id,quantity,average_cost_kurus) values($1,$2,1,1000) on conflict(store_id,product_id) do update set quantity=inventory.quantity+1',[stores[1],product]);
 await auth(a,users[1]);const backward=(await a.query('select public.create_marketplace_listing($1,1,10000,$2) id',[product,randomUUID()])).rows[0].id;
 await auth(b,users[0]);await a.query('begin');await purchase(a,forward,randomUUID());
 const opposite=purchase(b,backward,randomUUID());await lockObserved();await a.query('commit');assert.equal((await opposite).rows[0].data.fee_kurus,'500');
 console.log('PASS: progression independent-session mission reward replay (one cash ledger), opposite-direction Marketplace trades with sorted store locks.');
 await admin.query(await readFile('supabase/migrations/011_business.sql','utf8'));
 await auth(a,users[0]);await auth(b,users[0]);await a.query('begin');const upgradeKey=randomUUID();
 const upgrade=(await a.query("select public.business_action('warehouse','upgrade',0,$1) data",[upgradeKey])).rows[0].data;
 const upgradeRetry=b.query("select public.business_action('warehouse','upgrade',0,$1) data",[upgradeKey]);await lockObserved();await a.query('commit');assert.deepEqual((await upgradeRetry).rows[0].data,upgrade);
 assert.equal((await admin.query("select count(*)::int n from public.transactions where store_id=$1 and type='WAREHOUSE_UPGRADE'",[stores[0]])).rows[0].n,1);
 await admin.query('update public.stores set level=15,xp=19600 where id=$1',[stores[0]]);await a.query('begin');await a.query("select public.business_action('hire','sales',0,$1)",[randomUUID()]);
 const slotRace=b.query("select public.business_action('hire','warehouse',0,$1)",[randomUUID()]).then(value=>({value}),error=>({error}));await lockObserved();await a.query('commit');assert.equal((await slotRace).error?.code,'B0008');
 await a.query('begin');await a.query("select public.business_action('campaign','social',0,$1)",[randomUUID()]);
 const adRace=b.query("select public.business_action('campaign','search',0,$1)",[randomUUID()]).then(value=>({value}),error=>({error}));await lockObserved();await a.query('commit');assert.equal((await adRace).error?.code,'B0006');
 console.log('PASS: business independent-session upgrade replay charges once, final employee slot and single active campaign contention.');
 await admin.query(await readFile('supabase/migrations/012_advanced_trading.sql','utf8'));
 const rare=(await admin.query("select id from public.products where rarity='Rare' order by id limit 1")).rows[0].id;
 await admin.query('insert into public.inventory(store_id,product_id,quantity,average_cost_kurus) values($1,$2,2,1000)',[stores[0],rare]);
 await auth(a,users[0]);const serial=(await a.query("select public.trade_action('serialize',$1,$2) data",[{product_id:rare},randomUUID()])).rows[0].data;
 const auction=(await a.query("select public.trade_action('auction_create',$1,$2) data",[{serial_id:serial.serial_id,price_kurus:'10000',duration_minutes:5},randomUUID()])).rows[0].data.id;
 await auth(a,users[1]);await auth(b,users[2]);await a.query('begin');await a.query("select public.trade_action('auction_bid',$1,$2)",[{id:auction,amount_kurus:'10000'},randomUUID()]);
 const waitingBid=b.query("select public.trade_action('auction_bid',$1,$2)",[{id:auction,amount_kurus:'11000'},randomUUID()]).then(value=>({value}),error=>({error}));await lockObserved();await a.query('commit');assert.equal((await waitingBid).error?.code,'T0012');
 await b.query("select public.trade_action('auction_bid',$1,$2)",[{id:auction,amount_kurus:'11000'},randomUUID()]);
 assert.equal((await admin.query('select trading_escrow_kurus::text amount from public.stores where id=$1',[stores[1]])).rows[0].amount,'0');
 assert.equal((await admin.query('select trading_escrow_kurus::text amount from public.stores where id=$1',[stores[2]])).rows[0].amount,'11000');
 await admin.query("update public.player_auctions set ends_at=clock_timestamp()-interval '1 second' where id=$1",[auction]);await auth(a,users[2]);await a.query('begin');const claimId=randomUUID();
 const wonAuction=(await a.query("select public.trade_action('auction_claim',$1,$2) data",[{id:auction},claimId])).rows[0].data;
 const claimAgain=b.query("select public.trade_action('auction_claim',$1,$2) data",[{id:auction},claimId]);await lockObserved();await a.query('commit');assert.deepEqual((await claimAgain).rows[0].data,wonAuction);
 console.log('PASS: advanced trading independent-session bid change retry, outbid escrow refund and concurrent winner claim charges/transfers once.');
 console.log('PASS: real PostgreSQL independent-session lock contention, last-stock race, duplicate request race, warehouse-capacity race, cancel/buy race and fee conservation. Local auth.uid emulation; no Supabase player writes.');
}finally{
 for(const client of [a,b]){if(client){try{await client.query('rollback');}catch{}}}
 await Promise.allSettled([a?.end(),b?.end(),admin?.end()]);if(started)await cluster.stop();
}
