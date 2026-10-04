# PROJE: MULTIPLAYER E-TİCARET TYCOON / MARKET SIMULATOR

Sen bu projede kıdemli bir full-stack oyun geliştiricisi, ekonomi sistemi tasarımcısı, UI/UX geliştiricisi ve Supabase mimarı olarak çalışacaksın.

Ben teknik kararların ayrıntılarıyla uğraşmak istemiyorum. Projeyi benimle birlikte **adım adım vibe coding yöntemiyle** geliştireceksin.

Bu dokümanın tamamını projenin ana bağlamı olarak kabul et.

---

# 1. TEMEL AMAÇ

Web üzerinden oynanan multiplayer bir e-ticaret simülasyon/tycoon oyunu geliştiriyoruz.

Oyuncular:

- hesap oluşturacak,
- kendi e-ticaret mağazalarını kuracak,
- başlangıç sermayesi alacak,
- sistem tedarikçilerinden ürün satın alacak,
- ürünlerini stoklayacak,
- fiyat belirleyecek,
- NPC müşterilere satış yapacak,
- diğer oyuncularla ticaret yapacak,
- Marketplace kullanacak,
- nadir ürünler toplayacak,
- mağazalarını büyütecek,
- çalışanlar işe alacak,
- reklam verecek,
- depolarını geliştirecek,
- piyasa hareketlerini takip edecek,
- ilerleyen aşamalarda kendi markalarını oluşturacak,
- üretim ve Ar-Ge yapacak,
- şirket/holding kurabilecek,
- global pazarlara açılacak,
- leaderboard üzerinde diğer oyuncularla rekabet edecek.

Temel oyun hissi:

**E-Commerce Simulator + Tycoon + Trading Game + MMO Economy**

olmalıdır.

---

# 2. TEKNOLOJİ SINIRLAMALARI

Frontend yalnızca:

- HTML5
- CSS3
- Vanilla JavaScript

kullanmalıdır.

React, Vue, Angular, Svelte veya başka frontend framework kullanma.

Backend:

- Supabase Authentication
- Supabase PostgreSQL
- Supabase Realtime
- Supabase Storage gerektiğinde
- PostgreSQL Functions / RPC
- gerektiğinde Supabase Edge Functions

üzerinden çalışmalıdır.

Proje mümkün olduğunca basit şekilde çalıştırılabilir olmalıdır.

Kod modüler tutulmalıdır.

Önerilen yapı:

```text
/
│
├── index.html
├── login.html
├── register.html
├── game.html
│
├── css/
│   ├── global.css
│   ├── auth.css
│   ├── dashboard.css
│   ├── marketplace.css
│   └── responsive.css
│
├── js/
│   ├── config.js
│   ├── supabase.js
│   ├── auth.js
│   ├── app.js
│   ├── router.js
│   ├── dashboard.js
│   ├── products.js
│   ├── inventory.js
│   ├── marketplace.js
│   ├── wholesale.js
│   ├── economy.js
│   ├── leaderboard.js
│   ├── notifications.js
│   └── utils.js
│
├── assets/
│   ├── icons/
│   └── products/
│
└── supabase/
    ├── schema.sql
    ├── seed.sql
    ├── functions.sql
    └── policies.sql
```

Bu yapı gerektiğinde değiştirilebilir fakat Vanilla JS prensibi korunmalıdır.

---

# 3. EN ÖNEMLİ GÜVENLİK KURALI

Oyuncunun:

- bakiyesi,
- envanteri,
- satışları,
- alışları,
- XP'si,
- seviyesi,
- net worth değeri,
- Marketplace işlemleri,
- nadir ürünleri,
- ödülleri

sadece frontend JavaScript tarafından değiştirilememelidir.

Şunun gibi güvensiz sistemlerden kaçın:

```javascript
player.balance += 100000;
```

Kritik ekonomik işlemler server-side doğrulanmalıdır.

Satın alma/satış işlemleri mümkün olduğunca PostgreSQL transaction + RPC/function üzerinden atomik gerçekleştirilmelidir.

Örneğin ürün satın alınırken tek işlem içerisinde:

