# Supabase — Phase 2

SQL Editor içinde sırayla:
1. migrations/001_store_onboarding.sql
2. migrations/002_database_core.sql
3. seed.sql

Migration dosyaları canonical kaynaktır; schema.sql, functions.sql ve policies.sql referans parçalarıdır, ayrıca çalıştırmayın. Migration ve seed tekrar çalıştırılabilir; verileri veya değişmiş stok/fiyatları sıfırlamaz. 002, 001 olmadan çalışmaz. İki migration arasındaki geçişte onboarding isteklerini durdurun (bakım penceresi); 002 kendi içinde atomiktir.

public.store_onboarding uyumluluk için korunur. Yeni onboarding RPC aynı işlemde identity + profiles + stores + INITIAL_CAPITAL ledger kaydını oluşturur. Eski kimlikler 002 içinde aktarılır. Tarayıcı mağaza bilgisini artık stores tablosundan okur. Tüm finansal alanlar kuruş bigint; 10.000 ₺ = 1.000.000 kuruş. Weighted average cost envanter yaklaşımı seçildi; satın alma işlemi ve ağırlıklı maliyet güncellemesi Phase 4’te eklenecek.

RLS tüm core tablolarda aktif; authenticated yalnızca kendi özel kayıtlarını ve aktif ürünleri okuyabilir. İstemci yazma izni yoktur. Public profil/leaderboard API henüz yok. Yetkili mağaza oluşturma RPC kimliği auth.uid üzerinden alır, server defaults sermayeyi belirler. Ledger update/delete trigger ile reddedilir. Gelecekteki para hareketleri ledger ile aynı transaction içinde yazılmalıdır.

my_net_worth_kurus RPC sadece çağıranın mağazasını değerler, inactive ürünler dahil inventory market value + cash + business assets - debt hesaplar. numeric sum çarpma/toplama taşmasını önler. Koleksiyon gibi sonraki sistemler geldiğinde çift sayım yapılmadan genişletilecek.

50 seed ürünü / 8 kategori: Common 30, Uncommon 12, Rare 5, Epic 2, Legendary 1. Bu ürün dağılımıdır; gelecekteki drop olasılığı değildir. Seri numarası ve limited üretim Phase 12 kapsamındadır.

Yerel SQL testleri: node scripts/database-check.js. PGlite PostgreSQL motoru üzerinde Auth rollerini/uid fonksiyonunu taklit eder; canlı Supabase token davranışı veya iki ayrı DB oturumunda yarış testi değildir.

## Phase 3

Yeni kurulum sırası: 001, 002, seed.sql, 003_dashboard.sql. Mevcut Phase 2 kurulumunda sadece migrations/003_dashboard.sql çalıştırılır. Salt okunur dashboard RPC server zamanı ve auth.uid ile snapshot üretir. Ayrıntılı KPI tanımları ana README’de.

## Phase 4

Mevcut kurulumda sadece migrations/004_wholesale.sql çalıştırın. wholesale_receipts, read-only catalog RPC ve atomik buy_wholesale RPC eklenir. Eski tablolar silinmez/resetlenmez. Satın alma testleri scripts/database-check.js içinde yerel PostgreSQL’de çalışır; oyun satın alımı simulation parası kullanır.

## Phase 5

Mevcut kurulumda sadece migrations/005_inventory.sql dosyasını çalıştırın. Salt okunur my_inventory RPC, kendi mağazanızın miktar/maliyet/piyasa değeri ve potansiyel kâr snapshot’ını döndürür. Eski kayıtlar değişmez.

## Phase 6

Sadece migrations/006_npc_sales.sql çalıştırın. Ekonomik veriler sıfırlanmaz; store server tick zamanı, NPC listing tablosu ve ledger satış maliyeti eklenir. Online simulation; geçmiş offline süre biriktirilmez.

## Phase 7

Sadece migrations/007_marketplace.sql çalıştırın. Reservation column, listings/receipts, server fee config ve atomik RPC eklenir. NPC serbest stock ile uyumlu, dashboard fees ile uyumlu hale gelir. Kullanıcı verisi silinmez veya sıfırlanmaz. Yeni migration sonrasında eski 004–006 fonksiyon migrationlarını tek başına yeniden uygulamayın; yeni reservation semantiğini eski sürüme geri alır.

## Phase 8

Yalnızca migrations/008_economy.sql uygulanır. Yeni kurulumda seed.sql mutlaka 008'den önce uygulanır. Global clock, product reference ve price_history tabloları; mağaza doğrulayan server tick ve safe market snapshot RPC eklenir. Migration mevcut fiyatlarla ilk geçmiş kaydını oluşturur; referans/clock rerun ile resetlenmez. 5 dakika cooldown, adım başına %5 hareket, %50–%200 referans fiyat sınırı; online tek adım, offline catch-up yok. Ayrıntılı ekonomi formülü ve testler ana README'de.

## Phase 9

Yalnızca migrations/009_market_events.sql uygulanır. Ön koşul 008 ve seed; global schedule/event/offer/immutable receipt/drop-only mapping, güvenli snapshot ve atomic buy RPC eklenir. process_market_tick aktif olayları uygular ve drop-only ürünü restock etmez. Yeni Legendary Founder Limited Mouse yalnızca 25 adetlik süreli drop partilerinde alınır; normal catalog 50 üründür. Takvim ve tüketilmiş offer stock rerun ile resetlenmez. Eski 004/008 dosyalarını tek başına yeniden uygulamayın. Ekonomi/süreler/locking ve testler ana README'de.
Phase 10: `migrations/010_progression.sql` dosyasını 009 sonrası çalıştırın. XP, görev/başarım kayıtları, profil unvanları ve Marketplace seviye 5 kontrolünü ekler; mevcut ekonomik veriyi korur. Ayrıntılar ana README'deki Phase 10 bölümündedir. Eski Marketplace fonksiyon migrationlarını tek başına yeniden uygulamayın.


## Phase 11

Yalnızca migrations/011_business.sql dosyasını 010 sonrası çalıştırın. Depo/ofis/marka, reklam, peşin çalışan sözleşmeleri, idempotent şirket RPC ve şirket giderli dashboard ekler. Mevcut nakit ve stok korunur. Eski 006/007 fonksiyon migrationlarını tek başına yeniden uygulamayın. Ekonomi kuralları ana README Phase 11 bölümünde.

## Phase 12

Yalnızca migrations/012_advanced_trading.sql dosyasını 011 sonrası çalıştırın. Seri custody, açık artırma escrow, özel sözleşmeler, immutable makbuz ve escrow dahil net değer ekler. Eski 007/010 fonksiyon migrationlarını tek başına yeniden uygulamayın. Kural ve limitler ana README Phase 12 bölümündedir.
