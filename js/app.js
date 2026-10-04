import { config } from './config.js';
import { getSupabase } from './supabase.js';
import { currentScreen, screens } from './router.js';
import { setStatus } from './utils.js';
const navigation = document.querySelector('#navigation');
for (const [id, title, icon] of screens) {
 const link = document.createElement('a'); link.href = '#' + id;
 const symbol = document.createElement('span'); symbol.textContent = icon; symbol.setAttribute('aria-hidden','true');
 link.append(symbol, document.createTextNode(title)); link.dataset.screen = id; navigation.append(link);
}
function render() {
 const [id, title, , phase] = currentScreen();
 document.title = title + ' · ' + config.appName;
 document.querySelector('#page-title').textContent = title;
 const overview=document.querySelector('#dashboard') || document.querySelector('#foundation');
 overview.hidden = id !== 'dashboard';
 const wholesale=document.querySelector('#wholesale');
 if(wholesale)wholesale.hidden=id!=='wholesale';
 const inventory=document.querySelector('#inventory');
 if(inventory)inventory.hidden=id!=='inventory';
 const orders=document.querySelector('#orders');
 if(orders)orders.hidden=id!=='orders';
 const marketplace=document.querySelector('#marketplace');
 if(marketplace)marketplace.hidden=id!=='marketplace';
 const market=document.querySelector('#market');
 if(market)market.hidden=id!=='market';
 const progression=document.querySelector('#progression');if(progression)progression.hidden=id!=='progression';
 const profile=document.querySelector('#profile');if(profile)profile.hidden=id!=='profile';
 const company=document.querySelector('#company');if(company)company.hidden=id!=='company';
 for(const name of ['auction','contracts','collection']){const section=document.querySelector('#'+name);if(section)section.hidden=id!==name;}
 document.querySelector('#placeholder').hidden = id === 'dashboard' || (id === 'wholesale' && !!wholesale) || (id === 'inventory' && !!inventory) || (id === 'orders' && !!orders) || (id === 'marketplace' && !!marketplace) || (id === 'market' && !!market) || (id === 'progression' && !!progression) || (id === 'profile' && !!profile) || (id === 'company' && !!company) || (['auction','contracts','collection'].includes(id) && !!document.querySelector('#'+id));
 document.querySelector('#placeholder-title').textContent = title;
 document.querySelector('#placeholder-phase').textContent = 'Coming in Phase ' + phase;
 for (const link of navigation.querySelectorAll('a')) {
  if (link.dataset.screen === id) link.setAttribute('aria-current','page'); else link.removeAttribute('aria-current');
 }
 document.querySelector('.sidebar').classList.remove('open');
 document.querySelector('#menu-toggle').setAttribute('aria-expanded','false');
}
window.addEventListener('hashchange', render); render();
document.querySelector('#menu-toggle').addEventListener('click', event => {
 const expanded = document.querySelector('.sidebar').classList.toggle('open');
 event.currentTarget.setAttribute('aria-expanded', String(expanded));
});
document.addEventListener('keydown', event => {
 if (event.key === 'Escape') { document.querySelector('.sidebar').classList.remove('open'); document.querySelector('#menu-toggle').setAttribute('aria-expanded','false'); }
});
const status = document.querySelector('#connection-status');
if(status) {
setStatus(status, 'Yapılandırma kontrol ediliyor…');
getSupabase().then(client => setStatus(status, client ? 'Supabase istemcisi hazır · bağlantı henüz doğrulanmadı' : 'Supabase yapılandırması bekleniyor', client ? 'success' : 'neutral'))
 .catch(error => { console.error('Supabase initialization failed', error); setStatus(status, 'Supabase istemcisi başlatılamadı. Yapılandırmayı ve ağ bağlantısını kontrol edin.', 'error'); });
}
document.title = currentScreen()[1] + ' · ' + config.appName;

