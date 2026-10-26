// The TradingView symbol a tab shows, read from its address and title only: the panel never looks
// inside TradingView's page.
//   https://www.tradingview.com/chart/abc/?symbol=OANDA%3AXAUUSD   -> "OANDA:XAUUSD"
//   https://www.tradingview.com/symbols/OANDA-XAUUSD/             -> "OANDA:XAUUSD"
//   a chart whose address has no symbol: its title, "XAUUSD 2,650.12 ▲ +0.45% Unnamed" -> "XAUUSD"
// "" when the tab is not on TradingView, or the symbol can't be told.
export function tickerFromTab(url, title) {
  let u;
  try {
    u = new URL(url);
  } catch (e) {
    return '';
  }
  if (!/(^|\.)tradingview\.com$/i.test(u.hostname)) return '';
  const q = u.searchParams.get('symbol');
  if (q && clean(q)) return clean(q);
  const sym = /^\/symbols\/([^/]+)/i.exec(u.pathname);
  if (sym) {
    const s = decodeURIComponent(sym[1]);
    const dash = s.indexOf('-');
    return clean(dash > 0 ? s.slice(0, dash) + ':' + s.slice(dash + 1) : s);
  }
  if (!/^\/chart/i.test(u.pathname)) return '';
  const m = /^\s*([A-Za-z0-9._!:]+[A-Za-z0-9!])\s/.exec(title || '');
  return m ? clean(m[1]) : '';
}

function clean(s) {
  const t = String(s).trim().toUpperCase();
  return /^[A-Z0-9._!:]{2,40}$/.test(t) ? t : '';
}
