import {getSupabase} from './supabase.js';
import {createWholesaleService,wholesaleErrors} from './wholesale-service.js';
import {moneyFromKurus,setStatus} from './utils.js';
const section=document.querySelector('#wholesale');
const status=document.querySelector('#wholesale-status');
const list=document.querySelector('#wholesale-products');
const search=document.querySelector('#wholesale-search');
const category=document.querySelector('#wholesale-category');
const refresh=document.querySelector('#wholesale-refresh');
let service,products=[],loading=false,purchasing=false,unresolved=null,pendingKey;
const categories={Technology:'Teknoloji',Gaming:'Gaming',Clothing:'Giyim',Cosmetics:'Kozmetik',Sports:'Spor',Stationery:'Kırtasiye',Home:'Ev',Collectibles:'Koleksiyon'};
for(const [value,name] of Object.entries(categories)){const option=document.createElement('option');option.value=value;option.textContent=name;category.append(option);}
const count=value=>new Intl.NumberFormat('tr-TR').format(value);
function element(tag,text,className){const node=document.createElement(tag);if(text!==undefined)node.textContent=text;if(className)node.className=className;return node;}
function render(){
 list.replaceChildren();
 const filtered=products.filter(p=>(!category.value||p.category===category.value)&&p.name.toLocaleLowerCase('tr-TR').includes(search.value.trim().toLocaleLowerCase('tr-TR')));
 document.querySelector('#wholesale-count').textContent=filtered.length+' ürün';
 if(!filtered.length){list.append(element('p','Aramanıza uygun ürün bulunamadı.','muted'));return;}
 for(const product of filtered){
  const card=element('article',undefined,'card product-card');
  const header=element('div',undefined,'product-header');header.append(element('span',categories[product.category]||product.category,'eyebrow'),element('span',product.rarity,'tag rarity-'+product.rarity.toLowerCase()));
  card.append(header,element('h3',product.name));
  const prices=element('div',undefined,'product-prices');const wholesale=element('div');wholesale.append(element('small','Toptan fiyat','muted'),element('strong',moneyFromKurus(product.wholesale_price_kurus)));
  const market=element('div');market.append(element('small','Tahmini piyasa','muted'),element('span',moneyFromKurus(product.market_price_kurus)));prices.append(wholesale,market);card.append(prices);
  const info=element('div',undefined,'product-facts');info.append(element('span','Stok '+count(product.system_stock)),element('span','Talep '+(product.demand>=70?'Yüksek':product.demand>=40?'Orta':'Düşük')));card.append(info);
  card.append(element('p',product.change_pct===undefined?'Piyasa eğilimleri için Piyasa ekranına bakın.':'Başlangıca göre piyasa '+(Number(product.change_pct)>0?'+':'')+new Intl.NumberFormat('tr-TR').format(Number(product.change_pct))+'%','muted product-note'));
  const form=element('form',undefined,'purchase-form');const label=element('label','Adet');const input=document.createElement('input');input.type='number';input.min='1';input.max=String(Math.min(1000,product.system_stock));input.step='1';input.value='1';input.required=true;input.setAttribute('aria-label',product.name+' satın alma adedi');
  label.append(input);const button=element('button',product.system_stock?'Satın al':'Stok tükendi','primary');button.type='submit';
  const total=element('small','Toplam '+moneyFromKurus(product.wholesale_price_kurus),'muted purchase-total');
  function updateTotal(){const q=Number(input.value);total.textContent=Number.isInteger(q)&&q>=1&&q<=1000?'Toplam '+moneyFromKurus(BigInt(product.wholesale_price_kurus)*BigInt(q)):'Geçerli miktar girin';}
  input.addEventListener('input',updateTotal);
  input.disabled=purchasing||!!unresolved||product.system_stock===0;button.disabled=input.disabled;form.append(label,button,total);
  form.addEventListener('submit',event=>{event.preventDefault();if(purchasing||unresolved||!form.reportValidity())return;buy({p_product_id:product.id,p_quantity:Number(input.value),p_expected_price_kurus:product.wholesale_price_kurus,p_request_id:crypto.randomUUID()},product.name);});
  card.append(form);list.append(card);
 }
}
async function load(){
 if(loading||document.querySelector('#game-shell').hidden)return;
 loading=true;refresh.disabled=true;section.setAttribute('aria-busy','true');
 try{const client=await getSupabase();if(!client)throw new Error('Config missing');service=createWholesaleService(client);
 const {data:auth,error:authFailure}=await client.auth.getUser();if(authFailure||!auth.user)throw authFailure||new Error('No user');
 pendingKey='tradeup:wholesale-pending:'+auth.user.id;
 const stored=localStorage.getItem(pendingKey);
 if(stored&&!unresolved){try{const saved=JSON.parse(stored);if(saved.request?.p_request_id&&saved.request?.p_product_id&&saved.name){unresolved=saved;document.querySelector('#wholesale-retry').hidden=false;setStatus(status,'Önceki işlemin sonucunu doğrulamak için Aynı işlemi kontrol et butonunu kullanın.');}}catch{localStorage.removeItem(pendingKey);}}
 products=await service.catalog();render();if(!purchasing&&!unresolved)setStatus(status,'Tedarikçi ürünleri güncel.','success');}
 catch(error){setStatus(status,wholesaleErrors[error.code]||'Ürünler yüklenemedi. Tekrar deneyin.','error');}
 finally{loading=false;refresh.disabled=purchasing;section.setAttribute('aria-busy',String(purchasing));}
}
async function buy(request,name){
 if(purchasing)return;
 purchasing=true;refresh.disabled=true;section.setAttribute('aria-busy','true');render();setStatus(status,'Satın alma doğrulanıyor…');
 try{
  localStorage.setItem(pendingKey,JSON.stringify({request,name}));
  const receipt=await service.buy(request);localStorage.removeItem(pendingKey);unresolved=null;document.querySelector('#wholesale-retry').hidden=true;
  await load();window.dispatchEvent(new Event('tradeup:economy-updated'));
  setStatus(status,receipt.quantity+' adet '+name+' satın alındı · '+moneyFromKurus(receipt.total_kurus),'success');
 }catch(error){
  const known=wholesaleErrors[error.code];
  if(known){localStorage.removeItem(pendingKey);unresolved=null;document.querySelector('#wholesale-retry').hidden=true;setStatus(status,known,'error');}
  else{unresolved={request,name};document.querySelector('#wholesale-retry').hidden=false;setStatus(status,'İşlemin sonucu doğrulanamadı. Aynı işlemi kontrol et butonuyla güvenli şekilde tekrar deneyin.','error');}
 }finally{purchasing=false;refresh.disabled=false;section.setAttribute('aria-busy','false');render();}
}
document.querySelector('#wholesale-retry').addEventListener('click',()=>{if(unresolved)buy(unresolved.request,unresolved.name);});
refresh.addEventListener('click',load);search.addEventListener('input',render);category.addEventListener('change',render);
window.addEventListener('tradeup:store-ready',()=>{if(location.hash==='#wholesale')load();});
window.addEventListener('hashchange',()=>{if(location.hash==='#wholesale')load();});
