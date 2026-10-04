import {getSupabase} from './supabase.js';
import {moneyFromKurus,setStatus} from './utils.js';
const section=document.querySelector('#orders');const status=document.querySelector('#sales-status');const list=document.querySelector('#sales-listings');const orders=document.querySelector('#sales-history');
let loading=false,running=false,ticking=false,saving=false;
const errors={N0001:'Geçerli bir fiyat girin.',N0002:'Satış için stok gerekiyor.',N0003:'Aktif ilan limitine ulaştınız.',PGRST202:'006_npc_sales.sql dosyasını Supabase SQL Editor’da çalıştırın.'};
function node(tag,text,cls){const el=document.createElement(tag);if(text!==undefined)el.textContent=text;if(cls)el.className=cls;return el;}
async function rpc(name,args){const client=await getSupabase();if(!client)throw new Error('Missing config');const {data,error}=await client.rpc(name,args);if(error)throw error;return data;}
async function load(){
 if(loading||document.querySelector('#game-shell').hidden)return;loading=true;
 try{const data=await rpc('my_sales_state');list.replaceChildren();orders.replaceChildren();
  document.querySelector('#sales-limit').textContent='En fazla '+data.listing_limit+' aktif ürün';
  if(!data.items.length)list.append(node('p','Satışa çıkarmak için önce toptan pazardan ürün satın alın.','muted'));
  for(const item of data.items){const card=node('article',undefined,'card');card.append(node('h3',item.name),node('p',item.quantity+' adet · Maliyet '+moneyFromKurus(item.average_cost_kurus)+' · Piyasa '+moneyFromKurus(item.market_price_kurus),'muted'));
   const form=node('form',undefined,'sale-form');const label=node('label','Satış fiyatı (₺)');const input=node('input');input.type='text';input.inputMode='decimal';input.value=(BigInt(item.price_kurus)/100n).toString()+','+(BigInt(item.price_kurus)%100n).toString().padStart(2,'0');input.required=true;input.setAttribute('aria-label',item.name+' satış fiyatı');label.append(input);
   const toggleLabel=node('label',undefined,'sale-toggle');const toggle=node('input');toggle.type='checkbox';toggle.checked=item.enabled;toggleLabel.append(toggle,document.createTextNode('Satışa açık'));
   const button=node('button','Kaydet','primary');button.type='submit';form.append(label,toggleLabel,button);
   form.addEventListener('submit',async event=>{event.preventDefault();if(saving)return;const raw=input.value.trim().replace(',','.');if(!/^[0-9]{1,11}([.][0-9]{1,2})?$/.test(raw)){setStatus(status,'Fiyatı 168,00 gibi girin.','error');return;}const [whole,part='']=raw.split('.');const price=BigInt(whole)*100n+BigInt(part.padEnd(2,'0'));if(price<1n||price>1000000000000n){setStatus(status,'Fiyat 0,01–10.000.000.000 ₺ arasında olmalı.','error');return;}saving=true;button.disabled=true;
    try{await rpc('set_npc_listing',{p_product_id:item.id,p_price_kurus:price.toString(),p_enabled:toggle.checked});await load();setStatus(status,'Satış ayarları kaydedildi.','success');}catch(error){setStatus(status,errors[error.code]||'Satış ayarları kaydedilemedi.','error');}finally{saving=false;button.disabled=false;}
   });card.append(form);list.append(card);
  }
  if(!data.orders.length)orders.append(node('p','Henüz NPC siparişi yok.','muted'));
  for(const order of data.orders){const row=node('div',undefined,'row');row.append(node('strong',order.name+' · '+(order.quantity??'?')+' adet'),node('span',moneyFromKurus(order.revenue_kurus)+' · Kâr '+(order.profit_kurus===null?'bilinmiyor':moneyFromKurus(order.profit_kurus))),node('small',new Intl.DateTimeFormat('tr-TR',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Istanbul'}).format(new Date(order.created_at)),'muted'));orders.append(row);}
 }catch(error){setStatus(status,errors[error.code]||'Satış verileri yüklenemedi.','error');}finally{loading=false;}
}
async function tick(){if(ticking||document.hidden||document.querySelector('#game-shell').hidden)return;ticking=true;
 try{const data=await rpc('process_npc_sales');setStatus(status,data.sold?data.sold+' ürün satıldı · Gelir '+moneyFromKurus(data.revenue_kurus)+' · Kâr '+moneyFromKurus(data.profit_kurus):'Yeni satış yok. Sonraki fırsat '+data.wait_seconds+' saniye içinde.','success');if(data.sold){await load();window.dispatchEvent(new Event('tradeup:economy-updated'));}}
 catch(error){setStatus(status,errors[error.code]||'Satış kontrolü başarısız. Tekrar deneyin.','error');running=false;document.querySelector('#sales-start').textContent='Satış motorunu başlat';}
 finally{ticking=false;}
}
document.querySelector('#sales-start').addEventListener('click',()=>{running=!running;document.querySelector('#sales-start').textContent=running?'Satış motorunu durdur':'Satış motorunu başlat';if(running)tick();});
document.querySelector('#sales-check').addEventListener('click',tick);document.querySelector('#sales-refresh').addEventListener('click',load);
setInterval(()=>{if(running)tick();},15000);
window.addEventListener('hashchange',()=>{if(location.hash==='#orders')load();});
window.addEventListener('tradeup:store-ready',()=>{if(location.hash==='#orders')load();});
