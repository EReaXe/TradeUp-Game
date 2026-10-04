# TradeUp

Multiplayer e-ticaret tycoon projesi. **Mevcut aşama: PHASE 12 — ADVANCED TRADING.**

## Çalıştırma

Node.js 20 veya üzeri ile, bu klasörde:

```sh
npm start
```

http://localhost:3000 adresini açın. Kurulum veya npm install gerekmez. npm bulunmuyorsa node scripts/serve.js komutuyla başlatın; kontroller için node scripts/check.js ve node scripts/auth-check.js çalıştırın. PORT ortam değişkeni ile port değiştirilebilir. ES modules nedeniyle HTML dosyalarını file:// üzerinden açmayın. Yerel sunucu yalnızca geliştirme içindir.

## Yapı

- index.html: public proje kabuğu; game.html: Supabase oturum doğrulamasıyla korunan oyun kabuğu ve onboarding.
- login.html / register.html: Supabase Auth giriş ve kayıt formları.
- css/global.css: tasarım tokenları, tipografi ve ortak bileşenler.
- css/dashboard.css: sidebar ve temel sayfa yerleşimi.
- css/responsive.css: tablet/mobil ve erişilebilirlik uyarlamaları.
- js/config.js: public ayarlar.
- js/supabase.js: isteğe bağlı, tekil Supabase istemcisi.
- js/app.js / router.js: kabuk ve hash tabanlı ekran geçişleri.
- js/utils.js: güvenli metin durumları ve para biçimlendirme.
- assets/icons / assets/products: ileride kullanılacak yerel varlık klasörleri.
- supabase: sonraki fazlarda SQL ve migration dosyaları.
- scripts: bağımlılıksız yerel sunucu ve temel doğrulama.
- docs/PROJECT_BRIEF.md: orijinal proje talebi.

## Supabase kurulumu

Supabase projenizin Project URL ve public publishable key değerlerini js/config.js içindeki supabaseUrl ve supabasePublishableKey alanlarına girin. Legacy anon key de istemci anahtarı olarak kullanılabilir. Bu dosya tarayıcıya gönderilir: service_role veya secret key eklemeyin.

Statik frontend ortam değişkenlerini doğrudan okuyamaz; bu aşamada yapılandırma config.js üzerinden yapılır. Alanlar boşken site çalışır ve yapılandırma bekleniyor mesajı verir; SDK indirilmez. Yapılandırıldığında sürümü sabitlenmiş Supabase JS SDK CDN üzerinden yüklenir, internet gerekir. İstemci hazır mesajı uzak sunucuya bağlantı veya kimlik doğrulama başarısını kanıtlamaz. Ağ/SDK hataları sayfada gösterilir. Gerçek bağlantı için proje bilgileri gerekir.

## Phase 0 geçmişi ve güvenlik

Phase 0 yalnızca kabuk oluşturdu. Phase 1 özellikleri aşağıda belgelenmiştir; gameplay veya ekonomik işlem henüz yoktur. Sayfadaki kartlar proje hazırlığını gösterir; oyuncu KPI veya mock satış verisi yoktur. Tamamlanmamış ekranlar Coming in Phase X olarak etiketlenir. Şema/RLS Phase 2'de, atomik server-side ekonomi işlemleri ilgili sonraki fazlarda geliştirilecek. İstemcideki config ekonomik otorite değildir. Finansal veriler ileride kuruş bazında veya PostgreSQL numeric olarak tutulmalı; moneyFromKurus büyük integer değerlerini float dönüşümü olmadan biçimlendirir.

## Kontrol

npm run check: JS sözdizimi, sayfa dosya referansları ve kuruş biçimlendirme. Tarayıcıda masaüstü/mobil görünüm, sidebar, klavye odağı ve hash ekran geçişleri kontrol edilebilir.

Sıradaki faz **PHASE 8 — ECONOMY ENGINE**. Yalnızca kullanıcının “devam” komutuyla başlanır.

## Phase 1 kurulumu ve davranışı

1. js/config.js içinde Project URL ve public publishable/anon key girin. Secret/service_role anahtarı kullanmayın.
2. Supabase SQL Editor içinde supabase/migrations/001_store_onboarding.sql dosyasını uygulayın. Bu adım sadece mağaza kimliğini ekler. Phase 2’de profiles/stores core tablolarına veriler korunarak taşınacak.
3. Supabase Auth içinde Email provider etkin olsun. Minimum password length en az 8 yapın; e-posta doğrulamasını etkin tutun. Üretimde uygun SMTP sağlayıcısı yapılandırın.
4. Auth URL Configuration: yerel Site URL http://localhost:3000; Redirect URLs listesine http://localhost:3000/login.html ekleyin. Farklı port veya canlı domain için karşılık gelen URL ekleyin.
5. npm start; register.html üzerinden kayıt olun, e-posta doğrulamasını tamamlayın, login.html ile giriş yapın. game.html oturumu Supabase getUser ile doğrular; mağaza kimliği eksikse onboarding açar.

Oturum Supabase SDK tarafından saklanır ve yenilenir. Çıkış bu tarayıcının oturumunu kapatır. Auth state değişiklikleri ve geri tuşuyla cache dönüşü korumalı ekranı kapatır. Auth sayfaları geçerli oturumla game.html adresine yönlenir. Eksik config veya ağ hatasında oyun kabuğu açılmaz. Tarayıcıdaki yönlendirme tek başına veri güvenliği değildir: onboarding tablosu sadece kişinin kendi kaydını okutur; client INSERT/UPDATE/DELETE izinleri kapalıdır. RPC auth.uid ile kullanıcıyı belirler, istemciden user_id kabul etmez. Kullanıcı/mağaza adları case-insensitive unique index ile benzersizdir; aynı kullanıcı için paralel ve tekrarlanan istekler tek kaydı döndürür.

Başlangıç sermayesi/XP vb. onboarding ekranında açıkça planlanan değerler olarak gösterilir. Bunlar henüz verilmez veya client tarafında tutulmaz. Phase 2 sunucu core kayıtlarını oluşturacak.

Yeni dosyalar: css/auth.css, js/auth-service.js, js/auth.js, js/game-auth.js, supabase/migrations/001_store_onboarding.sql, scripts/auth-check.js. Güncellenenler: login/register/game/index HTML, js/config.js, package.json ve README dosyaları.

### Phase 1 doğrulama

npm run check JS/asset kontrolünü ve izole auth service testlerini çalıştırır. Test double yalnızca test dosyasında kullanılır; production fake auth içermez. Gerçek Supabase bilgileri bu repository’de olmadığından canlı kayıt, doğrulama e-postası, RLS ve RPC yarış testleri henüz çalıştırılamadı. SQL migration uzak veritabanına uygulanmadı.

Canlı kurulum sonrası kontrol: oturumsuz game yönlendirmesi; yanlış şifre; doğrulanmamış e-posta; kayıt/doğrulama/giriş; sayfa yenilemeyle oturum; geçersiz mağaza adı; iki kullanıcıyla aynı isim (biri 23505); aynı kullanıcının iki paralel RPC isteği (tek kayıt); başka kullanıcı kaydına select (boş sonuç); doğrudan insert/update/delete (izin reddi); anon RPC (izin reddi); logout ve geri tuşu.

Auth API ve RLS referansları: https://supabase.com/docs/reference/javascript/auth ve https://supabase.com/docs/guides/database/postgres/row-level-security.