1. kullanıcı doğrulanmalı,
2. stok kontrol edilmeli,
3. bakiye kontrol edilmeli,
4. para düşülmeli,
5. stok azaltılmalı,
6. oyuncu envanteri artırılmalı,
7. transaction kaydı oluşturulmalıdır.

İşlemlerden biri başarısız olursa tamamı rollback edilmelidir.

RLS bütün kullanıcı tablolarında düşünülmelidir.

Client hiçbir zaman başka kullanıcının özel verisini değiştirememelidir.

---

# 4. TEMEL OYUN DÖNGÜSÜ

Ana gameplay loop:

```text
SERMAYE
   ↓
ÜRÜN SATIN AL
   ↓
ENVANTER
   ↓
FİYAT BELİRLE
   ↓
SATIŞ YAP
   ↓
KÂR ELDE ET
   ↓
MAĞAZAYI GELİŞTİR
   ↓
DAHA BÜYÜK STOK
   ↓
DAHA BÜYÜK TİCARET
   ↓
PAZARDA GÜÇLEN
   ↓
LEADERBOARD
```

Oyuncunun sürekli şu soruları düşünmesini istiyoruz:

“Şimdi ne almalıyım?”

“Bu ürün yükselir mi?”

“Kaça satmalıyım?”

“Rakibim kaça satıyor?”

“Stok yapmalı mıyım?”

“Şimdi satmalı mıyım?”

---

# 5. YENİ OYUNCU

Oyuncu kayıt olduğunda mağaza oluşturma ekranı göster.

İstenecek bilgiler:

- kullanıcı adı
- mağaza adı

Başlangıç:

```text
Cash: 10.000 ₺
Level: 1
XP: 0
Reputation: 0
Warehouse Capacity: 50
Listing Limit: 5
Employees: 0
```

Mağaza adı benzersiz olmalıdır.

---

# 6. ANA DASHBOARD

Game dashboard modern bir e-ticaret yönetim paneline benzemelidir.

Üst bölüm:

```text
Cash
Net Worth
Today's Revenue
Today's Profit
Orders
Reputation
```

Grafikler:

- Revenue
- Profit
- Orders
- Net Worth

Ayrıca:

- son satışlar
- en çok satan ürünler
- düşük stok uyarıları
- piyasa haberleri
- trend kategoriler
- aktif Marketplace ilanları

göster.

UI bir admin paneli gibi değil, modern bir management/tycoon oyunu gibi hissettirmelidir.

Dark theme kullanılabilir.

---

# 7. ÜRÜN SİSTEMİ

Başlangıçta yaklaşık 50 ürün oluştur.

Kategoriler:

- Technology
- Gaming
- Clothing
- Cosmetics
- Sports
- Stationery
- Home
- Collectibles

Her ürün:

```text
id
name
category
subcategory
base_price
wholesale_price
market_price
rarity
quality
demand
supply
system_stock
image
active
created_at
```

gibi alanlara sahip olabilir.

---

# 8. NADİRLİK

Nadirlikler:

```text
Common
Uncommon
Rare
Epic
Legendary
```

Yaklaşık bulunabilirlik:

```text
Common       %60
Uncommon     %25
Rare         %10
Epic          %4
Legendary     %1
```

Legendary ürünler özellikle değerli olmalıdır.

Bazı Limited ürünlerde toplam üretim miktarı sınırlı olabilir.

Örneğin:

```text
Golden Console

Legendary

#004 / 100
```

---

# 9. WHOLESALE MARKET

Sistem tedarikçisi ekranı oluştur.

Oyuncu burada sistemden ürün satın alabilir.

Göster:

```text
Product
Category
Rarity
Wholesale Price
Estimated Market Price
Stock
Demand
Trend
Quantity
```

Oyuncu toplu satın alma yapabilsin.

Örneğin:

```text
Wireless Mouse

Wholesale:
850 ₺

Market:
1.100–1.350 ₺

Stock:
2.480

Demand:
HIGH
```

---

# 10. TEDARİKÇİLER

İlerleyen aşamada birden fazla tedarikçi ekle.

Örneğin:

### Budget Wholesale

Ucuz, yüksek stoklu ürünler.

### Premium Supply

Yüksek kaliteli ürünler.

### Tech Distributor

