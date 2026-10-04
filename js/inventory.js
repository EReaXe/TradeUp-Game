import {getSupabase} from './supabase.js';
import {moneyFromKurus,setStatus} from './utils.js';
const section=document.querySelector('#inventory');
const status=document.querySelector('#inventory-status');
const content=document.querySelector('#inventory-content');
const body=document.querySelector('#inventory-rows');
const search=document.querySelector('#inventory-search');
const refresh=document.querySelector('#inventory-refresh');
let items=[],loading=false;
function renderRows(){
 body.replaceChildren();
 const filtered=items.filter(p=>p.name.toLocaleLowerCase('tr-TR').includes(search.value.trim().toLocaleLowerCase('tr-TR')));
 document.querySelector('#inventory-empty').hidden=filtered.length>0;
 document.querySelector('#inventory-empty').textContent=items.length?'Aramanıza uygun ürün bulunamadı.':'Depon henüz boş. Toptan pazardan ilk ürünlerini satın al.';
 document.querySelector('#inventory-table').hidden=!filtered.length;
 for(const item of filtered){
  const row=document.createElement('tr');
  const name=document.createElement('th');name.scope='row';name.textContent=item.name;
  const detail=document.createElement('small');detail.className='muted';detail.textContent=item.category+' · '+item.rarity+' · Ayrılmış '+(item.reserved??0)+' / Serbest '+(item.available??item.quantity)+(item.active?'':' · Tedarik satışı kapalı');name.append(detail);row.append(name);
  for(const value of [new Intl.NumberFormat('tr-TR').format(item.quantity),moneyFromKurus(item.average_cost_kurus),moneyFromKurus(item.market_price_kurus),moneyFromKurus(item.value_kurus),moneyFromKurus(item.potential_profit_kurus)]){const cell=document.createElement('td');cell.textContent=value;row.append(cell);}
  row.lastChild.className=BigInt(item.potential_profit_kurus)<0n?'negative':'positive';body.append(row);
 }
}
async function load(){
 if(loading||document.querySelector('#game-shell').hidden)return;
 loading=true;refresh.disabled=true;content.hidden=true;section.setAttribute('aria-busy','true');setStatus(status,'Envanter yükleniyor…');
 try{
  const client=await getSupabase();if(!client)throw new Error('Missing config');const {data,error}=await client.rpc('my_inventory');if(error)throw error;
  items=data.items;
  for(const [id,key] of [['inventory-cost','cost_kurus'],['inventory-value','value_kurus'],['inventory-profit','potential_profit_kurus']])document.querySelector('#'+id).textContent=moneyFromKurus(data[key]);
  document.querySelector('#inventory-profit').classList.toggle('negative',BigInt(data.potential_profit_kurus)<0n);
  document.querySelector('#inventory-units').textContent=data.units+' / '+data.warehouse_capacity;
  document.querySelector('#inventory-updated').textContent='Son güncelleme: '+new Intl.DateTimeFormat('tr-TR',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Istanbul'}).format(new Date(data.as_of))+' · İstanbul';
  renderRows();content.hidden=false;setStatus(status,'Envanter güncel.','success');
 }catch(error){setStatus(status,error.code==='PGRST202'?'Envanter için 005_inventory.sql dosyasını Supabase SQL Editor’da çalıştırın.':'Envanter yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.','error');}
 finally{loading=false;refresh.disabled=false;section.setAttribute('aria-busy','false');}
}
refresh.addEventListener('click',load);search.addEventListener('input',renderRows);
window.addEventListener('tradeup:store-ready',()=>{if(location.hash==='#inventory')load();});
window.addEventListener('hashchange',()=>{if(location.hash==='#inventory')load();});
window.addEventListener('tradeup:economy-updated',()=>{if(location.hash==='#inventory')load();});
