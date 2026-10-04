import {getSupabase} from './supabase.js';
import {moneyFromKurus,setStatus} from './utils.js';
import {createEventsService,offerErrors} from './events-service.js';
const status=document.querySelector('#events-status'),offers=document.querySelector('#market-offers'),news=document.querySelector('#market-news'),dashboard=document.querySelector('#dashboard-news');
const refresh=document.querySelector('#events-refresh'),retry=document.querySelector('#events-retry');
let service,data=null,loading=false,busy=false,pending=null,key,received=0;
function el(tag,text,cls){const node=document.createElement(tag);if(text!==undefined)node.textContent=text;if(cls)node.className=cls;return node;}
const date=value=>new Intl.DateTimeFormat('tr-TR',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Istanbul'}).format(new Date(value));
const now=()=>data?new Date(data.as_of).getTime()+performance.now()-received:0;
const change=bps=>{const value=(bps-10000)/100;return (value>0?'+':'')+new Intl.NumberFormat('tr-TR',{maximumFractionDigits:2}).format(value)+'%';};
function phase(item){return now()<new Date(item.starts_at).getTime()?'Yakında':now()>=new Date(item.ends_at).getTime()?'Sona erdi':'Aktif';}
function controls(){refresh.disabled=loading||busy;retry.disabled=loading||busy;
 for(const form of offers.querySelectorAll('form')){const locked=loading||busy||!!pending||Number(form.dataset.remaining)<1||now()<Number(form.dataset.start)||now()>=Number(form.dataset.end);for(const input of form.querySelectorAll('input,button'))input.disabled=locked;}
 retry.hidden=!pending;
}
function countdown(){if(!data)return;for(const text of document.querySelectorAll('#market-offers [data-countdown]')){const start=Number(text.dataset.start),end=Number(text.dataset.end),time=now();if(time>=end)text.textContent='Sona erdi';else{const seconds=Math.max(0,Math.ceil(((time<start?start:end)-time)/1000));text.textContent=(time<start?'Başlar: ':'Kalan: ')+Math.floor(seconds/3600)+' sa '+Math.floor(seconds%3600/60)+' dk '+seconds%60+' sn';}}controls();}
function renderNews(target,items){target.replaceChildren();if(!items.length){target.append(el('p','Henüz piyasa haberi yok.','muted'));return;}
 for(const item of items){const card=el('article',undefined,'card event-card');card.append(el('span',phase(item)+' · '+item.category,'tag'),el('h3',item.title),el('p',item.news),el('p','Arz '+change(item.supply_bps)+' · Talep '+change(item.demand_bps)+' · Hedef fiyat '+change(item.price_bps),'muted'),el('small',date(item.starts_at)+' → '+date(item.ends_at)+' · İstanbul','muted'));target.append(card);}
}
function render(){renderNews(news,data.events);renderNews(dashboard,data.events.filter(item=>phase(item)!=='Sona erdi').slice().sort((a,b)=>new Date(a.starts_at)-new Date(b.starts_at)).slice(0,2));offers.replaceChildren();
 if(!data.offers.length)offers.append(el('p','Şu anda açık veya yaklaşan fırsat yok.','muted'));
 for(const item of data.offers){const card=el('article',undefined,'card product-card');card.append(el('span',(item.kind==='FLASH_DEAL'?'FLASH DEAL · %30 indirim':'LIMITED DROP')+' · '+item.rarity,'tag'),el('h3',item.name),el('strong',moneyFromKurus(item.price_kurus),'offer-price'));
  if(item.kind==='FLASH_DEAL')card.append(el('p','Oluşturulduğundaki normal fiyat '+moneyFromKurus(item.original_price_kurus)+' · Şu an normal toptan '+moneyFromKurus(item.current_wholesale_price_kurus),'muted'));
  card.append(el('p','Piyasa '+moneyFromKurus(item.market_price_kurus)+' · Kalan '+item.remaining+' / '+item.initial_quantity+' adet','muted'));
  const timer=el('p',undefined,'offer-timer');timer.dataset.countdown='true';timer.dataset.start=new Date(item.starts_at).getTime();timer.dataset.end=new Date(item.ends_at).getTime();card.append(timer,el('small',date(item.starts_at)+' → '+date(item.ends_at)+' · İstanbul','muted'));
  const form=el('form',undefined,'purchase-form');form.dataset.start=timer.dataset.start;form.dataset.end=timer.dataset.end;form.dataset.remaining=item.remaining;
  const label=el('label','Adet');const input=el('input');input.type='number';input.min='1';input.max=String(Math.max(1,Math.min(1000,item.remaining)));input.step='1';input.value='1';input.required=true;input.setAttribute('aria-label',item.name+' fırsat adedi');label.append(input);
  const button=el('button',item.remaining?'Fırsatı satın al':'Stok tükendi','primary');button.type='submit';button.setAttribute('aria-label',item.name+' '+(item.kind==='FLASH_DEAL'?'flash deal':'limited drop')+' satın al');
  const total=el('small','Toplam '+moneyFromKurus(item.price_kurus),'muted purchase-total');input.addEventListener('input',()=>{const q=Number(input.value);total.textContent=Number.isInteger(q)&&q>=1&&q<=1000?'Toplam '+moneyFromKurus(BigInt(item.price_kurus)*BigInt(q)):'Geçerli miktar girin';});
  form.append(label,button,total);form.addEventListener('submit',event=>{event.preventDefault();if(busy||pending||loading||!form.reportValidity())return;buy({p_offer_id:item.id,p_quantity:Number(input.value),p_expected_price_kurus:item.price_kurus,p_request_id:crypto.randomUUID()});});card.append(form);offers.append(card);
 }
 const history=document.querySelector('#offer-history');history.replaceChildren();if(!data.receipts.length)history.append(el('p','Henüz fırsat alımı yok.','muted'));
 for(const receipt of data.receipts){const row=el('div',undefined,'row');row.append(el('strong',receipt.name+' · '+receipt.quantity+' adet'),el('span',moneyFromKurus(receipt.total_kurus)),el('small',date(receipt.created_at),'muted'));history.append(row);}
 countdown();
}
async function load(){if(loading||document.querySelector('#game-shell').hidden)return;loading=true;controls();
 try{const client=await getSupabase();if(!client)throw new Error('Missing config');const {data:auth,error}=await client.auth.getUser();if(error||!auth.user)throw error||new Error('No user');service=createEventsService(client);key='tradeup:offer-pending:'+auth.user.id;
  const stored=localStorage.getItem(key);if(stored&&!pending){try{const parsed=JSON.parse(stored);if(parsed.p_offer_id&&parsed.p_request_id&&Number.isInteger(parsed.p_quantity)&&parsed.p_expected_price_kurus)pending=parsed;else localStorage.removeItem(key);}catch{localStorage.removeItem(key);}}
  const tick=await client.rpc('process_market_tick');if(tick.error)throw tick.error;if(tick.data.updated)window.dispatchEvent(new Event('tradeup:economy-updated'));
  data=await service.snapshot();received=performance.now();render();if(!busy)setStatus(status,pending?'Önceki alımın sonucunu Aynı işlemi kontrol et butonuyla doğrulayın.':'Haberler ve fırsatlar güncel.','success');
 }catch(error){setStatus(status,offerErrors[error.code]||'Haberler ve fırsatlar yüklenemedi. Yeniden deneyin.','error');if(!data)dashboard.replaceChildren(el('p',offerErrors[error.code]||'Haberler yüklenemedi.','muted'));}
 finally{loading=false;controls();}
}
async function buy(request){if(busy)return;busy=true;controls();setStatus(status,'Fırsat alımı doğrulanıyor…');
 try{localStorage.setItem(key,JSON.stringify(request));const result=await service.buy(request);localStorage.removeItem(key);pending=null;await load();window.dispatchEvent(new Event('tradeup:economy-updated'));setStatus(status,result.quantity+' adet alındı · '+moneyFromKurus(result.total_kurus),'success');}
 catch(error){if(offerErrors[error.code]){localStorage.removeItem(key);pending=null;setStatus(status,offerErrors[error.code],'error');}else{pending=request;setStatus(status,'Alımın sonucu doğrulanamadı. Aynı işlemi kontrol et butonuyla güvenli biçimde tekrar deneyin.','error');}}
 finally{busy=false;controls();}
}
refresh.addEventListener('click',load);retry.addEventListener('click',()=>{if(pending)buy(pending);});
const active=()=>['#market','#dashboard',''].includes(location.hash);
window.addEventListener('tradeup:store-ready',load);window.addEventListener('hashchange',()=>{if(active())load();});document.addEventListener('visibilitychange',()=>{if(!document.hidden&&active())load();});
setInterval(()=>{if(!document.hidden){countdown();if(active()&&!busy&&!loading&&data&&performance.now()-received>=60000)load();}},1000);