Tarayıcı kontrolleri: eksik config ile login/register submit butonları kapalı; game.html oyun kabuğunu açmıyor. Konsol hata/uyarı kontrolü temiz. 390px mobil kayıt ekranında yatay taşma yok. Bu kontroller gerçek Supabase happy-path testlerinin yerini tutmaz.

## Phase 2 — Database Core

profiles, stores, products, inventory ve transactions oluşturuldu. Çekirdek SQL kurulumu ve güvenlik ayrıntıları supabase/README.md içindedir. config.js bağlantısı canlı kontrol edildi: Auth settings HTTP 200; Email aktif, signup açık; kullanılan anahtar public publishable türünde. Onboarding endpoint PGRST205 döndü: 001 henüz kurulmamış. Canlı veritabanına migration uygulanmadı.

SQL Editor'da sırayla supabase/migrations/001_store_onboarding.sql, supabase/migrations/002_database_core.sql ve supabase/seed.sql uygulayın. Yalnızca public anahtar SQL çalıştırma yetkisi vermez; bu yüzden bu repository canlı DB’ye kendiliğinden şema yazamaz. Secret anahtar gerekmez; dashboard SQL Editor yeterlidir.

Frontend auth store sorgusu artık stores tablosunu kullanır; Phase 2 migration kurulmadan mevcut giriş sonrası mağaza sorgusu migration mesajı verir. Eski onboarding tablosu silinmez, kayıtlar core tablolara korunarak taşınır. Başlangıç sermayesi client tarafından değil SQL/RPC tarafından bir kez verilir. Yeni gameplay veya dashboard KPI eklenmedi.

PGlite yalnızca devDependency olarak eklendi. Uygulamayı başlatmak için halen bağımlılık kurulumu gerekmez. SQL testleri için pnpm install --frozen-lockfile (veya npm install), ardından node scripts/database-check.js. Tüm kontroller: npm run check; npm yoksa node scripts/check.js, node scripts/auth-check.js ve node scripts/database-check.js.

Yerel testler: migrations ve seed SQL gerçekten çalıştırıldı; eski kullanıcı aktarımı, tekrar migration, tek sermaye, duplicate request, duplicate username/store, invalid name, rollback, anon/kimliksiz RPC, başka oyuncu verilerine erişim, client write reddi, immutable ledger, negatif inventory miktarı, net worth ve stok korunması geçti. Gerçek Supabase Auth happy path ve bağımsız DB session concurrency testi canlı proje üzerinde ayrıca yapılmalıdır. Public API anahtarıyla sadece bağlantı kontrol edilmiştir; hesabınız adına test kullanıcı oluşturulmadı.

## Phase 3 — Dashboard

Supabase SQL Editor’da yalnızca supabase/migrations/003_dashboard.sql dosyasını çalıştırın. Önceki SQL dosyalarını yeniden çalıştırmanız gerekmez. Ardından game.html#dashboard ekranındaki Yenile butonuna basın. Migration salt okunur my_dashboard RPC ekler; mevcut para/envanter/verileri değiştirmez.

Nakit, net değer, bugünün satış geliri, kâr, sipariş/satış işlemi sayısı ve envanter adedi gerçek server snapshot’tan gösterilir. Depo kapasitesi, stok maliyeti, stok tahmini değeri, mağaza seviyesi/itibarı ve son altı ledger hareketi de gösterilir. Son yedi gün gelir/sipariş tablosu gerçek tarih kayıtlarını kullanır. Grafik veya sahte trend yoktur.

Bugün hesabı PostgreSQL now() ve Europe/Istanbul ile yapılır; tarayıcı saati veri seçmez. Para ve toplamlar API’de string döner, frontend BigInt ile kuruş hassasiyetini korur. RPC kimlik parametresi almaz, auth.uid üzerinden yalnızca kendi mağazasını toplar. Inactive ürünler stok/net değer hesabından çıkarılmaz.

Ciro yalnızca NPC_SALE/MARKETPLACE_SALE tutarlarını toplar; başlangıç sermayesi, kredi ve toptan alımlar satış sayılmaz. Sipariş sayısı bu satış ledger satırlarının sayısıdır; Phase 6/7 satış RPC’lerinde bir sipariş için tek satış hareketi yaklaşımı korunmalıdır. Marketplace gross/net ücret semantiği Phase 7’de kesinleştirilecek. Phase 2 ledger satış maliyetini tutmadığı için satış yoksa kâr 0, satış varsa kâr bilinmiyor (—) olarak gösterilir. Phase 6 ile satılan ürün maliyetini kaydeden model ve gerçek kâr hesabı eklenecek; ciro kâr gibi sunulmaz.

Yeni dosyalar: js/dashboard.js ve supabase/migrations/003_dashboard.sql. Güncellenenler: game.html, js/app.js, js/game-auth.js, js/config.js, css/dashboard.css, scripts/database-check.js ve README dosyaları.

Testler: mevcut syntax/auth/core kontrollerine ek olarak dashboard SQL’i yerel PostgreSQL’de çalıştırıldı. Sahiplik izolasyonu, boş satış metrikleri, inactive stok değeri, bilinmeyen maliyetin null kâr göstermesi, İstanbul gece yarısı sınırı, 7 günlük geçmiş ve yetkisiz/mağazasız çağrı kontrolleri geçti. Test satış kayıtları yalnızca yerel test motorunda oluşur, canlı oyuncu verilerine yazılmaz.

