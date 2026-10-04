import {getSupabase} from './supabase.js';
import {moneyFromKurus,setStatus} from './utils.js';
const section=document.querySelector('#market');
const status=document.querySelector('#market-status');
const product=document.querySelector('#market-product');
const windowSelect=document.querySelector('#market-window');
const refresh=document.querySelector('#market-refresh');
let loading=false,data=null;
const date=value=>new Intl.DateTimeFormat('tr-TR',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Istanbul'}).format(new Date(value));
function node(tag,text,cls){const el=document.createElement(tag);if(text!==undefined)el.textContent=text;if(cls)el.className=cls;return el;}
const percent=value=>(Number(value)>0?'+':'')+new Intl.NumberFormat('tr-TR',{maximumFractionDigits:2}).format(Number(value))+'%';
function trends(target){target.replaceChildren();for(const item of data.categories){const card=node('article',undefined,'card');card.append(node('strong',item.category),node('p',percent(item.change_pct),'trend-value'),node('small','Talep '+item.demand+'/100 · Arz '+item.supply+'/100','muted'));target.append(card);}}
function chart(history){
 const container=document.querySelector('#market-chart');container.replaceChildren();
 if(!history.length){container.append(node('p','Bu aralıkta henüz fiyat kaydı yok.','muted'));return;}
 if(history.length===1){container.append(node('p','İlk kayıt: '+moneyFromKurus(history[0].market_price_kurus)+'. Grafik için ikinci piyasa kaydı bekleniyor.','muted'));return;}
 const prices=history.map(item=>BigInt(item.market_price_kurus));let low=prices[0],high=prices[0];for(const p of prices){if(p<low)low=p;if(p>high)high=p;}
 const start=new Date(history[0].recorded_at).getTime(),end=new Date(history.at(-1).recorded_at).getTime();
 const points=history.map((item,i)=>{const x=30+(new Date(item.recorded_at).getTime()-start)/Math.max(1,end-start)*540;const y=high===low?100:180-Number((prices[i]-low)*16000n/(high-low))/100;return x+','+y;}).join(' ');
 const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('viewBox','0 0 600 200');svg.setAttribute('role','img');svg.setAttribute('aria-label','Piyasa fiyatı: '+date(history[0].recorded_at)+' ile '+date(history.at(-1).recorded_at)+' arasında '+moneyFromKurus(low)+'–'+moneyFromKurus(high)+'. Sayısal kayıtlar aşağıdaki tabloda.');
 const line=document.createElementNS(svg.namespaceURI,'polyline');line.setAttribute('points',points);line.setAttribute('fill','none');line.setAttribute('stroke','var(--accent)');line.setAttribute('stroke-width','3');svg.append(line);container.append(svg,node('p','En düşük '+moneyFromKurus(low)+' · En yüksek '+moneyFromKurus(high),'muted'));
}
function render(){
 trends(document.querySelector('#market-trends'));trends(document.querySelector('#dashboard-trends'));
 const selected=data.selected_product;product.replaceChildren();
 for(const item of data.products){const option=node('option',item.name);option.value=item.id;option.selected=item.id===selected;product.append(option);}
 const item=data.products.find(item=>item.id===selected);const detail=document.querySelector('#market-detail');detail.replaceChildren();
 if(item){detail.append(node('h3',item.name),node('p','Piyasa '+moneyFromKurus(item.market_price_kurus)+' · Toptan '+moneyFromKurus(item.wholesale_price_kurus)),node('p','Talep '+item.demand+'/100 · Arz '+item.supply+'/100 · Tedarikçi stoğu '+item.system_stock+' adet','muted'));}
 chart(data.history);const body=document.querySelector('#market-history');body.replaceChildren();
 for(const item of data.history){const row=node('tr');for(const value of [date(item.recorded_at),moneyFromKurus(item.market_price_kurus),moneyFromKurus(item.wholesale_price_kurus)])row.append(node('td',value));body.append(row);}
 document.querySelector('#market-updated').textContent='Son kontrol '+date(data.as_of)+' · Sonraki fırsat '+date(data.next_tick_at)+' · İstanbul';
}
async function load(advance=true){
 if(loading||document.querySelector('#game-shell').hidden)return;loading=true;refresh.disabled=true;product.disabled=true;windowSelect.disabled=true;section.setAttribute('aria-busy','true');setStatus(status,'Piyasa kontrol ediliyor…');
 try{const client=await getSupabase();if(!client)throw new Error('Missing config');let changed=false;
  if(advance){const result=await client.rpc('process_market_tick');if(result.error)throw result.error;changed=result.data.updated;}
  const result=await client.rpc('market_snapshot',{p_product_id:product.value||null,p_window:windowSelect.value});if(result.error)throw result.error;data=result.data;render();setStatus(status,changed?'Arz, talep ve fiyatlar güncellendi.':'Piyasa güncel. Fiyatlar en erken 5 dakikada bir değişir.','success');
  if(changed)window.dispatchEvent(new Event('tradeup:economy-updated'));
 }catch(error){const message=error.code==='PGRST202'?'008_economy.sql dosyasını Supabase SQL Editor’da çalıştırın.':'Piyasa verileri yüklenemedi. Yenile ile tekrar deneyin.';setStatus(status,message,'error');document.querySelector('#dashboard-trends').replaceChildren(node('p',message,'muted'));}
 finally{loading=false;refresh.disabled=false;product.disabled=false;windowSelect.disabled=false;section.setAttribute('aria-busy','false');}
}
const active=()=>['#market','#dashboard',''].includes(location.hash);
refresh.addEventListener('click',()=>load());product.addEventListener('change',()=>load(false));windowSelect.addEventListener('change',()=>load(false));
window.addEventListener('hashchange',()=>{if(active())load();});window.addEventListener('tradeup:store-ready',()=>load());
document.addEventListener('visibilitychange',()=>{if(!document.hidden)load();});
setInterval(()=>{if(!document.hidden)load();},60000);
