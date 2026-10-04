export const screens = [
 ['dashboard','Genel bakış','◈',3], ['wholesale','Toptan pazar','▦',4],
 ['inventory','Envanter','▣',5], ['marketplace','Marketplace','⇄',7],
 ['progression','İlerleme','☆',10], ['orders','Siparişler','≡',6], ['market','Piyasa','↗',8],
 ['analytics','Analitik','▥',3], ['company','Şirket','⌂',11],
 ['auction','Açık artırma','♧',12], ['contracts','Sözleşmeler','⇌',12], ['collection','Koleksiyon','◇',12], ['leaderboard','Liderlik tablosu','♜',18],
 ['profile','Profil','◎',1], ['settings','Ayarlar','⚙',1],
];
export function currentScreen() {
 return screens.find(screen => screen[0] === location.hash.slice(1)) || screens[0];
}