Canlı tarayıcı kontrolünde mevcut TrendBurada mağazasının oturumu korundu. 003 henüz uygulanmadığında dashboard açık kurulum mesajı ve yeniden deneme gösteriyor; sahte metrik göstermiyor. 390px kurulum ekranında yatay taşma görülmedi.
`n003 migration kullanıcı tarafından uygulandıktan sonra canlı dashboard doğrulandı: TrendBurada nakit/net değer 10.000 ₺, stok 0/50, satış metrikleri 0 ve başlangıç sermayesi ledger kaydı görüntülendi. Konsolda hata/uyarı yok. 390px mobil ve 1440px masaüstü taşma kontrolleri geçti. Canlı oyuncu verisine test satışları yazılmadı.

## Phase 4 — Wholesale

Supabase SQL Editor’da sadece supabase/migrations/004_wholesale.sql dosyasını çalıştırın. game.html#wholesale ekranında Yenile butonunu kullanın. Önceki migration/seed tekrar gerekmez.

Ürün, kategori, rarity, toptan fiyat, tahmini piyasa fiyatı, stok, talep ve miktar gösterilir; isim araması ve kategori filtresi vardır. Trend verisi Coming in Phase 8 olarak belirtilir. Satış/NPC veya inventory yönetim ekranı bu faza dahil değildir. Tahmini market fiyatı bir satış garantisi değildir.

wholesale_catalog finansal değerleri string olarak döndürür. buy_wholesale(product_id, quantity, expected_price_kurus, request_id) authenticated RPC’si fiyatı ürün tablosundan alır; expected_price sadece fiyat değişikliği kontrolüdür. Miktar 1–1000 tam sayı. Kullanıcı auth.uid ile belirlenir. Mağaza row lock, ardından ürün row lock alınır. Aynı oyuncunun tüm ekonomik yazma işlemleri gelecekte de önce mağaza kilidini almalı; çok ürünlü işlemler deterministik sırayla ürün kilitlemelidir. Bu protokol depo toplamı/bakiye ve tedarikçi stok yarışlarını engeller.

Bakiye düşümü, tedarikçi stok azaltımı, ağırlıklı ortalama envanter maliyeti, immutable ledger ve receipt tek PostgreSQL transaction içindedir. Ortalama maliyet numeric hesapla en yakın kuruşa yuvarlanır; sonraki satış fazı bu yuvarlama yaklaşımını tutarlı korumalıdır. Başarısız adımda tümü rollback edilir.

Mağaza/request UUID benzersiz receipt sayesinde aynı istek önceki sonucu döndürür; farklı payload ile aynı UUID W0008 döner. Başarılı yanıt kaybolursa istemci localStorage’da kullanıcıya ait pending işlem kimliğini korur ve yeni işlem yapmadan aynı UUID ile tekrar sorgular. Para/envanter localStorage’da tutulmaz. Onaylı başarısızlık veya başarıda pending temizlenir. Birden fazla tarayıcı sekmesinin farklı UUID ile isteği ayrı satın almalardır; uygulama yeni işlem istemini bilinçli şekilde ayrı tutar.

Yeni dosyalar: css/wholesale.css, js/wholesale.js, js/wholesale-service.js, supabase/migrations/004_wholesale.sql, scripts/wholesale-check.js. Güncellenenler: game.html, js/app.js, js/dashboard.js, js/config.js, package.json, scripts/database-check.js ve README dosyaları.

Testler: happy path, bakiye/stok/depo/miktar/auth reddi, fiyat değişikliği, inactive ürün, ağırlıklı maliyet, tekrar UUID, farklı payload, receipt RLS ve ledger başarısızlığında tam rollback. PGlite tek session çalışır; Promise.all tekrar testleri bağımsız PostgreSQL session yarış testinin yerine geçmez. Canlı bağımsız-session testi için iki hesaptan aynı son stok ürününe paralel RPC gönderin: sadece stok kadar işlem başarıyla tamamlanmalı. Aynı hesap/UUID paralel çağrılar tek ledger/receipt oluşturmalı; farklı UUID ile toplam depo sınırını aşan çağrılardan yalnızca kapasiteye sığanlar başarılı olmalı.

Veritabanı bütçe, miktar, sahiplik ve idempotency kuralları aktif. Request flood için daha ileri API/gateway rate limit henüz eklenmedi; üretime açılmadan anti-cheat fazında tamamlanmalı.
`nPhase 4 canlı doğrulama: 004 migration kullanıcı tarafından uygulandı. 50 ürün katalogda yüklendi; arama çalıştı. TrendBurada hesabında 1 Gel Pen Set 120 ₺ oyun bakiyesiyle alındı; bakiye 9.880 ₺, depo 1/50, supplier stock 799, stok maliyeti 120 ₺, market value 168 ₺, net worth 10.048 ₺ ve ledger -120 ₺ görüldü. 100 adet denemesi yetersiz bakiye, 60 adet denemesi kapasite nedeniyle reddedildi; envanter/bakiye sabit kaldı. 390px mobil yatay taşma yok; konsol error/warn yok. Test ürünü oyuncu envanterinde bırakıldı. Bağımsız PostgreSQL session concurrency testi henüz yapılmadı.

## Phase 5 — Inventory

Supabase SQL Editor’da sadece supabase/migrations/005_inventory.sql dosyasını çalıştırın; game.html#inventory ekranında Yenile’ye basın. Migration salt okunur my_inventory RPC ekler; bakiye, stok ve mevcut satın alma akışını değiştirmez.

Envanter ürün adedi, ağırlıklı ortalama birim maliyet, piyasa fiyatı, stok değeri ve gerçekleşmemiş potansiyel kârı gösterir. Toplam depo kullanımı, stok maliyeti/değeri ve potansiyel kâr sunucuda hesaplanır. Finansal değerler string, çarpımlar numeric, frontend para formatı BigInt kullanır. Arama filtresi toplam depo özetini değiştirmez. Inactive owned ürünler dahil edilir; sıfır miktarlı satırlar gösterilmez.

Potansiyel kâr = miktar × (market fiyatı − average cost). Masraflar/komisyonlar hariç tahmindir, gerçekleşmiş satış veya garanti değildir. Weighted average rounding Phase 4 yaklaşımını aynen kullanır; yeni maliyet yöntemi eklenmedi.

RPC security definer ancak kimlik parametresi kabul etmez; auth.uid ile kendi mağazasını sınırlar. Anon rolünde execute kapalıdır; oturumsuz/mağazasız authenticated çağrı reddedilir. Değişiklikler: js/inventory.js, supabase/migrations/005_inventory.sql, game.html, js/app.js, js/config.js, css/dashboard.css, scripts/database-check.js ve README dosyaları.

SQL testlerinde sahiplik izolasyonu, boş depo, inactive ürün, maliyet hesapları, negatif potansiyel kâr ve yeniden migration geçti. Önceki auth/dashboard/wholesale kontrolleri de geçti. Phase 5 stok görüntülemedir; satış/fiyat belirleme NPC sales fazında açılacak.
`nPhase 5 canlı doğrulama: 005 migration kullanıcı tarafından uygulandı. TrendBurada envanterinde mevcut 50 Gel Pen Set, ortalama maliyet 120 ₺, piyasa fiyatı 168 ₺, toplam maliyet 6.000 ₺, stok değeri 8.400 ₺ ve potansiyel kâr 2.400 ₺ görüntülendi. Arama boş sonucu doğru; filtre genel toplamları değiştirmiyor. 390px/1440px görünüm kontrollerinde sayfa yatay taşması yok, konsol error/warn yok. Bu fazda canlı stok/bakiye değiştirilmedi.

## Phase 6 — NPC Sales

Supabase SQL Editor’da sadece supabase/migrations/006_npc_sales.sql dosyasını çalıştırın. Siparişler ekranında kendi stok ürününü fiyatlandırıp Satışa açık seçeneğini işaretleyin, Kaydet’e basın ve Satış motorunu başlatın. Bu faz fiyatlama, online NPC simülasyonu ve son 20 NPC siparişini ekler. XP/level ödülleri Phase 10’da; offline simülasyon Phase 19’da.

Sunucu store row lock ile 60 saniyelik fırsatı sınırlar. Sekme görünürken frontend 15 saniyede bir yoklar; bu aralık para üretme yetkisi değildir. İlk çağrı zamanlayıcıyı başlatır. Son çağrı 120 saniyeden eskiyse birikmiş süreyi işlemek yerine yeni 60 saniyelik dönem başlatılır. Offline catch-up yapılmaz. Her tick, aktif listing ve stoklu ürün başına en fazla 1 adet satabilir.

Olasılık = min(1, demand/100 × (market_price/sale_price)^2 × (0,5 + reputation/200)). Olasılık PostgreSQL random ile sunucuda uygulanır; client satış sonucu/zamanı/miktarı göndermez. Düşük fiyat satış hızını artırır ama maliyet altı satış zarar verir. Bu ilk ekonomi modelidir; balancing fazında ayarlanacak.

set_npc_listing sadece kendi mağazasını değiştirir; aktif ürün sayısı listing_limit ile sınırlandırılır, enabled ilan stok ister. Fiyat 1–1.000.000.000.000 kuruş arasıdır. Tüm ekonomik mutasyonlar önce store kilidini alır; satış cash/quantity/reputation/immutable ledger aynı transaction’da güncellenir. Stok tükenince ilan pasife alınır. Tedarik satışından kaldırılmış owned ürün hâlâ NPC’ye satılabilir.

Ledger’a sale_quantity ve cost_of_goods_kurus nullable alanları eklenir. Yeni NPC satışlarında maliyet kayıt altına alınır; dashboard günün satış gelirinden COGS düşer. Eski maliyetsiz satışlar bilinmiyor kalır. Marketplace ücretleri Phase 7’de bu hesapla uyumlu ele alınacak.

Yeni dosyalar: js/sales.js, supabase/migrations/006_npc_sales.sql. Güncellenenler: game.html, js/app.js, js/dashboard.js, js/config.js, css/wholesale.css, scripts/database-check.js ve README dosyaları.
`nPhase 6 yerel kontrolleri: server cooldown/kimlik doğrulama, stock ownership, listing limiti, zero-demand, no offline catch-up, negatif gerçekleşen kâr, sold-out auto-pause ve ledger hatasında clock/cash/stock/reputation rollback testleri geçti. Önceki auth/dashboard/inventory/wholesale regresyon testleri geçti. PGlite tek-session testidir; bağımsız PostgreSQL session concurrency testi hâlâ canlı deployment kontrolüdür.