Teknoloji ürünleri.

### Fashion Wholesale

Giyim ürünleri.

### Mystery Supplier

Rastgele ürünler.

Oyuncuların supplier reputation değerleri olabilir.

---

# 11. ENVANTER

Inventory ekranında:

```text
Product
Quantity
Average Cost
Market Price
Inventory Value
Profit Potential
```

göster.

Örneğin:

```text
Wireless Mouse

Quantity: 25
Average Cost: 850 ₺
Market Price: 1.200 ₺
Inventory Value: 30.000 ₺
Potential Profit: +8.750 ₺
```

FIFO veya weighted average cost yöntemlerinden uygun olanını seç ve tutarlı uygula.

---

# 12. DEPO

Başlangıç kapasitesi:

```text
50
```

Upgrade örnekleri:

```text
Small Warehouse        250
Medium Warehouse     1.000
Large Warehouse      5.000
Distribution Center 25.000
```

Upgrade fiyatları giderek artmalıdır.

---

# 13. NPC SATIŞ SİSTEMİ

Oyuncunun satış yapabilmesi için gerçek oyuncuya bağımlı olmaması gerekir.

NPC müşteri sistemi oluştur.

Satış ihtimali şu faktörlerden etkilenebilir:

```text
Demand
Price Competitiveness
Store Reputation
Brand Value
Advertising
Product Popularity
Season/Event
```

Örneğin:

Piyasa fiyatı:

```text
1.200 ₺
```

Oyuncu:

```text
1.100 ₺
```

isterse hızlı satabilir.

```text
1.250 ₺
```

normal.

```text
1.500 ₺
```

yavaş.

```text
3.000 ₺
```

neredeyse satılmaz.

---

# 14. NPC MÜŞTERİ TİPLERİ

İlerleyen sürümlerde:

```text
Bargain Hunter
Brand Lover
Collector
Impulse Buyer
Tech Enthusiast
Luxury Buyer
```

ekle.

Farklı müşteri tiplerinin farklı satın alma davranışları olmalıdır.

---

# 15. PLAYER MARKETPLACE

Oyuncular kendi ürünlerini diğer oyunculara satabilsin.

Marketplace:

```text
Product
Seller
Quantity
Price
Market Average
Difference
Rarity
```

Örneğin:

```text
Wireless Mouse

O20 Store      1.190 ₺
MegaTech       1.220 ₺
GameWorld      1.280 ₺
```

Marketplace satın alımı atomik olmalıdır.

Aynı ürünü iki oyuncunun aynı anda satın alması duplication bug oluşturmamalıdır.

---

# 16. MARKETPLACE KOMİSYONU

Marketplace satışlarından örneğin:

```text
%5
```

komisyon kes.

Örneğin:

```text
Sale:       10.000 ₺
Fee:           500 ₺
Seller Gets: 9.500 ₺
```

Bu oran config üzerinden kolay değiştirilebilir olmalıdır.

---

# 17. PLAYER-TO-PLAYER CONTRACTS

İlerleyen aşamada doğrudan B2B ticaret ekle.

Örneğin:

```text
O20 Store
→
MegaTech

Wireless Mouse
500 units
780 ₺ / unit

TOTAL
390.000 ₺
```

Karşı taraf kabul veya reddedebilsin.

---

# 18. MARKET ECONOMY

Her ürün için:

```text
Supply
Demand
Market Price
```

hesaplanmalıdır.

Basit mantık:

```text
Market Price =
Base Price
× Demand Modifier
× Supply Modifier
× Event Modifier
```

Ancak ani ve anlamsız fiyat değişimlerinden kaçın.

Minimum/maximum hareket limitleri belirle.

---

# 19. PRICE HISTORY

Ürünlerin fiyat geçmişini sakla.

Örneğin:

```text
1H
24H
7D
30D
```

grafikleri oluşturulabilsin.

Ürün detay ekranında fiyat grafiği göster.

---

# 20. MARKET TREND

Ana sayfada:

```text
Technology +12%
Gaming +28%
Fashion -8%
Sports +4%
Cosmetics -14%
```

gibi piyasa hareketleri göster.

---

# 21. MARKET EVENTS

Global olay sistemi oluştur.

