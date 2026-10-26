// Numbers written the way the chart panel writes them (mql5/Include/ActionInna/Util.mqh): money
// with the account currency's decimals and thousands separators, prices with the symbol's digits,
// pips with one decimal.

// 12345.6 -> "12,345.60" (v >= 0).
export function group(v, digits) {
  const s = Math.abs(v).toFixed(Math.max(0, digits));
  const dot = s.indexOf('.');
  const ip = dot < 0 ? s : s.slice(0, dot);
  const fp = dot < 0 ? '' : s.slice(dot);
  return ip.replace(/\B(?=(\d{3})+(?!\d))/g, ',') + fp;
}

// "$1,234.50" for USD, "1,234.50 EUR" for others; withSign adds "+" to gains.
export function money(v, currency, digits = 2, withSign = false) {
  if (!Number.isFinite(v)) return '-';
  const num = group(v, digits);
  let sign = '';
  if (v < 0 && Math.abs(v) >= 0.5 * Math.pow(10, -digits)) sign = '-';
  else if (withSign && v > 0) sign = '+';
  return currency === 'USD' ? sign + '$' + num : sign + num + ' ' + currency;
}

export function trimZeros(s) {
  if (s.indexOf('.') < 0) return s;
  return s.replace(/0+$/, '').replace(/\.$/, '');
}

// Decimals needed to write a step: 0.01 -> 2, 0.25 -> 2, 1 -> 0.
export function stepDigits(step) {
  if (!(step > 0)) return 2;
  for (let d = 0; d <= 8; d++) {
    const scaled = step * Math.pow(10, d);
    if (Math.abs(scaled - Math.round(scaled)) < 1e-7) return d;
  }
  return 8;
}

export function price(v, digits) {
  return Number.isFinite(v) && v > 0 ? v.toFixed(Math.max(0, digits)) : '-';
}

export function pips(v) {
  return Number.isFinite(v) ? trimZeros(v.toFixed(1)) : '-';
}

export function lots(v, step) {
  return Number.isFinite(v) ? v.toFixed(stepDigits(step)) : '-';
}

// "1.25%"; withSign: "+1.25%", "-0.50%".
export function pct(v, withSign = false) {
  if (!Number.isFinite(v)) return '-';
  const s = Math.abs(v).toFixed(2) + '%';
  if (Math.abs(v) < 0.005) return '0.00%';
  return (v < 0 ? '-' : withSign ? '+' : '') + s;
}

// What the trader typed: "1,5", " 25 ", "2%", "$100". NaN for anything else.
export function parseNumber(text) {
  const s = String(text == null ? '' : text).replace(/[\s%$]/g, '').replace(',', '.');
  if (!/^-?(\d+\.?\d*|\.\d+)$/.test(s)) return NaN;
  const v = Number(s);
  return Number.isFinite(v) ? v : NaN;
}

// A stop loss, take profit or entry the trader typed: empty is none (0), anything else must be a
// positive number (NaN otherwise), so a typo never reaches MT5 as "no stop loss".
export function parseLevel(text) {
  if (String(text == null ? '' : text).trim() === '') return 0;
  const v = parseNumber(text);
  return v > 0 ? v : NaN;
}