Phase 6 canlı test: 006 uygulandı. Gel Pen Set 125 ₺ fiyatla 1 NPC siparişinde satıldı: gelir 125 ₺, maliyet 120 ₺, kâr 5 ₺, stok 49, bakiye 4.125 ₺ ve itibar 1. Dashboard sipariş/ciro/kâr kayıtları doğrulandı. Fiyat 168 ₺ olarak geri alındı, ilan kapatıldı; motor çalışır halde bırakılmadı. Mobil taşma ve konsol hatası yok. Gerçek sipariş ledger’da korunur.

## Phase 7 — Marketplace

SQL Editor’da sadece supabase/migrations/007_marketplace.sql dosyasını çalıştırın. game.html#marketplace ekranında ürün/adet/fiyat ile ilan oluşturun. Kendi ilanlarınız iptal edilebilir; başka mağazaların ilanları satın alınabilir. Kendi ilanını satın alma server tarafından reddedilir. İlanlar 50 satırlık sayfalar halinde gösterilir.

Inventory.quantity toplam sahip olunan stoktur; reserved_quantity ilanda ayrılmış bölümdür. Depo kapasitesi ve net değer ayrılmış stoğu saymaya devam eder. NPC motoru yalnızca serbest stoğu satabilir. İptal sadece rezervasyonu kaldırır; para/ürün yaratmaz. Satış gerçekleşince seller toplam/adet rezervasyonu birlikte azalır, alıcı inventory weighted average güncellenir.

Fee config: public.economy_settings.marketplace_fee_bps (500 = %5). Yetkili SQL Editor’dan UPDATE public.economy_settings SET marketplace_fee_bps=500 WHERE id=true; ile değişir. Client bu ayarı değiştiremez. Kuruş bazında işlem başına en yakın tam kuruşa yuvarlanır. Marketplace_SALE gross tutarı, MARKETPLACE_FEE ayrı negatif ledger hareketidir; dashboard kârı gross − COGS − fee olarak hesaplanır.

Create ve buy request UUID ile idempotenttir. Aynı key/farklı payload reddedilir. Cancel tekrar çağrılabilir. Frontend pending RPC/payload sadece ilgili kullanıcıya ait localStorage key ile saklanır; belirsiz ağ sonucunda aynı işlem tekrar sorgulanır, yeni işlem engellenir. Parasal otorite her zaman server’dır.

İki tarafın store row lock’ları UUID sırasıyla alınır, sonra listing kilitlenir. Tek-store wholesale/NPC/ilan/iptal operasyonları da önce store kilidini kullanır. Satış, alıcı/satıcı bakiyeleri, reserved stok, envanter, fee ve receipt/immutable ledger tek transaction’da yazılır. Başarısız adım tümüyle rollback edilir. Fonksiyonlar user_id/seller_id kabul etmez, auth.uid ve immutable listing ownership üzerinden belirler. Public Marketplace RPC yalnızca ürün/satıcı mağaza adı/fiyat/stok gösterir; cash, user email veya özel profil döndürmez.

Seviye kilitleri Phase 10 progression kapsamındadır; bu geliştirme fazında Marketplace oyunculara açıktır. Public player profile, auction ve contracts eklenmedi.

Yeni dosyalar: js/marketplace.js, supabase/migrations/007_marketplace.sql, scripts/marketplace-race-check.js, pnpm-workspace.yaml. Güncellenenler: game.html, js/app.js, js/inventory.js, js/dashboard.js, js/utils.js, js/config.js, css/wholesale.css, scripts/database-check.js, package.json, pnpm-lock.yaml, .gitignore ve README dosyaları.

### Testler

PGlite core suite: reservation, idempotency, stock/ownership/self-buy/funds/capacity/price reddi, cancelled/sold stock, buyer weighted average, server fee, realized net profit ve ledger hatasında iki taraf için rollback.

Gerçek bağımsız PostgreSQL session race testleri: node scripts/marketplace-race-check.js (veya npm run check:race). Embedded PostgreSQL 18 test server localhost 55439 üzerinde başlar ve finally içinde kapanır. Auth rollerini/uid fonksiyonunu emüle eder; Supabase’e canlı veri yazmaz. İkinci bağlantının pg_stat_activity Lock durumunda beklediği doğrulanır. Son stok, duplicate UUID, aynı alıcının depo kapasitesi ve cancel/buy yarışları geçti. Üç satışta toplam para tam komisyon kadar azaldı (conservation).