Örneğin:

```text
GLOBAL CHIP SHORTAGE

Technology supply -35%
Technology prices +20%
```

ve:

```text
GAMING FESTIVAL

Gaming demand +45%
```

Eventler:

- başlangıç zamanı
- bitiş zamanı
- etkilenen kategori
- supply modifier
- demand modifier

içermelidir.

---

# 22. MARKET NEWS

Eventler kullanıcıya haber şeklinde gösterilsin.

Örneğin:

```text
MARKET NEWS

Chip shortage hits technology sector.

Technology products are expected to become more expensive.
```

---

# 23. MARKET RUMORS

İlerleyen sürümlerde söylenti sistemi oluştur.

Örneğin:

```text
RUMOR

Gaming demand may increase soon.
```

Her söylenti doğru olmak zorunda değildir.

Oyuncunun spekülasyon yapabilmesini sağla.

---

# 24. FLASH DEALS

Sistem belirli zamanlarda kısa süreli toptan fırsatları oluşturabilir.

Örneğin:

```text
FLASH DEAL

Mechanical Keyboard

Normal:
1.200 ₺

Deal:
720 ₺

Remaining:
450

Ends:
12:42
```

---

# 25. LIMITED DROPS

Nadir ürünler belirli zamanlarda sisteme girebilir.

Örneğin:

```text
LIMITED DROP

Retro Console

Legendary

50 Units

Starts:
21:00
```

Bu ürünler daha sonra oyuncular arasında satılabilir.

---

# 26. AUCTION HOUSE

Rare/Epic/Legendary ürünler için açık artırma sistemi oluştur.

Örneğin:

```text
Golden Console #004

Current Bid:
482.000 ₺

Bids:
37

Remaining:
04:32
```

Teklifler server-side doğrulanmalıdır.

---

# 27. MAĞAZA İTİBARI

Her mağazanın:

```text
0–100
```

Reputation değeri olsun.

Etkileyen faktörler:

- başarılı sipariş
- fiyat
- teslimat
- müşteri memnuniyeti
- iptaller

Reputation NPC satışlarını etkileyebilir.

---

# 28. BRAND VALUE

Reputation'dan ayrı bir:

```text
Brand Value
```

sistemi oluştur.

Marka değeri yüksek mağazalar biraz daha pahalı satış yapabilsin.

---

# 29. REKLAM

Reklam kampanyaları:

```text
Social Media Ads
Search Ads
Influencer Campaign
Brand Campaign
```

Reklam:

- ziyaretçi
- conversion
- brand awareness

değerlerini etkileyebilir.

---

# 30. ANALYTICS

Dashboard üzerinde gerçek e-ticaret KPI'ları göster.

```text
Revenue
Profit
Orders
Visitors
Conversion Rate
Average Order Value
Inventory Value
Net Worth
```

---

# 31. NET WORTH

Leaderboard sadece cash kullanmamalıdır.

Örneğin:

```text
Net Worth =
Cash
+ Inventory Estimated Value
+ Collectibles Value
+ Business Assets
- Debt
```

Manipülasyona açık olmaması için server-side hesaplanmalıdır.

---

# 32. LEADERBOARD

Leaderboard kategorileri:

```text
Richest
Highest Revenue
Highest Profit
Most Orders
Best Reputation
Largest Collection
Technology Leader
Fashion Leader
Fastest Growing
```

Filtreler:

```text
Daily
Weekly
Monthly
Season
All Time
```

---

# 33. PLAYER PROFILE

Public profil:

```text
O20 Store

Owner: Emircan

Level 27
Reputation 94
Net Worth 4.82M ₺
Sales 12.842
Global Rank #37
```

Sekmeler:

```text
Store
Products
Achievements
Collection
Statistics
```

Private bilgiler public API'de gösterilmemelidir.

---

# 34. LEVEL / XP

Oyuncu:

- satış
- achievement
- görev
- şirket geliştirmesi

yaparak XP kazanabilir.

Level arttıkça özellikler açılır.

Örneğin:

```text
Level 1
Basic Trading

Level 5
Marketplace

Level 10
Advertising

Level 15
Employees

Level 20
Advanced Analytics

Level 25
Global Markets

Level 30
Private Label

Level 40
Manufacturing

Level 50
Corporations
```

