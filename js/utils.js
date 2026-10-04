export const money = value => new Intl.NumberFormat('tr-TR', { style: 'currency', currency: 'TRY', maximumFractionDigits: 2 }).format(value);
export function moneyFromKurus(value) {
  const amount = BigInt(value);
  const negative = amount < 0n;
  const absolute = negative ? -amount : amount;
  return (negative ? '-' : '') + new Intl.NumberFormat('tr-TR').format(absolute / 100n) + ',' + String(absolute % 100n).padStart(2, '0') + ' ₺';
}
export function setStatus(element, message, state = 'neutral') {
  element.textContent = message;
  element.dataset.state = state;
}

export function parseMoneyKurus(value){const raw=value.trim().replace(',','.');if(!/^[0-9]{1,11}([.][0-9]{1,2})?$/.test(raw))throw new Error('Invalid price');const [whole,part='']=raw.split('.');const amount=BigInt(whole)*100n+BigInt(part.padEnd(2,'0'));if(amount<1n||amount>1000000000000n)throw new Error('Invalid price');return amount.toString();}
