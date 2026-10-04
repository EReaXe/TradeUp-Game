export function createEventsService(client){return {
 async snapshot(){const {data,error}=await client.rpc('market_events_snapshot');if(error)throw error;return data;},
 async buy(request){const {data,error}=await client.rpc('buy_market_offer',request);if(error)throw error;return data;}
};}
export const offerErrors={F0001:'Geçerli bir miktar girin.',F0002:'Fırsat henüz başlamadı veya sona erdi.',F0003:'Fırsat stoku yetersiz.',W0001:'Mağaza bulunamadı.',W0002:'Ürün artık satışta değil.',W0005:'Bakiyeniz yetersiz.',W0006:'Depo kapasiteniz yetersiz.',W0007:'Fiyat değişti. Fırsatları yenileyin.',W0008:'İstek kimliği farklı işlemde kullanılmış.','28000':'Yeniden giriş yapın.','42501':'İşlem için yetkiniz yok.','22P02':'İstek biçimi geçersiz.','22003':'Miktar veya fiyat sınır dışında.',PGRST202:'009_market_events.sql dosyasını Supabase SQL Editor’da çalıştırın.'};
