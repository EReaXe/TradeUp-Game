import {getSupabase} from './supabase.js';
import {moneyFromKurus,setStatus} from './utils.js';
const section=document.querySelector('#dashboard');
const status=document.querySelector('#dashboard-status');
const content=document.querySelector('#dashboard-content');
const refresh=document.querySelector('#dashboard-refresh');
const migration=document.querySelector('#dashboard-migration');
let loading=false;
const integer=value=>new Intl.NumberFormat('tr-TR').format(BigInt(value));
const dateTime=value=>new Intl.DateTimeFormat('tr-TR',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Istanbul'}).format(new Date(value));
const labels={INITIAL_CAPITAL:'Başlangıç sermayesi',WHOLESALE_PURCHASE:'Toptan alım',NPC_SALE:'NPC satışı',MARKETPLACE_SALE:'Marketplace satışı',MARKETPLACE_PURCHASE:'Marketplace alımı',MARKETPLACE_FEE:'Marketplace komisyonu',WAREHOUSE_UPGRADE:'Depo yükseltmesi',OFFICE_UPGRADE:'Ofis yükseltmesi',ADVERTISEMENT:'Reklam',SALARY:'Maaş',LOAN:'Kredi',LOAN_PAYMENT:'Kredi ödemesi',REWARD:'Ödül',ESCROW_HOLD:'Teklif için bloke',ESCROW_REFUND:'Teklif blokesinin iadesi'};
function text(id,value){document.querySelector('#'+id).textContent=value;}
function render(data){
 for(const [id,key] of [['kpi-cash','cash_kurus'],['kpi-worth','net_worth_kurus'],['kpi-revenue','revenue_kurus'],['stock-value','inventory_value_kurus'],['stock-cost','inventory_cost_kurus']]) text(id,moneyFromKurus(data[key]));
 const profit=data.net_profit_kurus===undefined?data.profit_kurus:data.net_profit_kurus;
 text('kpi-profit',profit===null?'—':moneyFromKurus(profit));
 text('profit-note',data.profit_kurus===null?'Satış maliyeti verisi bekleniyor':data.operating_costs_kurus!==undefined?'Satış kârı − işletme giderleri ('+moneyFromKurus(data.operating_costs_kurus)+')':BigInt(data.orders)===0n?'Bugün henüz satış yok':'Satış geliri − maliyet − Marketplace komisyonu');
 text('kpi-orders',integer(data.orders));text('kpi-inventory',integer(data.inventory_units));
 text('dashboard-store',data.store_name);text('store-level','Seviye '+data.level);text('store-reputation',data.reputation+' / 100');
 text('stock-units',integer(data.inventory_units)+' / '+integer(data.warehouse_capacity)+' ürün');
 const meter=document.querySelector('#warehouse-meter');meter.max=data.warehouse_capacity;meter.value=Number(data.inventory_units);
 text('updated-at','Son güncelleme: '+dateTime(data.as_of)+' · İstanbul');
 const activity=document.querySelector('#dashboard-activity');activity.replaceChildren();
 if(!data.activity.length){const p=document.createElement('p');p.className='muted';p.textContent='Henüz bir işlem yok.';activity.append(p);}
 for(const item of data.activity){
  const row=document.createElement('div');row.className='row';const description=document.createElement('div');
  const title=document.createElement('strong');title.textContent=labels[item.type]||item.type;
  const date=document.createElement('small');date.className='muted';date.textContent=dateTime(item.created_at);description.append(title,date);
  const amount=document.createElement('span');amount.className=BigInt(item.amount_kurus)>=0n?'positive':'muted';amount.textContent=moneyFromKurus(item.amount_kurus);row.append(description,amount);activity.append(row);
 }
 const body=document.querySelector('#revenue-history');body.replaceChildren();
 for(const day of data.history){const row=document.createElement('tr');for(const value of [new Intl.DateTimeFormat('tr-TR',{day:'numeric',month:'short',timeZone:'Europe/Istanbul'}).format(new Date(day.date+'T12:00:00+03:00')),moneyFromKurus(day.revenue_kurus),integer(day.orders)]){const td=document.createElement('td');td.textContent=value;row.append(td);}body.append(row);}
 content.hidden=false;
}
async function load(){
 if(loading || document.querySelector('#game-shell').hidden) return;
 loading=true;refresh.disabled=true;section.setAttribute('aria-busy','true');content.hidden=true;migration.hidden=true;setStatus(status,'Mağaza verileri yükleniyor…');
 try{const client=await getSupabase();if(!client) throw new Error('Missing config');const {data,error}=await client.rpc('my_dashboard');if(error)throw error;render(data);setStatus(status,'Mağaza verileri güncel.','success');}
 catch(error){
  if(error.code==='PGRST202'){migration.hidden=false;setStatus(status,'Dashboard için 003_dashboard.sql migration dosyasını Supabase SQL Editor’da çalıştırın.','error');}
  else setStatus(status,'Mağaza verileri yüklenemedi. Bağlantınızı kontrol edip yeniden deneyin.','error');
 }
 finally{loading=false;refresh.disabled=false;section.setAttribute('aria-busy','false');}
}
refresh.addEventListener('click',load);
window.addEventListener('tradeup:store-ready',load);
window.addEventListener('hashchange',()=>{if(location.hash==='#dashboard')load();});

window.addEventListener('tradeup:economy-updated',load);
