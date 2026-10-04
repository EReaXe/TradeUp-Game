export function createAuthService(client) {
 return {
  async user() { const {data,error}=await client.auth.getUser(); if(error) throw error; return data.user; },
  async login(email,password) { const {data,error}=await client.auth.signInWithPassword({email,password}); if(error) throw error; return data; },
  async register(email,password,redirect) { const {data,error}=await client.auth.signUp({email,password,options:{emailRedirectTo:redirect}}); if(error) throw error; return data; },
  async logout() { const {error}=await client.auth.signOut({scope:'local'}); if(error) throw error; },
  async store(userId) { const {data,error}=await client.from('stores').select('user_id,store_name,created_at').eq('user_id',userId).maybeSingle(); if(error) throw error; return data; },
  async createStore(username,storeName) { const {data,error}=await client.rpc('complete_store_onboarding',{p_username:username,p_store_name:storeName}); if(error) throw error; return data; }
 };
}
export function authError(error) {
 if(error.code === '23505') return 'Kullanıcı adı veya mağaza adı zaten kullanılıyor.';
 if(error.code === '42P01' || error.code === 'PGRST202' || error.code === 'PGRST205') return 'Mağaza kurulumu için Phase 1 ve Phase 2 SQL migration dosyalarını uygulayın.';
 if(error.code === 'invalid_credentials') return 'E-posta veya şifre hatalı.';
 if(error.code === 'email_not_confirmed') return 'Giriş yapmadan önce e-posta adresinizi doğrulayın.';
 if(error.status === 429) return 'Çok fazla deneme yapıldı. Biraz bekleyip tekrar deneyin.';
 if(error.code === 'weak_password') return 'Şifreniz güvenlik gereksinimlerini karşılamıyor.';
 return 'İşlem tamamlanamadı. Yapılandırmayı ve bağlantıyı kontrol edip tekrar deneyin.';
}