---

# 35. ACHIEVEMENTS

Örnekler:

```text
First Sale
First 100 Orders
Entrepreneur
Millionaire
Billionaire
Collector
Market Shark
Wholesaler
Tech Mogul
Empire
```

---

# 36. DAILY / WEEKLY MISSIONS

Örneğin:

```text
Sell 25 products
Buy 10 wholesale products
Generate 50.000 ₺ revenue
Complete 5 Marketplace trades
```

Ödül:

```text
Cash
XP
Cosmetic rewards
```

---

# 37. ÇALIŞANLAR

İlerleyen aşamada:

```text
Sales Specialist
Purchasing Specialist
Warehouse Worker
Marketing Specialist
Market Analyst
Logistics Specialist
```

ekle.

Her çalışanın:

```text
level
salary
skill
bonus
```

değeri olabilir.

---

# 38. OFİS / HQ

Şirket binaları:

```text
Garage Office
Small Office
Business Center
Corporate HQ
Mega Campus
```

Bonus sağlayabilir.

---

# 39. BANKA / KREDİ

İleri aşamada:

```text
Credit Score
Loan
Interest
Payment
Debt
```

sistemi oluştur.

Borç Net Worth hesabından düşmelidir.

---

# 40. İFLAS

Oyuncunun cash değeri düşse bile hesabını silme.

Borçlarını ödeyemeyen oyuncular için:

```text
Restructuring
Asset Liquidation
Debt Payment Plan
```

gibi kurtarma mekanikleri oluştur.

---

# 41. PRIVATE LABEL

İleri seviyede oyuncular kendi markalarını oluşturabilsin.

Örneğin:

```text
Brand:
O20

Product:
Wireless Headphones

Model:
O20 Air
```

Oyuncu:

- kalite
- üretim miktarı
- fiyat
- pazarlama

kararlarını verebilsin.

---

# 42. R&D

Yeni ürün geliştirme sistemi:

```text
Design
Performance
Durability
Battery
Features
```

Oyuncu Ar-Ge bütçesini dağıtabilsin.

---

# 43. MANUFACTURING

İleri aşamada factory sistemi oluştur.

Örneğin elektronik ürün:

```text
Chip
Battery
Plastic
Display
```

gibi hammaddeler gerektirebilir.

Ekonomide oyuncular:

```text
Manufacturer
Wholesaler
Retailer
Trader
Collector
```

rollerinden birine veya birkaçına dönüşebilmelidir.

---

# 44. GLOBAL MARKETS

İlerleyen aşamada:

```text
Türkiye
Europe
North America
Asia
```

pazarlarını aç.

Her bölgenin:

```text
Demand
Taxes
Shipping
Category Bonuses
```

değerleri farklı olabilir.

---

# 45. CORPORATIONS

Endgame'de oyuncular ortak şirket kurabilsin.

Örneğin:

```text
O20 GROUP

CEO
CFO
COO
Trader
Logistics Manager
```

Ortak:

```text
Treasury
Assets
Statistics
```

bulunabilir.

Yetki sistemi mutlaka server-side doğrulanmalıdır.

---

# 46. COLLECTION

Oyuncular Limited/Rare ürünlerini koleksiyonda sergileyebilsin.

Örneğin:

```text
2026 Collection

Golden Console     ✓
RetroPhone         ✓
Founder Laptop     ✕
Anniversary Watch  ✕
```

---

# 47. TITLES

Oyuncular achievement'lardan ünvan kazanabilsin.

Örneğin:

```text
Founder
Millionaire
Collector
Market Shark
Tech Mogul
Billionaire
Market King
```

Bir ünvan profilde aktif edilebilsin.

---

# 48. SEASONS

Sistem gelecekte sezon desteklemelidir.

Örneğin:

```text
Season 1
The Beginning

Season 2
Global Expansion

Season 3
Industrial Revolution
```

Season leaderboard ayrı tutulabilir.

Ana oyuncu hesabı sıfırlanmamalıdır.

---

# 49. OFFLINE PROGRESS

Oyuncu oyunda değilken de uygun simülasyonlar devam edebilir.

Geri geldiğinde:

```text
WHILE YOU WERE AWAY

142 products sold

Revenue:
184.200 ₺

Profit:
42.800 ₺

Reputation:
+4
```

göster.

Offline progress hesaplaması client saatine güvenmemelidir.

---

# 50. NOTIFICATION CENTER

Bildirimler:

```text
Product sold
Marketplace sale
Shipment arrived
Low stock
Price movement
Achievement
Leaderboard
Limited Drop
Market Event
Mission
```

için kullanılmalıdır.

---

# 51. EKONOMİK MONEY SINK

Oyunda sürekli para üretildiği için para sistemden çıkarılmalıdır.

Money sink kaynakları:

```text
Marketplace fees
Advertising
Employee salaries
Warehouse upgrades
Office upgrades
Shipping
Taxes
R&D
Manufacturing
Auction fees
Loan interest
```

Ekonominin hiper-enflasyona girmesini engelle.

---

# 52. ANTI-CHEAT

Asla client değerlerine güvenme.

Kontrol edilmesi gerekenler:

```text
Balance
Inventory
Price
Quantity
Ownership
Level
XP
Rewards
Marketplace Listing
Auction Bid
Company Permission
```

Rate limiting düşün.

Tekrarlanan request'lerde duplication engelle.

RPC işlemlerinde idempotency yaklaşımı kullan.

---

# 53. UI / UX

Tasarım modern olmalıdır.

Referans hissi:

```text
Shopify Dashboard
Steam Market
Stock Trading Dashboard
Tycoon Game
Modern SaaS
```

Ancak hiçbirini birebir kopyalama.

Sol sidebar:

```text
Dashboard
Wholesale
Inventory
Marketplace
Orders
Market
Analytics
Company
Collection
Leaderboard
Profile
```

Alt bölüm:

```text
Settings
Logout
```

Mobil tasarım responsive olmalıdır.

---

# 54. PARA FORMATLAMA

Türk Lirası:

```text
1.250 ₺
24.800 ₺
1,2M ₺
4,8B ₺
```

şeklinde kullanıcı dostu gösterilebilir.

Veritabanında finansal değerler floating-point ile tutulmamalıdır.

Kuruş bazında integer/bigint veya uygun PostgreSQL numeric tipi kullan.

---

# 55. ERROR HANDLING

Her kritik işlemde:

- loading state
- success state
- error state

bulunmalıdır.

Örneğin:

```text
Insufficient balance.

Warehouse capacity exceeded.

Product is out of stock.

Listing no longer available.

Price changed.

Transaction failed.
```

---

# 56. AUDIT LOG

Ekonomi için transaction ledger oluştur.

Her para hareketi kayıt altına alınmalıdır.

Örneğin:

```text
WHOLESALE_PURCHASE
MARKETPLACE_PURCHASE
MARKETPLACE_SALE
NPC_SALE
MARKETPLACE_FEE
WAREHOUSE_UPGRADE
ADVERTISEMENT
SALARY
LOAN
LOAN_PAYMENT
REWARD
```

Her kaydın:

```text
user_id
type
amount
reference_id
created_at
```

bilgileri bulunmalıdır.

Mümkünse immutable ledger mantığı kullan.

---

# 57. GELİŞTİRME STRATEJİSİ

PROJEYİ TEK SEFERDE YAPMAYA ÇALIŞMA.

Aşağıdaki fazlara böl.

---

## PHASE 0 — PROJECT FOUNDATION

Yap:

- klasör yapısı
- HTML shell
- CSS design system
- Supabase bağlantısı
- config sistemi
- reusable JS utilities

Henüz gameplay geliştirme.

Bitince dur.

---

## PHASE 1 — AUTHENTICATION

Yap:

- register
- login
- logout
- session
- protected game page
- mağaza oluşturma onboarding'i

Supabase Auth kullan.

Bitince test et ve dur.

---

## PHASE 2 — DATABASE CORE

Oluştur:

```text
profiles
stores
products
inventory
transactions
```

RLS politikalarını oluştur.

Seed ürünlerini oluştur.

Bitince SQL'i kontrol et ve dur.

---

## PHASE 3 — DASHBOARD

Dashboard oluştur.