Dev dependencies embedded-postgres ve pg eklendi; pnpm-workspace.yaml yalnızca Windows binary paketinin gerekli kurulum betiğine izin verir. Kaynak: [embedded-postgres](https://github.com/leinelissen/embedded-postgres). Test cluster dizinleri .test-db-race altında ignored olarak kalır; test bittikten sonra server açık bırakılmaz. Uygulama için Node server yeterli, geliştirme testleri için pnpm install --frozen-lockfile gerekir. Test portu doluysa yerel test server config portunu değiştirin.

Phase 7 canlı doğrulama: 007 migration kullanıcı tarafından uygulandı. TrendBurada hesabında 1 Gel Pen Set için 168 ₺ ilan oluşturuldu; 48 toplam stok, 1 ayrılmış / 47 serbest olarak envanterde görüldü. İptal sonrası 48 adet serbest kaldı, aktif test ilanı kalmadı. İlan rezervasyonu toplam depo maliyeti 5.760 ₺ ve piyasa değerini 8.064 ₺ değiştirmedi. 390px mobil görünümde yatay taşma ve konsolda error/warn yok. Canlı iki hesap arasında satın alım denenmedi; satın alma ve yarış durumları yerel bağımsız PostgreSQL bağlantılarıyla doğrulandı. Görünüm: docs/phase7-marketplace.png. Phase 7 tamamlandı; sonraki aşama Phase 8 Economy Engine.
## Phase 8 — Economy Engine

Mevcut kurulumda yalnızca supabase/migrations/008_economy.sql uygulanır. Önceki SQL dosyalarını tekrar çalıştırmayın. Ön koşul 001–007 ve seed.sql; yeni kurulumda seed 008'den önce çalışmalıdır. Migration başlangıç fiyatlarını/demand/supply değerlerini referans olarak kaydeder, mevcut parayı, oyuncu envanterini ve satış ilanı fiyatlarını değiştirmez. İlk history kaydı mevcut fiyatla oluşturulur; reapply referansları ve global clock'u sıfırlamaz.

Global online piyasa adımı en erken 300 saniyede bir process_market_tick RPC ile çalışır. Oyun açık ve sekme görünürken istemci bütün ekranlarda 60 saniyede bir kontrol eder. İstemci zaman/fiyat/oyuncu kimliği göndermez. Uzun aradan sonra yalnızca tek adım uygulanır; offline fiyat ve stok yakalaması yoktur. Bu fazda cron veya daimi arka plan worker eklenmedi. Bütün oyuncular aynı global ürün fiyatlarını kullanır.

Demand, ürünün referans talebine göre ±%20 yavaş kategori döngüsünden hesaplanır (0–100). Supply, referans arzın supplier stock / hedef stok oranıyla ölçeklenir (0–100). Hedefler Common 2500, Uncommon 800, Rare 200, Epic 40, Legendary 10; her adımda hedefin en fazla %5'i tedarik edilir, hedef üstündeki stok azaltılmaz. Hedef fiyat = başlangıç piyasa referansı × demand/reference demand × clamp(1 + (1 − stock/target) × 0.5, 0.75, 1.5). Sıfır referans demand için modifier 1; NPC talebi sıfır kalır. Event modifier bu fazda 1; etkinlikler Phase 9'da.

Her adımda piyasa ve toptan fiyat en fazla ±%5 değişebilir. Tam kuruşa ceil/floor limitleri uygulanır; fiyat referansın %50–%200 aralığında ve ürün şemasının 1–1e12 kuruş sınırlarında kalır. Toptan hedef fiyat orijinal wholesale/market oranını korur; ayrı %5 sınırı nedeniyle geçişte oran geçici farklılaşabilir. Toptan satın alımdaki expected-price kontrolü fiyat değişimini reddeder. Oyuncu NPC/Marketplace ilan fiyatları otomatik değiştirilmez. Güncel market price envanter/net değer ve NPC satış olasılığı hesaplarında kullanılır.

Global clock kilidi, ardından UUID sıralı product kilitleri alınır. Motor store/inventory kilidi almaz; mevcut store→product satın alma sırasıyla kilit döngüsü oluşturmaz. Clock/fiyat/tedarik/history tek transaction'dır. Underlying economy tabloları RLS ile kapalı, istemci yalnızca authenticated ve mağazası olan kullanıcı adına RPC çalıştırabilir; ürün/zaman/ayar değiştiremez. Cash veya ledger üretmez.

Piyasa ekranı 8 kategori eğilimi, ürün arz/talep/tedarikçi stoğu, piyasa/toptan fiyatı ve gerçek fiyat geçmişini gösterir. Dashboard'da kategori kartları bulunur. Eğilim, kategori ürünlerinin başlangıç referansına göre yüzdelik fiyat değişiminin eşit ağırlıklı ortalamasıdır; 24 saatlik getiri değildir. 1H/24H/7D/30D geçmiş filtreleri mevcut gerçek kayıtlardan sırasıyla 1/5/60/240 dakikalık dilimlerin son kaydını gösterir. Maksimum yaklaşık 289 nokta; fiyat geçmişi indeksli tabloda saklanır, eski veri uydurulmaz. İlk tek kayıt için grafik yerine bekleme açıklaması gösterilir. Grafik sayısal tabloyla erişilebilir; zamanlar İstanbul saatidir.

Yeni dosyalar: supabase/migrations/008_economy.sql, js/economy.js, css/economy.css, scripts/economy-check.js. Güncellenenler: game.html, js/app.js, js/config.js, package.json, scripts/marketplace-race-check.js ve README dosyaları.

Yerel testler geçti: 35 adım fiyat hareketi ve hard bounds, supplier refill, cooldown/no catch-up, demand/supply aralıkları, history filtreleri, kategori ortalamaları, cash/ledger conservation, auth/RLS, migration replay, history hatasında tam rollback. Önceki fazların regresyon kontrolleri geçti. Bağımsız gerçek PostgreSQL bağlantıları aynı global tick'i yalnızca bir kez işler; wholesale product kilidiyle eşzamanlı güncellemede stok 100 → satın alma sonrası 99 → tedarik sonrası 224 kaldı, azaltım kaybolmadı. Çalıştırma: node scripts/economy-check.js ve node scripts/marketplace-race-check.js. Canlı Supabase kontrolü 008 uygulandıktan sonra yapılacak.

Phase 8 canlı doğrulama: 008 kullanıcı tarafından uygulandı. 50 ürün, 8 kategori, ürün seçimi ve 1H/24H/7D/30D filtreleri yüklendi. İlk gerçek piyasa adımında Gel Pen Set market 168,00 → 176,40 ₺, wholesale 120,00 → 126,00 ₺ (%5); supplier stock 750 → 790, demand 74 → 86, supply 84 → 83 oldu. İkinci history kaydı ve SVG grafik oluştu; erken tekrar kontrolde üçüncü kayıt üretilmedi. Envanter 48 adet ve maliyet 5.760 ₺ korunurken piyasa değeri 8.467,20 ₺ oldu. Nakit 4.293 ₺ sabit, net değer 12.760,20 ₺; dashboard kategori kartları yeni fiyatları gösterdi. 390px grafikli mobil görünümde taşma yok, migration sonrası reload konsol error/warn yok. Test için canlı satın alım veya NPC satışı yapılmadı. Görünüm docs/phase8-economy.png. Phase 8 tamamlandı; sonraki aşama Phase 9 Market Events.

## Phase 9 — Market Events

Mevcut kurulumda yalnızca supabase/migrations/009_market_events.sql uygulanır. Ön koşul 001–008 ve seed.sql; eski 004/008 fonksiyon migrationlarını tek başına yeniden uygulamak yeni catalog/scheduler/limited-stock davranışını geri alır. Migration ekonomik veriyi sıfırlamaz. 51. ürün Founder Limited Mouse (Legendary, drop-only) eklenir; normal wholesale katalog 50 ürün kalır, Piyasa fiyat takibi 51 aktif ürün içerir.

Server market_schedule.anchor_at üzerinden saatlik program kurar. Şimdiki ve sonraki saat için bir global event, %30 referans indirimli flash deal ve 25 adet limited drop partisi oluşturur. Saat başına event 45, flash 15, drop 20 dakika sürer; aralarda sakin dönem vardır. Clock kilidi altında unique slot/kind ile bir kez oluşturulur. Uzun offline aradan sonra yalnızca şimdiki/sonraki program üretilir; kaçırılan her saat için stok veya fırsat oluşturulmaz. Migration rerun alınmış stoğu/anchor'u resetlemez. Arka plan cron eklenmedi; görünen oyun sekmesindeki global market kontrolü programı ilerletir.

Etkinlikler sırayla Technology chip shortage (supply ×0.65, hedef fiyat ×1.20), Gaming festival (demand ×1.45), Cosmetics shipment (supply ×1.25, hedef fiyat ×0.90) ve Sports season (demand ×1.30). Her kayıt starts_at, ends_at, category, supply/demand/price bps ve haber metni içerir. Bir kategoride çakışan admin etkinliklerinin en yeni başlayanı uygulanır; modifiers stack olmaz. Aktif event, tick timestamp'ında talep skorunu, arz skorunu, tedarik yenileme hızını ve hedef fiyatı etkiler. Demand/supply 0–100; mevcut ±%5 adım ve %50–%200 baseline fiyat sınırları korunur. Bitiş sonrası bir sonraki fiyat adımında modifiers kalkar; fiyatlar normal sınırlı adımlarla geri döner. Haberlerde hedef fiyat değişimi doğrudan gerçekleşmiş anlık fiyat artışı gibi sunulmaz.

Flash deal normal active Common/Uncommon ürünlerden seçilir. Referans normal fiyat ve %30 indirimli kuruş fiyatı program oluşturulurken sabitlenir; yakındaki fırsat fiyatı sonraki piyasa hareketlerinde değişmez. Kart oluşturulduğundaki ve şu anki normal wholesale fiyatını karşılaştırmak için gösterir. Fırsat kotası ve gerçek supplier stock birlikte sınırdır; normal wholesale satışları da supplier stock'u tüketebilir. Normal stok önceden reserve edilmez, RPC gerçek stoğu yeniden kontrol eder.

Limited drop ayrı market_offers kotası kullanır. Founder Limited Mouse normal supplier stock'u 0'dır; ekonomi motoru drop-only ürününü otomatik restock etmez. Her parti en fazla 25 adet verir. Biten partinin kalan stoğu sonraki partiye aktarılmaz; yeni parti ayrı ID/kotadır. Satın alınan ürün gerçek inventory/weighted average cost'a girer, NPC/Marketplace akışlarıyla uyumludur. Bu faz seri numarası/collection/auction eklemez.

buy_market_offer client'tan only offer UUID, qty, expected fixed kurus price ve request UUID alır. auth.uid ile store → product → offer kilitlerini alır; clock_timestamp ile kilit bekledikten sonraki gerçek süreyi kontrol eder. Miktar, aktif pencere, fiyat, quota, supplier stock, cash ve total warehouse capacity doğrulanır. Cash, offer quota, flash supplier stock, inventory weighted cost, WHOLESALE_PURCHASE ledger ve immutable receipt aynı transaction'da yazılır. Ledger idempotency prefix offer:; ayrı store/request unique receipts. Aynı UUID/payload tekrarında sold-out/expired olsa bile önceki receipt döner, ikinci transfer yapılmaz; farklı payload reddedilir. Server snapshot özel oyuncu bilgilerini göstermez; receipt sadece kendi mağazasına açık RLS'dir. Event/offer/schedule/drop mapping tablolarında client write/read yetkisi yoktur; safe RPC kullanılır.

Piyasa ekranı market news, açık/yaklaşan fırsatlar, server saatine dayanan countdown ve son 20 kendi fırsat alımını gösterir. Upcoming/sold-out/expired kartlar satın alınamaz; server yine süre/stok doğrular. Dashboard aktif/yaklaşan haber kartları gösterir. Toptan pazardan fırsat ekranına bağlantı ve Phase 8'den kalan placeholder yerine gerçek başlangıç-referans trendi eklendi. Frontend belirsiz ağ sonucu için user-scoped localStorage pending payload saklar ve aynı request ile tekrar kontrol eder; yeni alımlar doğrulanana kadar engellenir.

Yeni dosyalar: supabase/migrations/009_market_events.sql, js/events.js, js/events-service.js, css/events.css, scripts/events-check.js, scripts/events-service-check.js. Güncellenenler: game.html, js/config.js, js/wholesale.js, package.json, scripts/marketplace-race-check.js ve README dosyaları.

Yerel kontroller geçti: etkinlik takvimi/süre dolumu, Gaming demand modifier ve Technology supply/refill, price caps, no offline batches, sabit offer fiyatı, weighted inventory cost, funds/capacity/stock/ownership/auth/RLS, expiry sonrası idempotent retry, immutable receipt, ledger failure tam rollback ve limited-drop Marketplace resale. Bağımsız gerçek PostgreSQL bağlantılarıyla last-unit race, concurrent same-request retry ve transaction başlangıcı expiry'den önce olup ürün kilidinde beklerken gerçek süre dolduğunda reddedilen alım geçti. Önceki faz regresyon kontrolleri geçti. Komutlar: node scripts/events-check.js, node scripts/events-service-check.js, node scripts/marketplace-race-check.js. Canlı doğrulama 009 uygulandıktan sonra yapılacak.

Phase 9 canlı doğrulama: 009 kullanıcı tarafından uygulandı. Aktif Technology chip shortage ve yaklaşan Gaming festival haberi Piyasa/Dashboard'da görüldü. Aktif Gel Pen Set flash deal referans 115,14 ₺ → 80,60 ₺, 100 adet; Founder Limited Mouse Legendary drop 25 adet ve 1.800 ₺ olarak yüklendi. Gelecek partilerin alım düğmeleri kapalı; countdown sunucu snapshot'ından ilerliyor. 1 flash deal alımı geçti: cash 4.293 → 4.212,40 ₺, inventory 48 → 49, offer quota 100 → 99, ledger −80,60 ₺ ve kalıcı receipt geçmişi görüldü. Ağırlıklı ortalama maliyet 119,20 ₺; stok maliyeti 5.840,80 ₺ (ortalama maliyet tam kuruşa yuvarlanır). İkinci 2 adetlik kapasite denemesi reddedildi, offer quota 99 kaldı. Limited drop ürünü normal katalog aramasında bulunmadı; normal katalog hâlâ 50 ürün. 390px görünümde yatay taşma yok; migration sonrası reload console error/warn yok. Canlı limited drop satın alımı yapılmadı; drop transferi/Marketplace resale yerel PostgreSQL testinde geçti. Testte alınan 1 Gel Pen Set envanterde bırakıldı. Görünüm docs/phase9-market-events.png. Phase 9 tamamlandı; sonraki aşama Phase 10 Progression.
## Phase 10 — Progression

Yeni kurulum adımı: `supabase/migrations/010_progression.sql`. Ön koşul 001–009 ve seed.sql. Migration nakit veya envanteri sıfırlamaz. Önceki Marketplace fonksiyon migrationlarını tek başına yeniden çalıştırmayın; Phase 10 sunucu seviye kontrolünü geri alabilir.

İlerleme ekranı 9 başarım, 7 günlük/haftalık görev, XP geçmişi ve seviye hedeflerini gösterir. Profilde kazanılmış unvan seçilebilir. Dashboard XP özeti içerir. Marketplace alım/ilan oluşturma seviye 5'te açılır; mevcut ilan iptali ve daha önce tamamlanmış isteğin yeniden doğrulanması korunur. Sonraki sistemlerin seviye hedefleri “Yakında” olarak gösterilir.

Seviye formülü `min(50, floor(sqrt(XP/100))+1)`; seviye 5 eşiği 1.600 XP. Maliyet bilgisi bulunan kârlı NPC satışları ürün başına 10 XP, işlem başına en fazla 100 ve İstanbul günü başına 2.000 satış XP verir. Önceki kayıtlar aynı günlük sınırla yalnızca bir kez işlenir. Başarım ve görev XP'si bu satış sınırından ayrıdır. P2P satışlar doğrudan satış XP veya günlük ciro ödülü üretmez. Marketplace görevleri en az 5 ₺ komisyonlu işlemleri sayar ve yalnızca XP verir.

Günlük görevler İstanbul 00:00, haftalık görevler pazartesi 00:00 dönemine göre gerçek makbuz/ledger kayıtlarını sayar. Eksik veya geçmiş dönem ödülü alınamaz. Kazanılmış görev ödülü oyuncunun talebiyle tek transaction'da nakit ledger, XP, unvan ve immutable makbuza yazılır. Mağaza/görev/dönem anahtarıyla retry önceki sonucu döndürür; istemci belirsiz ağ sonucu için aynı dönem ve görevi saklar. Başarımlar otomatik, unvan seçimi yalnızca oyuncunun kazanmış olduklarından yapılır. RLS kendi ilerleme kayıtlarına okumayı sınırlar; XP ve metrik fonksiyonları istemciye kapalıdır.

Kontroller: `node scripts/progression-check.js` ve `node scripts/marketplace-race-check.js`. Yerel testler XP cap/kârlılık, migration replay, başarım tekrarları, görev dönemleri/ödül tekrarları, unvan/RLS/özel RPC yetkileri ve seviye kilidini doğruladı. Gerçek bağımsız PostgreSQL bağlantılarında eşzamanlı aynı ödül tek ledger kaydı oluşturdu; karşı yönlü oyuncu ticaretleri sıralı mağaza kilitleriyle tamamlandı. Canlı doğrulama 010 uygulandıktan sonra yapılacak.

Phase 10 canlı doğrulama: 010 kullanıcı tarafından uygulandı. Önceki 13 kârlı NPC satışı ve 52 toptan/fırsat ürünü 380 XP ve seviye 2 olarak işlendi; İlk satış, Girişimci ve Toptancı başarımları açıldı. Günlük ve haftalık tedarik ödülleri alındı: toplam +300 XP, +125 ₺ oyun parası; sonuç 680 XP/seviye 3. Dashboard ledger'da ayrı 25 ₺ ve 100 ₺ ödül kayıtları, nakit 5.587,80 ₺ görüldü. Görevler “Ödül alındı” ile yeniden alıma kapalı kaldı. Profil Entrepreneur/Founder/Wholesaler seçeneklerini gösterdi; aktif unvan değiştirilmedi. Marketplace ilan oluşturma seviye 5 altında kapalı ve açıklamalı. 390px görünümde yatay taşma yok; console error/warn yok. Yerel ödül ledger hata testinde cash/XP/unvan/makbuz tamamen geri alındı. Görünüm docs/phase10-progression.png. Phase 10 tamamlandı; sonraki aşama Phase 11 Business Management.


## Phase 11 — Business Management

Kurulum: yalnızca supabase/migrations/011_business.sql; ön koşul 001–010 ve seed.sql. Veriler sıfırlanmaz. Eski 006/007 dashboard/NPC fonksiyonlarını tek başına tekrar uygulamayın: şirket giderleri ve bonuslarını geri alabilir. Şirket ekranı depo/ofis kademeleri, marka, reklam, altı çalışan rolü ve son 20 kalıcı işlem makbuzunu gösterir.

Depo kapasitesi 50 → 250 → 1.000 → 5.000 → 25.000; sırayla 2.500/10.000/50.000/250.000 ₺ ve minimum seviye 1/5/10/20. Ofis Garage → Small → Business Center → Corporate HQ → Mega Campus; kontenjan 1/3/4/5/6, fiyat 5.000/25.000/100.000/500.000 ₺, minimum seviye 5/10/20/30. Her yeni kademe 100/250/500/1.000 XP verir. Aynı kademe tekrar alınamaz. Ücretin %50'si şirket varlığına eklenir, %50'si gider olur; nakitten ücretin tamamı düşer. Varlıkların satış/likidasyon akışı bu fazda yoktur. Depo kapasitesi legacy daha büyük kapasiteyi düşürmez.

Reklam seviye 10: Social 250 ₺/30 dk (erişim +%10, dönüşüm +%5, marka +1), Search 500 ₺/60 dk (+%5/+%15/+2), Influencer 1.500 ₺/120 dk (+%20/+%10/+4), Brand 2.500 ₺/240 dk (+%5/+%5/+5). Aynı anda tek aktif kampanya; ücret peşin, süre gerçek sunucu saatidir. Marka kalıcı 0–100; ofis kademeleri +5/+10/+20/+30 verir. Marka itibardan ayrıdır, NPC fiyat toleransını marka puanı başına %0,2 (en fazla %20) artırır.

Çalışanlar seviye 15'te, her rolden bir tane ve ofis kontenjanıyla alınır. 24 saat maaş peşin ödenir: Sales 200, Purchasing 150, Warehouse 125, Marketing 200, Analyst 175, Logistics 150 ₺. Sırasıyla dönüşüm bonusları %10/%4/%3/%8/%5/%4; becerileri 10/8/6/10/5/7. Bu fazda çalışan seviyeleri 1; sonraki çalışan eğitimi/otomatik satın alma/sevkiyat akışı yoktur. Sözleşme bittiğinde bonus hemen sona erer; elle 24 saat yenileme, erken sonlandırmada iade yok. Otomatik maaş çekimi, borç veya offline gider/satış catch-up eklenmedi.

NPC ihtimali = min(1, eski demand × (market/price × brand factor)^2 × reputation factor × (1 + ekip dönüşümü) × (1 + reklam erişimi) × (1 + reklam dönüşümü)). Sıfır demand sıfır satış kalır. Bu oranlar simülasyon çarpanlarıdır; gerçek ziyaretçi/conversion analitiği gibi sunulmaz. Reserved stok, 60 saniye cooldown, uzun offline aranın tek başlangıç kontrolü, COGS/XP ve atomik ledger korunur. Dashboard satış kârından reklam/maaş ve yükseltmenin gider yarısını çıkaran net günlük kârı gösterir. Ödüller satış kârına dahil edilmez.

Tek business_action RPC kimliği auth.uid ile bulur, mağaza kilidi altında seviye/kademe/nakit/süre/kontenjanı doğrular. Cash, varlık, kapasite, marka, sözleşme, XP, ledger ve immutable makbuz aynı transaction'dır. İstek UUID/payload sabittir; tamamlanan işlemin retry'si süre/seviye/nakit sonradan değişse de aynı sonucu döndürür, farklı payload reddedilir. İstemci belirsiz sonucu user-scoped pending olarak saklar. Client fiyat/bonus/zaman belirleyemez; catalog/effects fonksiyonları kapalı, kendi sözleşme/makbuz kayıtları RLS'yle okunur.

Testler: node scripts/business-check.js ve node scripts/marketplace-race-check.js. Kademe/varlık/gider, seviye/nakit/tekrar kontrolü, maaş/kontenjan/yenileme/sonlandırma, reklam süre/çakışma, gerçek NPC satış/reservation/cooldown/COGS, bonus cap/sıfır demand, auth/RLS/private RPC, migration replay ve ledger hata tam rollback geçti. Gerçek PostgreSQL iki bağımsız oturumda yükseltme retry yalnızca bir ücret, son çalışan kontenjanı yalnızca bir işe alım, aynı anda yalnızca bir reklam üretti. Canlı doğrulama 011 uygulandıktan sonra yapılacak.

Phase 11 canlı doğrulama: 011 kullanıcı tarafından uygulandı. Canlı başlangıç nakdi 5.950,80 ₺, 36/50 ürün, 710 XP/seviye 3, marka 0 ve Garage Office görüldü. Small Warehouse yükseltmesi 2.500 ₺ karşılığında tamamlandı: nakit 3.450,80 ₺, kapasite 250, şirket varlığı 1.250 ₺ ve 810 XP/seviye 3. Dashboard ledger −2.500 ₺, depo 36/250, günlük işletme gideri 1.250 ₺ ve net kâr −1.161,02 ₺ gösterdi. Makbuz ve kademe reload sonrası korundu. Sonraki depo/ofis seviye 5; reklam seviye 10, tüm altı çalışan seviye 15 düğmeleri kapalıydı. Canlı hesap seviyesi yükseltilmedi; reklam/çalışan alım/yenileme/expiry/bonus akışları yerel veritabanlarında doğrulandı. Aktif profil unvanına dokunulmadı. Mobil ve konsol kontrolleri aşağıda kaydedilir. Phase 11 sonrası Phase 12 Advanced Trading için kullanıcı devamı beklenir.

390px şirket görünümünde yatay taşma yok; reload sonrası console error/warn yok. Görüntü docs/phase11-business.png. Phase 11 tamamlandı.

## Phase 12 — Advanced Trading

Yalnızca supabase/migrations/012_advanced_trading.sql dosyasını 011 sonrası çalıştırın. Yeni ekranlar: Açık artırma, Sözleşmeler ve Koleksiyon. Önceki ekonomik veriler korunur. Eski 007/010 fonksiyon migrationlarını tek başına tekrar uygulamayın; özel ilanlar, escrow net değeri ve ortak ilan limiti geri alınabilir.

Rare/Epic/Legendary stoktaki serbest bir adet kalıcı ürün-bazlı sıra numarasıyla serial_items kaydına dönüştürülür. Ürün yeniden üretilmez: aynı inventory adedi reserved kalır, depo ve net değerde sayılır. NPC/normal Marketplace söz konusu adedi satamaz. Seri verme ücretsiz ve seviye 1'de; seri kaldırma/burn bu fazda yoktur. Devir yalnızca açık artırmayla yapılır, numara değişmez. Koleksiyon ekranı tüm Rare/Epic/Legendary ürünlerin sahiplik hedeflerini ve kendi seri numaralarını gösterir.

Açık artırma ve sözleşmeler seviye 5'te açılır. Açık artırma yalnızca kendi seri numaralı ürünün 1 adedi içindir; süre 5/30/60 dakika. Başlangıç fiyatını karşılayan ilk teklif ve sonraki teklifler için en az %5 artış (tam kuruşa ceil, minimum 1 kuruş). En yüksek teklifin oyun parası nakitten escrow'a taşınır; geçilen teklif atomik iade edilir. En fazla 10 kazanan açık teklif. Kendi ilanına teklif verilemez. Escrow tüm net değer hesaplarına dahil; satış/ciro/gider değildir.

Kazanan bitişten sonra 24 saat içinde Teslim al ile ödemeyi tamamlar; depoda 1 boş yer ve satıcıda nakit sınırı kontrol edilir. Seri numarası ve reserved ürün aynı transaction'da geçer; standart sunucu komisyonu uygulanır. Depo doluysa işlem tamamen geri alınır, escrow korunur ve yer açıp tekrar teslim alınabilir. 24 saat dolarsa satıcı veya kazanan İade et ve kapat ile parayı iade eder; seri ürün satıcıda kalır. Teklifsiz ilan satıcı tarafından kapanabilir. Otomatik cron/otomatik teslim yok; kapatma için ilgili tarafın işlem yapması gerekir. Süresi dolmuş açık kayıtlar kapatılana kadar ilan/teklif limitinde sayılır. Snapshot ilk 50 açık ilanı kendi/kazanılan ilanlara öncelik vererek gösterir.

Sözleşme satıcıdan tam mağaza adına gönderilir, miktar 1–1.000, 24 saat sabit fiyat ve stok reservation. Yalnızca iki taraf görebilir. Alıcı kabul/ret, satıcı iptal eder. Kabul tek transaction'da gerçek nakit/stok/weighted-cost/COGS/komisyon/Marketplace receipt yazar. Süresi dolmuş teklifi kabul etme girişimi alım yapmadan expired kapatır; satıcı/alıcının kapatma düğmesi de stoğu serbest bırakır. Özel ilanlar normal Marketplace'te görünmez, normal buy RPC özel statüyü kabul etmez. Aktif normal ilan + özel sözleşme + açık artırma aynı listing_limit bütçesini paylaşır.

trade_action tek oyuncu/request UUID ve tam JSON payload için immutable makbuz saklar; retry aynı sonucu döndürür, payload değişikliği reddedilir. UI belirsiz sonucu aynı UUID/payload ile user-scoped saklar. Çok oyunculu işlemlerde mağazalar UUID sıralı kilitlenir, sonra auction/contract kilidi ve yeniden doğrulama gelir. Önceki kazanan kilit beklerken değiştiyse T0012 ile yeniden snapshot istenir; yeni mağazayı sıra dışı kilitlemez. Saat kontrolü store kilitlerinden sonra gerçek clock_timestamp. Tamamlanan transferlerin retry'si seviye/süre değişse de tekrar ücret almaz. RLS yalnızca kendi seri/makbuz kayıtları; diğer tablolar private safe RPC'dir.

Testler: node scripts/trading-check.js ve node scripts/marketplace-race-check.js. Seri custody/devir/retry, teklif minimumu/escrow/iade/net değer, doğru kazanan/son teslim süresi/komisyon/idempotency, sözleşme privacy/accept/reject/expiry, escrow ledger hata rollback, RLS/private RPC ve migration replay geçti. Gerçek bağımsız PostgreSQL bağlantılarıyla teklif değişimi kilit sonrası güvenli retry, geçilen teklif iadesi ve eşzamanlı aynı teslim isteğinde tek ödeme/stok devri geçti. Canlı doğrulama 012 uygulandıktan sonra yapılacak.

Phase 12 canlı doğrulama: 012 kullanıcı tarafından uygulandı. Açık artırma, Sözleşmeler, Koleksiyon ekranları yüklendi. Hesap seviye 4 olduğu için ticaret oluşturma kapalı, komisyon %5 ve escrow 0 görüldü. 9 Rare/Epic/Legendary koleksiyon hedefi görüntülendi. Canlı toptan pazardan 1 Rare Plant Pot 234,09 ₺ karşılığında alındı: nakit 4.539,80 → 4.305,71 ₺. Aynı birim ücretsiz seri numarasıyla Plant Pot #0001 oldu; envanter 1 adet, Ayrılmış 1 / Serbest 0, toplam depo 28/250 olarak korundu. Sözleşme ürün listesinden ayrılmış Plant Pot çıkarıldı, yalnızca serbest Gel Pen Set kaldı. Ürün test sonunda koleksiyonda bırakıldı. Canlı hesap seviyesi değiştirilmedi veya ikinci oyuncu hesabı açılmadı; escrow/iki oyunculu teklif/teslim/sözleşme kabul testleri yerel gerçek PostgreSQL bağlantılarında yapıldı. Yerel dolu depo teslim denemesi escrow'u kaybetmeden rollback oldu; NPC yalnızca fungible serbest adedi satabildi, seri numaralı birim korundu. Reload/mobil/konsol kontrolleri ve görsel aşağıda kaydedilir. Phase 13 Finance kullanıcı devamından sonra başlayacak.

Plant Pot #0001 reload sonrası aynı numarayla kaldı. 390px koleksiyon görünümünde yatay taşma yok, reload sonrası console error/warn yok. Görsel docs/phase12-collection.png. Phase 12 tamamlandı.
