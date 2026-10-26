// The TradingView symbol a tab shows, read from its address and title only: the panel never looks
// inside TradingView's page. Any of TradingView's sites (www., id., in., ...).
//   https://www.tradingview.com/symbols/OANDA-XAUUSD/             -> "OANDA:XAUUSD"
//   a chart: https://www.tradingview.com/chart/abc/?symbol=OANDA%3AXAUUSD, titled
//   "XAUUSD 2,650.12 ▲ +0.45% Unnamed"                            -> "OANDA:XAUUSD"
// On a chart the title changes the moment another symbol is picked, and the address may follow
// later, so when the two differ the title wins. When they agree, the address adds the exchange.
// "" when the tab is not on TradingView, or the symbol can't be told.
export function tickerFromTab(url, title) {
  const u = tradingViewUrl(url);
  if (!u) return '';
  const sym = /^\/symbols\/([^/]+)/i.exec(u.pathname);
  if (sym) {
    let s;
    try {
      s = decodeURIComponent(sym[1]);
    } catch (e) {
      return '';   // "%ZZ": not a ticker
    }
    const dash = s.indexOf('-');
    return clean(dash > 0 ? s.slice(0, dash) + ':' + s.slice(dash + 1) : s);
  }
  if (!/^\/chart/i.test(u.pathname)) return '';
  const fromAddress = clean(u.searchParams.get('symbol') || '');
  const fromTitle = titleTicker(title);
  if (fromAddress && fromTitle && bare(fromAddress) !== bare(fromTitle)) return fromTitle;
  return fromAddress || fromTitle;
}

// An address on one of TradingView's sites. Chrome shows the panel a tab's address only on the
// sites it may read, so a tab whose address it can't see is not TradingView either.
export function isTradingView(url) {
  return tradingViewUrl(url) !== null;
}

function tradingViewUrl(url) {
  let u;
  try {
    u = new URL(url);
  } catch (e) {
    return null;
  }
  return u.protocol === 'https:' && /(^|\.)tradingview\.com$/i.test(u.hostname) ? u : null;
}

// "XAUUSD 2,650.12 ▲ +0.45% Unnamed" -> "XAUUSD"; a count of unread alerts in front, "(2) ", is skipped.
function titleTicker(title) {
  const m = /^\s*(?:\(\d+\)\s*)?([A-Za-z0-9._!:]+[A-Za-z0-9!])\s/.exec(title || '');
  return m ? clean(m[1]) : '';
}

// "OANDA:XAUUSD" -> "XAUUSD"
function bare(ticker) {
  return ticker.slice(ticker.lastIndexOf(':') + 1);
}

function clean(s) {
  const t = String(s).trim().toUpperCase();
  return /^[A-Z0-9._!:]{2,40}$/.test(t) ? t : '';
}