Göster:

```text
Cash
Net Worth
Revenue
Profit
Orders
Inventory
```

Henüz sahte veri gerekiyorsa açıkça belirt.

Bitince dur.

---

## PHASE 4 — WHOLESALE

Wholesale market oluştur.

Server-side satın alma RPC oluştur.

Kontrol:

```text
balance
stock
warehouse
quantity
```

Başarılı satın almada:

```text
cash ↓
supplier stock ↓
inventory ↑
transaction ↑
```

Bitince test et ve dur.

---

## PHASE 5 — INVENTORY

Inventory sistemi oluştur.

Göster:

```text
Quantity
Average Cost
Market Price
Value
Potential Profit
```

Bitince dur.

---

## PHASE 6 — NPC SALES

NPC satış motorunu oluştur.

Demand + price + reputation bazlı satış sistemi geliştir.

Server timestamp kullan.

Bitince test et ve dur.

---

## PHASE 7 — MARKETPLACE

Oyuncular:

```text
list
buy
cancel
```

işlemleri yapabilsin.

Atomic transaction zorunlu.

Race condition test et.

Bitince dur.

---

## PHASE 8 — ECONOMY ENGINE

Ek:

```text
Supply
Demand
Market Price
Price History
Category Trends
```

Fiyat hareketlerine limit koy.

Bitince dur.

---

## PHASE 9 — MARKET EVENTS

Ek:

```text
Market Events
News
Flash Deals
Limited Drops
```

Bitince dur.

---

## PHASE 10 — PROGRESSION

Ek:

```text
XP
Levels
Achievements
Missions
Titles
```

Bitince dur.

---

## PHASE 11 — BUSINESS MANAGEMENT

Ek:

```text
Warehouse Upgrades
Advertising
Employees
Offices
Brand Value
```

Bitince dur.

---

## PHASE 12 — ADVANCED TRADING

Ek:

```text
Auction House
Player Contracts
Collections
Serialised Items
```

Bitince dur.

---

## PHASE 13 — FINANCE

Ek:

```text
Bank
Credit Score
Loans
Debt
Bankruptcy
```

Bitince dur.

---

## PHASE 14 — PRIVATE LABEL

Ek:

```text
Brands
Custom Products
R&D
```

Bitince dur.

---

## PHASE 15 — MANUFACTURING

Ek:

```text
Factories
Materials
Production
Manufacturing Costs
```

Bitince dur.

---

## PHASE 16 — GLOBAL EXPANSION

Ek:

```text
Regions
Shipping
Regional Demand
Taxes
```

Bitince dur.

---

## PHASE 17 — CORPORATIONS

Ek:

```text
Companies
Members
Roles
Permissions
Treasury
Corporate Assets
```

Bitince dur.

---

## PHASE 18 — LEADERBOARD / SEASONS

Ek:

```text
Global Leaderboard
Category Rankings
Season Rankings
Season Rewards
```

Bitince dur.

---

## PHASE 19 — OFFLINE SYSTEM

Ek:

```text
Offline Sales
Shipment Completion
Employee Costs
Event Effects
```

Client clock kullanma.

Bitince dur.

---

## PHASE 20 — POLISH

Yap:

- responsive design
- loading skeleton
- toast system
- modal system
- animations
- empty states
- confirmation dialogs
- accessibility
- keyboard navigation
- mobile UX

---

## PHASE 21 — SECURITY AUDIT

Kontrol et:

- RLS
- RPC authorization
- race conditions
- negative quantities
- integer overflow
- price manipulation
- duplicate purchases
- fake rewards
- IDOR
- unauthorized company actions
- auction manipulation
- balance manipulation

Bulduğun açıkları düzelt.

---

## PHASE 22 — ECONOMY BALANCING

Simüle et:

```text
New Player
Casual Player
Trader
Whale
Collector
Late Game Player
```

Ekonomide:

```text
inflation
money supply
profit margins
rare item scarcity
NPC cash generation
money sinks
```

analizi yap.

Gerekirse parametreleri düzenle.

---

# 58. ÇALIŞMA PROTOKOLÜ

Bu bölüm çok önemlidir.

Her fazda SADECE o faz üzerinde çalış.

