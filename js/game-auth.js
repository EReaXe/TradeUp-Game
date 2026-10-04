import {getSupabase} from './supabase.js';
import {createAuthService,authError} from './auth-service.js';
import {setStatus} from './utils.js';
const shell=document.querySelector('#game-shell');
const gate=document.querySelector('#auth-gate');
const status=document.querySelector('#gate-status');
const onboarding=document.querySelector('#onboarding');
const form=onboarding.querySelector('form');
const formStatus=document.querySelector('#onboarding-status');
let service;
function hide() { shell.hidden=true; onboarding.hidden=true; gate.hidden=false; }
function showStore(store) {
 onboarding.hidden=true; gate.hidden=true; shell.hidden=false;
 document.querySelector('#store-identity').textContent=store.store_name;
 window.dispatchEvent(new Event('tradeup:store-ready'));
}
async function initialize() {
 hide(); setStatus(status,'Oturum doğrulanıyor…');
 try {
  const client=await getSupabase();
  if(!client) { setStatus(status,'Supabase yapılandırması eksik. Bağlantı bilgilerini js/config.js dosyasına girin.','error'); return; }
  service=createAuthService(client);
  client.auth.onAuthStateChange((event,session)=>{
   if(event==='SIGNED_OUT' || (event==='TOKEN_REFRESHED' && !session)) { hide(); location.replace('login.html'); }
  });
  const {data,error}=await client.auth.getSession();
  if(error) throw error;
  if(!data.session) { location.replace('login.html'); return; }
  const user=await service.user();
  if(!user) { location.replace('login.html'); return; }
  const store=await service.store(user.id);
  if(store) showStore(store); else { gate.hidden=true; onboarding.hidden=false; }
 } catch(error) { hide(); setStatus(status,authError(error),'error'); }
}
form.addEventListener('submit',async event=>{
 event.preventDefault(); const button=form.querySelector('button[type=submit]');
 if(!service || button.disabled || !form.reportValidity()) return;
 button.disabled=true; form.setAttribute('aria-busy','true'); setStatus(formStatus,'Mağazan oluşturuluyor…');
 try {
  const store=await service.createStore(form.elements.username.value.trim(),form.elements.store_name.value.trim());
  showStore(store);
 } catch(error) { setStatus(formStatus,authError(error),'error'); }
 finally { button.disabled=false; form.setAttribute('aria-busy','false'); }
});
for(const button of document.querySelectorAll('[data-logout]')) button.addEventListener('click',async()=>{
 button.disabled=true;
 try { await service.logout(); hide(); location.replace('login.html'); }
 catch(error) { const target= shell.hidden ? formStatus : document.querySelector('#logout-status'); setStatus(target,authError(error),'error'); }
 finally {button.disabled=false;}
});
document.querySelector('#retry-auth').addEventListener('click',()=>location.reload());
window.addEventListener('pageshow',event=>{if(event.persisted) {hide(); location.reload();}});
initialize();
