export function createWholesaleService(client) {
 return {
  async catalog(){const {data,error}=await client.rpc('wholesale_catalog');if(error)throw error;return data;},
  async buy(request){const {data,error}=await client.rpc('buy_wholesale',request);if(error)throw error;return data;}
 };
}
export const wholesaleErrors={
 W0001:'Mağaza bulunamadı. Oturumunuzu kontrol edin.',W0002:'Ürün artık satışta değil.',W0003:'Miktar 1–1.000 arasında tam sayı olmalı.',
 W0004:'Tedarikçi stoku yetersiz.',W0005:'Bakiyeniz yetersiz.',W0006:'Depo kapasitesi aşılıyor.',W0007:'Fiyat değişti. Listeyi yenileyip tekrar deneyin.',W0008:'İstek kimliği farklı bir işlemde kullanılmış.',
 '22P02':'İstek biçimi geçersiz. Miktarı kontrol edin.','22003':'Miktar veya fiyat izin verilen aralığın dışında.','42501':'İşlem için giriş yapmanız gerekiyor.',
 '28000':'Oturumunuz sona erdi. Yeniden giriş yapın.',PGRST202:'Toptan pazar için 004_wholesale.sql migration dosyasını uygulayın.'
};