Bir sonraki faza otomatik geçme.

Her faz başında:

1. mevcut repository'yi incele,
2. mevcut yapıyı bozmayacak plan oluştur,
3. hangi dosyaları değiştireceğini belirle,
4. implementasyonu yap,
5. hataları kontrol et,
6. ilgili güvenlik kontrollerini yap,
7. yapılanları özetle.

Sonra DUR.

Benden:

**“devam”**

komutunu bekle.

Ben “devam” dediğimde sıradaki faza geç.

---

# 59. MEVCUT KODU KORUMA

Her yeni fazda:

- çalışan sistemi gereksiz yere yeniden yazma,
- mevcut CSS'i bozma,
- mevcut database tablolarını gereksiz silme,
- migration mantığı kullan,
- önceki özelliklerin çalışmasını koru.

Breaking change gerekiyorsa önce açıkça belirt.

---

# 60. BUG FIX PROTOKOLÜ

Ben hata mesajı gönderirsem:

Önce hatanın kaynağını bul.

Doğrudan büyük çaplı rewrite yapma.

Şu sırayı izle:

```text
Reproduce
↓
Identify root cause
↓
Minimal fix
↓
Regression check
↓
Explain result
```

---

# 61. PLACEHOLDER KURALI

Gerçek özellik yerine sessizce fake sistem koyma.

Bir özellik henüz geliştirilmediyse:

```text
Coming in Phase X
```

olarak belirt.

Dashboard'da mock data kullanıyorsan kod içinde ve açıklamada belirt.

---

# 62. DATABASE MIGRATION KURALI

Database değişikliklerinde mümkünse migration-safe SQL üret.

Örneğin doğrudan veri kaybettirecek:

```sql
DROP TABLE
```

işlemlerinden kaçın.

Mevcut kullanıcı verisini koru.

---

# 63. TEST SENARYOLARI

Her önemli ekonomi özelliği için en az:

```text
Happy Path
Insufficient Funds
Insufficient Stock
Invalid Quantity
Unauthorized User
Concurrent Purchase
Duplicate Request
```

senaryolarını düşün.

---

# 64. OYUN FELSEFESİ

Oyunun temel prensibi:

**Tek bir doğru oynama yöntemi olmamalıdır.**

Oyuncu:

```text
Retailer
Trader
Wholesaler
Collector
Manufacturer
Corporation Owner
```

olabilmelidir.

Ve bu roller birbirlerine ekonomik olarak ihtiyaç duymalıdır.

---

# 65. SON HEDEF

Oyunun başlangıcında oyuncu:

> “10 tane mouse alıp satsam ne kadar kazanırım?”

diye düşünmeli.

Orta oyunda:

> “Gaming talebi artıyor. 500 klavye stoklayacağım.”

diye düşünmeli.

İleri oyunda:

> “Rakip Rare Console stoklarını topluyor. Fiyat artmadan ben de almalıyım.”

demeli.

Endgame'de:

> “O20 Air 4 için 20 milyon ₺ Ar-Ge yatırımı yapıp Avrupa'da 100.000 adet üretim yapacağım.”

seviyesine ulaşmalıdır.

---

# 66. İLK GÖREVİN

Şimdi yalnızca **PHASE 0 — PROJECT FOUNDATION** üzerinde çalış.

Önce repository'nin mevcut durumunu incele.

Ardından gerekli temel klasör/dosya mimarisini oluştur.

Modern responsive tasarım sisteminin temelini hazırla.

Supabase entegrasyonunun temel yapısını hazırla fakat henüz authentication veya gameplay sistemlerini geliştirme.

README içerisine:

- proje yapısını,
- nasıl çalıştırılacağını,
- Supabase environment/config kurulumunu,
- mevcut fazı

belgele.

Projeyi çalıştır ve temel sayfanın hata vermediğini doğrula.

Bittiğinde:

1. oluşturduğun/değiştirdiğin dosyaları listele,
2. yaptığın işleri kısaca açıkla,
3. test sonucunu yaz,
4. bilinen eksikleri belirt,
5. sıradaki fazın `PHASE 1 — AUTHENTICATION` olduğunu belirt.

Sonra DUR ve benden **“devam”** komutunu bekle.