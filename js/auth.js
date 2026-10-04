import {getSupabase} from './supabase.js';
import {createAuthService,authError} from './auth-service.js';
import {setStatus} from './utils.js';
const form=document.querySelector('form');
const status=document.querySelector('#auth-status');
const submit=form.querySelector('button[type=submit]');
let service;
const redirect=()=>location.replace('game.html');
function busy(value) { submit.disabled=value; form.setAttribute('aria-busy',String(value)); }
async function init() {
 busy(true);
 try {
  const client=await getSupabase();
  if(!client) { setStatus(status,'Supabase henüz yapılandırılmadı. js/config.js içindeki public bağlantı bilgilerini doldurun.','error'); return; }
  service=createAuthService(client);
  const fragment=new URLSearchParams(location.hash.slice(1));
  if(fragment.has('error')) { history.replaceState(null,'',location.pathname); setStatus(status,'Doğrulama bağlantısı geçersiz veya süresi dolmuş. Yeniden giriş yapmayı deneyin.','error'); }
  const {data,error}=await client.auth.getSession();
  if(error) throw error;
  if(data.session) { await service.user(); redirect(); return; }
  client.auth.onAuthStateChange((event,session)=>{ if(event==='SIGNED_IN' && session) redirect(); });
  if(!fragment.has('error')) setStatus(status,'Giriş ve kayıt için bağlantı hazır.','success');
  busy(false);
 } catch(error) { setStatus(status,authError(error),'error'); }
}
form.addEventListener('submit',async event=>{
 event.preventDefault(); if(!service || submit.disabled) return;
 if(!form.reportValidity()) return;
 const email=form.elements.email.value.trim(); const password=form.elements.password.value;
 if(form.dataset.mode==='register' && password!==form.elements.confirm.value) { setStatus(status,'Şifreler eşleşmiyor.','error'); return; }
 busy(true); setStatus(status,'İşlem yapılıyor…');
 try {
  if(form.dataset.mode==='login') { await service.login(email,password); redirect(); }
  else {
   const data=await service.register(email,password,new URL('login.html',location.href).href);
   form.reset();
   if(data.session) redirect();
   else setStatus(status,'E-posta adresiniz uygunsa doğrulama bağlantısı gönderildi. E-postanızı kontrol edip giriş yapın.','success');
  }
 } catch(error) { setStatus(status,authError(error),'error'); }
 finally { busy(false); }
});
init();
