export function createProgressionService(client){return {
 async snapshot(){const {data,error}=await client.rpc('my_progression');if(error)throw error;return data;},
 async claim(request){const {data,error}=await client.rpc('claim_progression_mission',request);if(error)throw error;return data;},
 async title(code){const {error}=await client.rpc('set_active_title',{p_title_code:code});if(error)throw error;}
};}
export const progressionErrors={G0001:'Marketplace seviye 5’te açılır.',G0002:'Görev bulunamadı.',G0003:'Görev henüz tamamlanmadı.',G0004:'Bu görev dönemi sona erdi. Listeyi yenileyin.',G0005:'Bu unvan henüz kazanılmadı.',G0006:'Bakiye sınırına ulaşıldı.',W0001:'Mağaza bulunamadı.','28000':'Yeniden giriş yapın.','42501':'İşlem için yetkiniz yok.','22P02':'İstek biçimi geçersiz.',PGRST202:'010_progression.sql dosyasını Supabase SQL Editor’da çalıştırın.'};
