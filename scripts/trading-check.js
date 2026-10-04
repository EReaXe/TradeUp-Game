import {PGlite} from '@electric-sql/pglite';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const db=new PGlite();
try{
 await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth,public to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
 for(const name of ['001_store_onboarding','002_database_core','003_dashboard','004_wholesale','005_inventory','006_npc_sales','007_marketplace'])await db.exec(await readFile('supabase/migrations/'+name+'.sql','utf8'));
 await db.exec(await readFile('supabase/seed.sql','utf8'));
 for(const name of ['008_economy','009_market_events','010_progression','011_business','012_advanced_trading'])await db.exec(await readFile('supabase/migrations/'+name+'.sql','utf8'));
 const users=[randomUUID(),randomUUID(),randomUUID()];async function auth(i=0){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[users[i]]);await db.exec('set role authenticated');}
 for(let i=0;i<3;i++){await db.query('insert into auth.users values($1)',[users[i]]);await auth(i);await db.query('select public.complete_store_onboarding($1,$2)',['business_'+i,'Business '+i]);await db.exec('reset role');}
 const stores=(await db.query('select id from public.stores order by store_name')).rows.map(x=>x.id);
 await db.exec('update public.stores set level=5,xp=1600,cash_kurus=10000000');
 const product=(await db.query("select id from public.products where rarity='Rare' order by id limit 1")).rows[0].id;
 await db.query('insert into public.inventory(store_id,product_id,quantity,average_cost_kurus) values($1,$2,5,1000)',[stores[0],product]);
 const action=async(name,payload,key=randomUUID())=>(await db.query('select public.trade_action($1,$2,$3) data',[name,payload,key])).rows[0].data;
 const snap=async()=>(await db.query('select public.my_advanced_trading() data')).rows[0].data;
 await auth();const serialKey=randomUUID(),serial=await action('serialize',{product_id:product},serialKey);assert.deepEqual(await action('serialize',{product_id:product},serialKey),serial);
 const auction=(await action('auction_create',{serial_id:serial.serial_id,price_kurus:'10000',duration_minutes:5})).id;
 await assert.rejects(()=>action('auction_bid',{id:auction,amount_kurus:'10000'}),e=>e.code==='T0008');
 await auth(1);const bidKey=randomUUID(),bid=await action('auction_bid',{id:auction,amount_kurus:'10000'},bidKey);assert.deepEqual(await action('auction_bid',{id:auction,amount_kurus:'10000'},bidKey),bid);
 assert.equal((await snap()).escrow_kurus,'10000');const worth=(await db.query('select public.my_net_worth_kurus() worth')).rows[0].worth;assert.equal(Number(worth),10000000);
 assert.equal((await db.query('select public.my_dashboard() data')).rows[0].data.net_worth_kurus,'10000000');
 await auth(2);await assert.rejects(()=>action('auction_bid',{id:auction,amount_kurus:'10499'}),e=>e.code==='T0009');await action('auction_bid',{id:auction,amount_kurus:'10500'});
 await auth(1);assert.equal((await snap()).escrow_kurus,'0');assert.equal((await snap()).cash_kurus,'10000000');
 await db.exec('reset role');await db.query("update public.player_auctions set ends_at=clock_timestamp()-interval '1 second' where id=$1",[auction]);
 await auth(1);await assert.rejects(()=>action('auction_claim',{id:auction}),e=>e.code==='T0011');await assert.rejects(()=>action('auction_bid',{id:auction,amount_kurus:'11000'}),e=>e.code==='T0008');
 await db.exec('reset role');await db.query('update public.stores set warehouse_capacity=1 where id=$1',[stores[2]]);await db.query('insert into public.inventory(store_id,product_id,quantity,average_cost_kurus) values($1,$2,1,1000)',[stores[2],product]);await auth(2);await assert.rejects(()=>action('auction_claim',{id:auction}),e=>e.code==='W0006');assert.equal((await snap()).escrow_kurus,'10500');
 await db.exec('reset role');await db.query('update public.stores set warehouse_capacity=50 where id=$1',[stores[2]]);await auth(2);const claimKey=randomUUID(),claim=await action('auction_claim',{id:auction},claimKey);assert.equal(claim.fee_kurus,'525');assert.deepEqual(await action('auction_claim',{id:auction},claimKey),claim);assert.equal((await snap()).serials[0].serial_number,serial.serial_number);assert.equal((await snap()).escrow_kurus,'0');
 await db.exec('reset role');assert.equal((await db.query('select reserved_quantity from public.inventory where store_id=$1 and product_id=$2',[stores[2],product])).rows[0].reserved_quantity,1);
 await auth();const contract=(await action('contract_create',{recipient:'Business 1',product_id:product,quantity:2,price_kurus:'20000'})).id;
 assert.equal((await db.query('select public.my_marketplace() data')).rows[0].data.listings.length,0);
 await auth(2);await assert.rejects(()=>action('contract_accept',{id:contract}),e=>e.code==='T0007');assert.equal((await snap()).contracts.length,0);
 await auth(1);const accepted=await action('contract_accept',{id:contract});assert.equal(accepted.status,'accepted');assert.equal(accepted.fee_kurus,'2000');
 await auth();const reject=(await action('contract_create',{recipient:'Business 1',product_id:product,quantity:1,price_kurus:'10000'})).id;
 await auth(1);assert.equal((await action('contract_decline',{id:reject})).status,'declined');
 await auth();const exp=(await action('contract_create',{recipient:'Business 1',product_id:product,quantity:1,price_kurus:'10000'})).id;await db.exec('reset role');await db.query("update public.player_contracts set ends_at=clock_timestamp()-interval '1 second' where id=$1",[exp]);await auth(1);assert.equal((await action('contract_accept',{id:exp})).status,'expired');
 // Failure in escrow ledger must roll back cash, refund and the highest bid.
 await auth();const serial2=await action('serialize',{product_id:product});const auction2=(await action('auction_create',{serial_id:serial2.serial_id,price_kurus:'10000',duration_minutes:5})).id;
 await auth(1);await action('auction_bid',{id:auction2,amount_kurus:'10000'});
 await db.exec('reset role');await db.exec(`create function public.fail_bid() returns trigger language plpgsql as $$begin if new.type='ESCROW_HOLD' then raise exception 'test rollback';end if;return new;end;$$;create trigger fail_bid before insert on public.transactions for each row execute function public.fail_bid();`);
 const before=(await db.query('select * from public.stores order by id')).rows;await auth(2);await assert.rejects(()=>action('auction_bid',{id:auction2,amount_kurus:'11000'}),e=>e.code==='P0001');await db.exec('reset role');assert.deepEqual((await db.query('select * from public.stores order by id')).rows,before);await db.exec('drop trigger fail_bid on public.transactions');
 await db.query("update public.player_auctions set ends_at=clock_timestamp()-interval '25 hours' where id=$1",[auction2]);await auth();assert.equal((await action('auction_cancel',{id:auction2})).status,'cancelled');await auth(1);assert.equal((await snap()).escrow_kurus,'0');
 for(const table of ['serial_items','player_auctions','player_contracts','trading_receipts'])await assert.rejects(()=>db.exec('delete from public.'+table),e=>e.code==='42501');
 await assert.rejects(()=>db.query('select public.trading_escrow($1,1,$2)',[stores[1],'bad']),e=>e.code==='42501');
 await db.exec('reset role');await db.exec(await readFile('supabase/migrations/012_advanced_trading.sql','utf8'));await auth();assert.equal((await snap()).serials.length,1);
 // NPC can sell the remaining fungible unit, never the serialized reserved unit.
 await db.exec('reset role');await db.query('update public.products set demand=100 where id=$1',[product]);await db.query("update public.stores set last_npc_tick_at=clock_timestamp()-interval '61 seconds' where id=$1",[stores[0]]);
 await auth();await db.query('select public.set_npc_listing($1,1,true)',[product]);assert.equal((await db.query('select public.process_npc_sales() data')).rows[0].data.sold,1);
 await assert.rejects(()=>db.query('select public.set_npc_listing($1,1,true)',[product]),e=>e.code==='N0002');
 assert.equal((await snap()).serials.length,1);assert.equal((await snap()).items.find(x=>x.id===product).available,0);
 console.log('PASS: serial custody/retry/transfer, auction bid increments/refunds/escrow net-worth/winner/expiry/fees/idempotency, contract privacy/accept/reject/expiry, ledger rollback, RLS/private RPC and migration replay.');
}catch(error){console.error(error.message,error.code);process.exitCode=1;}finally{await db.close();}
