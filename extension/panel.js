// The ActionInna side panel. Every number and every rule comes from the ActionInna EA in MT5,
// through the link (docs/protocol.md): this page shows them, sends what the trader typed, and
// confirms only previews MT5 made. Outside Chrome (a plain page, for development) there is no link,
// and dev/mock.js stands in for it.
import { Link, explainLinkError } from './lib/link.js';
import * as fmt from './lib/format.js';
import { tickerFromTab, isTradingView } from './lib/tv.js';
import { wantedLines, parseLineKey } from './lib/lines.js';

const HOST = 'com.actioninna.link';
const TV_ORIGINS = ['https://*.tradingview.com/*'];   // www and the country sites (id., in., uk., ...)
const ARM_MS = 300;        // Confirm waits this long after the order changed, against a click on moving numbers
const ALIVE_MS = 3000;     // MT5 heard within this long (it writes at least once a second)
const LEAVE_MS = 1500;     // the panel closes this long after TradingView left the front of its window
const $ = (id) => document.getElementById(id);

const inExtension = typeof chrome !== 'undefined' && !!(chrome.runtime && chrome.runtime.connectNative);
let openPort;
let browser;   // the browser's tabs, windows and permissions: Chrome's, or the mock's stand-ins
if (inExtension) {
  openPort = () => chrome.runtime.connectNative(HOST);
  browser = chrome;
} else {
  const mock = await import('./dev/mock.js');
  openPort = () => mock.connect();
  browser = mock.browser;
}
const link = new Link(openPort, () => (inExtension && chrome.runtime.lastError ? chrome.runtime.lastError.message : ''));

//--- preferences: the trader's choices, kept in the browser ----------------------
const prefs = {
  chip: 0,
  customUnit: 'percent',
  custom: { percent: '', money: '', lots: '' },
  slMode: 'pips',
  slValue: '',
  tpMode: 'r',
  tpValue: '',
  autoRecall: true,
  riskBase: '',      // 'equity' or 'balance' when the trader chose one
  riskBaseInput: '', // the EA's input when they did
  symbols: {},   // account -> symbol last used
};

async function loadPrefs() {
  try {
    if (inExtension && chrome.storage) {
      const r = await chrome.storage.local.get('prefs');
      Object.assign(prefs, r.prefs || {});
    } else {
      Object.assign(prefs, JSON.parse(localStorage.getItem('actioninna.prefs') || '{}'));
    }
  } catch (e) {
    // defaults
  }
}

function savePrefs() {
  try {
    if (inExtension && chrome.storage) chrome.storage.local.set({ prefs });
    else localStorage.setItem('actioninna.prefs', JSON.stringify(prefs));
  } catch (e) {
    // a choice that can't be kept is no reason to stop
  }
}

//--- state ------------------------------------------------------------------------
const S = {
  terms: new Map(),     // term -> { info: terminal message, trades: trades message }
  heard: new Map(),     // term -> when a message came last
  term: '',
  linkText: 'Starting the link…',
  linkState: '',
  symbol: '',
  levelsFor: '',         // the symbol the SL/TP and entry fields were filled for
  spec: null,
  quote: null,
  ticker: '',
  candidates: [],
  candVersion: 0,
  tickerSeq: 0,
  windowId: null,        // the browser window this panel is in
  tvAccess: false,       // the trader allowed access to TradingView's tabs
  tvShown: '',           // the ticker of the TradingView chart in front; '' when none is
  tvMissing: '',         // that ticker, when this broker has no symbol for it
  followed: '',          // the TradingView ticker followed last
  chartTabId: null,      // the TradingView tab it came from, where the panel draws its lines
  side: 0,
  pending: false,
  entry: '',
  entrySet: false,       // the trader typed the entry
  plan: null,
  planErr: '',
  previewId: '',
  previewSeq: 0,
  previewAt: 0,
  planAt: 0,
  inputs: 0,             // counts the trader's changes to the order (typed, chosen, or dragged on the chart)
  planInputs: -1,        // the count the plan on screen was made for
  sending: false,
  recallSl: 0,
  recallTp: 0,
  status: { text: '', level: 0, until: 0 },
  card: null,
};

function term() {
  return S.terms.get(S.term) || null;
}

function info() {
  const t = term();
  return (t && t.info) || null;
}

function settings() {
  const i = info();
  return (i && i.settings) || null;
}

function currency() {
  const i = info();
  return (i && i.currency) || 'USD';
}

function money(v, withSign) {
  const i = info();
  return fmt.money(v, currency(), i && Number.isInteger(i.currencyDigits) ? i.currencyDigits : 2, withSign);
}

function alive(id) {
  return Date.now() - (S.heard.get(id) || 0) < ALIVE_MS;
}

function accountKey() {
  const i = info();
  return i ? i.login + '@' + i.server : '';
}

function setStatus(text, level, ms) {
  S.status = { text, level, until: ms ? Date.now() + ms : Infinity };
}

//--- messages from the link and MT5 ---------------------------------------------
link.on('*', (m) => {
  if (m.term) S.heard.set(m.term, Date.now());
});

link.on('link-open', () => {
  S.linkText = 'Starting the link…';
  render();
});

link.on('link-stopped', (m) => {
  S.terms.clear();
  S.term = '';
  S.linkText = explainLinkError(m.error);
  // An order on its way is confirm()'s to report: it may have gone through.
  if (S.side && !S.sending) closePreview('The link stopped. Nothing was sent', 2);
  S.card = null;
  render();
});

link.on('link', (m) => {
  S.linkState = m.state;
  if (m.state === 'listening') S.linkText = 'Waiting for MT5…';
  else if (m.state === 'terminal-gone') {
    S.terms.delete(m.term);
    // Its answers can't come any more: the link has no terminal to take them from.
    link.abandon(m.term, 'MT5 stopped serving the panel before it answered');
    if (m.term === S.term) {
      if (S.side && !S.sending) closePreview('MT5 stopped serving the panel. Nothing was sent', 2);
      S.card = null;
      S.term = '';
      const next = S.terms.keys().next();
      if (!next.done) chooseTerm(next.value);
    }
    if (S.terms.size === 0) S.linkText = 'Waiting for MT5…';
  } else if (m.state !== 'terminal-connected') S.linkText = m.text || m.state;
  render();
});

link.on('terminal', (m) => {
  const t = S.terms.get(m.term) || {};
  t.info = m;
  S.terms.set(m.term, t);
  if (!S.term) chooseTerm(m.term);
  render();
});

link.on('trades', (m) => {
  const t = S.terms.get(m.term) || {};
  t.trades = m;
  S.terms.set(m.term, t);
  if (m.term === S.term) syncCard();
  render();
});

link.on('quote', (m) => {
  if (m.term !== S.term || m.symbol !== S.symbol) return;
  S.quote = m;
  if (S.side && !S.sending && Date.now() - S.previewAt > 700) schedulePreview(0);
  render();
});

// A new terminal starts on TradingView's chart, or else on the symbol last used with its account.
function chooseTerm(id) {
  S.term = id;
  S.symbol = '';
  S.spec = null;
  S.quote = null;
  followTab(null, true).then((followed) => {
    const remembered = prefs.symbols[accountKey()];
    if (!followed && remembered && S.term === id && !S.symbol) setSymbol(remembered);
  });
}

//--- the symbol: always the one on TradingView ------------------------------------
// TradingView's ticker to this broker's symbol. Returns the symbol, or '' when the broker has
// none, or the trader has to choose between several.
async function resolveTicker(ticker) {
  if (!term() || !ticker) return '';
  const seq = ++S.tickerSeq;
  const r = await link.request('symbols', { ticker }, S.term);
  if (seq !== S.tickerSeq) return '';
  if (!r.ok) {
    setStatus(r.err, 2, 6000);
    render();
    return '';
  }
  S.ticker = r.ticker;
  S.candidates = r.pick ? [] : r.candidates || [];
  S.candVersion++;
  S.tvMissing = !r.pick && !S.candidates.length ? r.ticker : '';
  if (r.pick) await setSymbol(r.pick);
  render();
  return r.pick || '';
}

async function chooseCandidate(name) {
  await link.request('pick', { ticker: S.ticker, symbol: name }, S.term);
  S.candidates = [];
  S.candVersion++;
  await setSymbol(name);
}

async function setSymbol(sym) {
  if (!sym || (sym === S.symbol && S.spec)) return;
  if (S.side) closePreview('The symbol changed to ' + sym + ': the preview was closed. Nothing was sent', 1);
  S.symbol = sym;
  S.spec = null;
  S.quote = null;
  render();
  const r = await link.request('watch', { symbol: sym }, S.term);
  if (S.symbol !== sym) return;
  if (!r.ok) {
    setStatus(r.err, 2, 6000);
    S.symbol = '';
    render();
    return;
  }
  S.spec = r.spec;
  if (S.levelsFor && S.levelsFor !== sym) {
    // Prices typed for another symbol mean nothing here; distances still do.
    if (prefs.slMode === 'price') prefs.slValue = '';
    if (prefs.tpMode === 'price') prefs.tpValue = '';
    S.entry = '';
    S.entrySet = false;
  }
  S.levelsFor = sym;
  const acc = accountKey();
  if (acc) prefs.symbols[acc] = sym;
  savePrefs();
  render();
}

//--- following TradingView ------------------------------------------------------
// The panel takes its symbol from the TradingView chart in front of its own window, always. That
// needs access to TradingView's tabs, which the trader allows once with one click: Chrome asks
// only on the trader's own gesture.
async function initFollow() {
  if (!browser || !browser.tabs) return;
  try {
    S.windowId = (await browser.windows.getCurrent()).id;
  } catch (e) {
    S.windowId = null;
  }
  try {
    S.tvAccess = await browser.permissions.contains({ origins: TV_ORIGINS });
  } catch (e) {
    S.tvAccess = false;
  }
  browser.permissions.onAdded.addListener(tvAccessGranted);
  browser.permissions.onRemoved.addListener(() => {
    browser.permissions.contains({ origins: TV_ORIGINS }).then((has) => {
      S.tvAccess = has;
      checkFront();
      render();
    }, () => {});
  });
  const ours = (windowId) => S.windowId === null || windowId === S.windowId;
  // A tab brought to the front is looked at again, whatever it showed before.
  browser.tabs.onActivated.addListener((info) => {
    if (!ours(info.windowId)) return;
    followTab(null, true);
    checkFront();
  });
  // TradingView rewrites its title with every price; only a new ticker counts. A tab that goes to
  // another site says only that it is loading: Chrome hides the address.
  browser.tabs.onUpdated.addListener((id, change, tab) => {
    if (!tab || !tab.active || !ours(tab.windowId)) return;
    if (change.title || change.url) followTab(tab, false);
    if (change.url || change.status) checkFront();
  });
  browser.tabs.onRemoved.addListener((tabId) => {
    if (tabId === S.chartTabId) S.chartTabId = null;
  });
  // A line dragged on TradingView's chart (tv/bridge.js), from the tab the panel draws on.
  browser.runtime.onMessage.addListener((msg, sender) => {
    if (msg && msg.t === 'ai-moved' && sender && sender.tab && sender.tab.id === S.chartTabId) lineMoved(msg.key, Number(msg.price));
  });
}

function tvAccessGranted() {
  if (S.tvAccess) return;
  S.tvAccess = true;
  followTab(null, true);
  checkFront();
  render();
}

// Called straight from a click, for Chrome to show its prompt.
function allowTv() {
  browser.permissions.request({ origins: TV_ORIGINS }).then((granted) => {
    if (granted) tvAccessGranted();
    else setStatus('The panel takes its symbol from TradingView, so it needs that access. Press Allow when you are ready', 1, 8000);
    render();
  }, () => {});
}

// Follows the ticker of the TradingView chart in front when it changed, or always with force.
// tab: the tab an event named, or null to look. True when the panel took a broker symbol from it.
async function followTab(tab, force) {
  if (!browser || !browser.tabs || !S.tvAccess || !term()) return false;
  if (!tab) {
    try {
      [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    } catch (e) {
      return false;
    }
  }
  const ticker = tab ? tickerFromTab(tab.url || '', tab.title || '') : '';
  if (ticker && tab.id !== undefined) S.chartTabId = tab.id;
  if (ticker !== S.tvShown) {
    S.tvShown = ticker;
    render();
  }
  if (!ticker) return false;
  if (ticker === S.followed && !force) return !!S.symbol;
  S.followed = ticker;
  return !!(await resolveTicker(ticker));
}

//--- only beside TradingView ------------------------------------------------------
// The panel closes itself when the tab in front of its window is not TradingView. Chrome shows it
// the tabs' addresses only once the trader allowed access to TradingView, so until then it stays.
// An order or a change on its way is waited for, and an error stays on screen for its time: "the
// order may have gone through" has to be seen.
const LEAVING = 'Not a TradingView tab: the panel closes';
let offTvSince = 0;   // when TradingView left the front; 0 while it is there
let offTvTimer = null;

function mustStay() {
  return S.sending || !!(S.card && S.card.busy) || (S.status.level >= 2 && Date.now() < S.status.until);
}

async function checkFront() {
  clearTimeout(offTvTimer);
  if (!browser || !browser.tabs || !S.tvAccess) {
    offTvSince = 0;
    return;
  }
  let tab;
  try {
    [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  } catch (e) {
    return;
  }
  if (tab && isTradingView(tab.url)) {
    offTvSince = 0;
    if (S.status.text === LEAVING) S.status.until = 0;
    return;
  }
  if (!offTvSince) {
    offTvSince = Date.now();
    if (!mustStay()) setStatus(LEAVING, 1, LEAVE_MS);
    render();
  }
  const wait = offTvSince + LEAVE_MS - Date.now();
  if (wait > 0 || mustStay()) {
    clearTimeout(offTvTimer);
    offTvTimer = setTimeout(checkFront, Math.max(wait, 250));
    return;
  }
  // chrome.sidePanel.close came in Chrome 141; before it, the panel's page closes the panel.
  if (browser.sidePanel && browser.sidePanel.close) browser.sidePanel.close({ windowId: S.windowId }).catch(() => window.close());
  else window.close();
}

// What the line under the symbol says, and whether it is a warning.
function followText() {
  if (!S.tvAccess || !term()) return { text: '', warn: false };
  const staying = 'the panel stays on ' + (S.symbol || 'no symbol');
  if (!S.tvShown) return { text: 'No TradingView chart in front: ' + staying, warn: false };
  if (S.tvMissing) return { text: 'TradingView shows ' + S.tvMissing + ', which this broker does not have: ' + staying, warn: true };
  if (S.candidates.length) return { text: '', warn: false };
  return { text: 'From TradingView: ' + S.tvShown, warn: false };
}

//--- lines on TradingView's chart ------------------------------------------------
// The preview and the open trades on the panel's symbol, drawn on the TradingView chart it follows
// (tv/page.js), and lines the trader drags there brought back. A drag changes only what the panel
// shows: nothing reaches MT5 before a Confirm in the panel.
const CHART_RESEND_MS = 2000;   // tv/page.js takes the lines away when they stop coming (the panel closed)
const chartSent = { tabId: null, sig: '', at: 0 };

function chartLines() {
  if (!S.tvAccess || !S.symbol || !S.spec || S.tvMissing || S.candidates.length) return [];
  const p = S.side && S.plan ? S.plan : null;
  const c = S.card && S.card.kind === 'mod' ? S.card : null;
  return wantedLines({
    preview: p ? Object.assign({ pending: S.pending }, p) : null,
    trades: trades().filter((x) => x.symbol === S.symbol),
    card: c ? {
      ticket: c.ticket,
      open: fmt.parseLevel(c.open),
      sl: fmt.parseLevel(c.sl),
      tp: fmt.parseLevel(c.tp),
      type: c.result && c.result.retype ? c.result.type : '',
    } : null,
    volStep: S.spec.volStep,
    money,
  });
}

// Sends the lines when they changed, and every 2 s anyway.
function syncChart() {
  if (!browser || !browser.scripting) return;
  if (S.chartTabId !== chartSent.tabId) {
    if (chartSent.tabId !== null) sendLines(chartSent.tabId, []);
    chartSent.tabId = S.chartTabId;
    chartSent.sig = '';
  }
  if (S.chartTabId === null) return;
  const lines = chartLines();
  const sig = JSON.stringify(lines);
  if (sig === chartSent.sig && Date.now() - chartSent.at < CHART_RESEND_MS) return;
  chartSent.sig = sig;
  chartSent.at = Date.now();
  sendLines(S.chartTabId, lines);
}

// When the tab doesn't have the scripts yet (a new tab, or TradingView reloaded), puts them in first.
async function sendLines(tabId, lines) {
  const msg = { t: 'ai-lines', lines };
  try {
    await browser.tabs.sendMessage(tabId, msg);
  } catch (e) {
    if (!lines.length) return;
    try {
      await browser.scripting.executeScript({ target: { tabId }, files: ['tv/bridge.js'] });
      await browser.scripting.executeScript({ target: { tabId }, files: ['tv/page.js'], world: 'MAIN' });
      await browser.tabs.sendMessage(tabId, msg);
    } catch (e2) {
      // a page the panel may not draw on: no lines there
    }
  }
}

// A preview line dragged sets that level as a price; an open trade's opens its change card, as a
// drag on the MT5 chart does. Prices far from the market are not taken.
function lineMoved(key, price) {
  const k = parseLineKey(key);
  const q = S.quote;
  if (!k || !S.spec || !q || !(price > 0) || Math.abs(price - (q.bid + q.ask) / 2) > (q.bid + q.ask) / 4) return;
  const text = fmt.price(price, S.spec.digits);
  if (!k.ticket) {
    if (!S.side || S.sending) return;
    if (k.role === 'sl') {
      prefs.slMode = 'price';
      prefs.slValue = text;
    } else if (k.role === 'tp') {
      prefs.tpMode = 'price';
      prefs.tpValue = text;
    } else if (k.role === 'entry' && S.pending) {
      S.entry = text;
      S.entrySet = true;
    } else return;
    setStatus('Moved on the chart. Check the numbers, then confirm', 0, 3000);
    changed();
    return;
  }
  const x = findTrade(k.ticket);
  if (!x || x.symbol !== S.symbol || x.locked || (k.role === 'entry' && x.kind !== 'order')) return;
  if (!S.card || S.card.kind !== 'mod' || S.card.ticket !== x.ticket) openCard('mod', x);
  const c = S.card;
  if (c.busy) return;
  if (k.role === 'entry') {
    // A pending order's SL and TP move with its entry, as on the MT5 chart.
    const was = fmt.parseLevel(c.open) || x.open;
    const sl = fmt.parseLevel(c.sl);
    const tp = fmt.parseLevel(c.tp);
    c.open = text;
    if (sl > 0) c.sl = fmt.price(sl + price - was, S.spec.digits);
    if (tp > 0) c.tp = fmt.price(tp + price - was, S.spec.digits);
  } else c[k.role] = text;
  c.edits++;
  c.at = Date.now();
  scheduleCardPreview(0);
  render();
}

//--- the new order ----------------------------------------------------------------
function eaRiskBase() {
  const st = settings();
  return (st && st.riskBase) || 'equity';
}

// What the risk % is measured on. As on the chart (App.mqh), the trader's choice holds until the
// EA's input changes.
function riskBase() {
  return prefs.riskBase && prefs.riskBaseInput === eaRiskBase() ? prefs.riskBase : eaRiskBase();
}

function riskInput() {
  if (prefs.chip === 'custom') {
    const v = fmt.parseNumber(prefs.custom[prefs.customUnit]);
    return { riskMode: prefs.customUnit, riskValue: v > 0 ? v : 0 };
  }
  const st = settings();
  const presets = (st && st.presets) || [1, 1.5, 2];
  return { riskMode: 'percent', riskValue: presets[prefs.chip] || presets[0] };
}

function marketFor(side) {
  if (!S.quote) return 0;
  return side > 0 ? S.quote.ask : S.quote.bid;
}

function defaultEntry() {
  const st = settings();
  const offset = ((st && st.pendingOffsetPips) || 10) * ((S.spec && S.spec.pipSize) || 0);
  const m = marketFor(S.side || 1);
  return m > 0 ? fmt.price(m - (S.side || 1) * offset, S.spec ? S.spec.digits : 5) : '';
}

function applyDefaults() {
  const st = settings();
  if (prefs.slValue === '' && st) {
    prefs.slMode = 'pips';
    prefs.slValue = String(st.defaultSLPips);
  }
  if (prefs.tpValue === '' && st) {
    prefs.tpMode = st.defaultTPMode || 'r';
    prefs.tpValue = String(st.defaultTPValue);
  }
}

let previewTimer = null;

function schedulePreview(ms) {
  clearTimeout(previewTimer);
  previewTimer = setTimeout(doPreview, ms === undefined ? 150 : ms);
}

// Changes that need a new look before Confirm counts: not the price drifting under a market order.
function materialChange(a, b) {
  return !a || !b || a.lots !== b.lots || a.type !== b.type || a.valid !== b.valid;
}

async function doPreview() {
  if (!S.side || !S.symbol || !S.spec || !term()) return;
  const seq = ++S.previewSeq;
  const sl = fmt.parseLevel(prefs.slValue);
  const tp = fmt.parseLevel(prefs.tpValue);
  const entry = S.pending ? fmt.parseLevel(S.entry) : 0;
  const bad = Number.isNaN(sl) ? 'The stop loss is not a number' : Number.isNaN(tp) ? 'The take profit is not a number' :
    Number.isNaN(entry) ? 'The entry is not a price' : '';
  if (bad) {
    S.plan = null;
    S.previewId = '';
    S.planErr = bad;
    render();
    return;
  }
  const inputs = S.inputs;
  const fields = Object.assign({
    symbol: S.symbol,
    side: S.side > 0 ? 'buy' : 'sell',
    pending: S.pending,
    entry,
    slMode: prefs.slMode,
    slValue: sl,
    tpMode: prefs.tpMode,
    tpValue: tp,
    riskBase: riskBase(),
  }, riskInput());
  S.previewAt = Date.now();
  const r = await link.request('preview', fields, S.term);
  if (seq !== S.previewSeq || !S.side) return;
  if (!r.ok) {
    S.plan = null;
    S.previewId = '';
    S.planErr = r.err;
  } else {
    // The numbers of a changed order count from when they are on screen, however long MT5 took.
    if (inputs !== S.planInputs || materialChange(S.plan, r.plan)) {
      S.planAt = Date.now();
      renderWhenArmed();
    }
    S.plan = r.plan;
    S.previewId = r.preview;
    S.planErr = '';
  }
  S.planInputs = inputs;
  render();
}

// Confirm lights up when the arm delay ends, not at the next 250 ms redraw.
function renderWhenArmed() {
  setTimeout(render, ARM_MS + 20);
}

// Until MT5's preview of the change comes back, the plan on screen is the old order's, and Confirm
// waits: it would send that old preview.
function changed() {
  S.inputs++;
  S.planAt = Date.now();
  savePrefs();
  schedulePreview();
  render();
}

async function onSide(side) {
  if (!S.spec) return;
  if (S.side === side) {
    closePreview('Preview closed. Nothing was sent', 0);
    render();
    return;
  }
  const fresh = !S.side;
  S.side = side;
  if (S.pending && !S.entrySet) S.entry = defaultEntry();
  applyDefaults();
  if (fresh) {
    // A new preview starts from the newest record, as on the chart (App.mqh).
    S.recallSl = 0;
    S.recallTp = 0;
    if (prefs.autoRecall) await recall('both', true);
  }
  changed();
}

function closePreview(text, level) {
  S.side = 0;
  S.plan = null;
  S.previewId = '';
  S.planErr = '';
  S.previewSeq++;
  if (text) setStatus(text, level, 4000);
}

function toggleSlMode() {
  if (prefs.slMode === 'pips') {
    if (S.plan && S.plan.sl > 0) prefs.slValue = fmt.price(S.plan.sl, S.spec.digits);
    prefs.slMode = 'price';
  } else {
    if (S.plan && S.plan.slPips > 0) prefs.slValue = fmt.pips(S.plan.slPips);
    prefs.slMode = 'pips';
  }
  changed();
}

function cycleTpMode() {
  const next = { r: 'pips', pips: 'price', price: 'r' }[prefs.tpMode] || 'r';
  if (next === 'pips' && S.plan && S.plan.tpPips > 0) prefs.tpValue = fmt.pips(S.plan.tpPips);
  else if (next === 'price' && S.plan && S.plan.tp > 0) prefs.tpValue = fmt.price(S.plan.tp, S.spec.digits);
  else if (next === 'r') prefs.tpValue = S.plan && S.plan.rr > 0 ? fmt.trimZeros(S.plan.rr.toFixed(2)) : '2';
  prefs.tpMode = next;
  changed();
}

// Earlier SL/TP for this symbol, as the chart's Last buttons: each press goes one record further back.
async function recall(which, auto) {
  if (!S.symbol || !term()) return;
  const back = which === 'tp' ? S.recallTp : S.recallSl;
  const side = S.side || 1;
  const r = await link.request('recall', {
    symbol: S.symbol,
    side: side > 0 ? 'buy' : 'sell',
    entry: S.pending ? fmt.parseNumber(S.entry) || 0 : 0,
    which,
    back,
  }, S.term);
  if (!r.ok) {
    if (!auto) setStatus(r.err, 0, 4000);
    return;
  }
  if (which !== 'tp') {
    prefs.slMode = r.slMode;
    prefs.slValue = String(r.slValue);
  }
  if (which !== 'sl') {
    prefs.tpMode = r.tpMode;
    prefs.tpValue = String(r.tpValue);
  }
  const n = r.count || 0;
  const used = r.index || 0;
  const next = n ? (used + 1) % n : 0;
  if (which !== 'tp') S.recallSl = next;
  if (which !== 'sl') S.recallTp = next;
  const from = auto ? 'Set automatically' : n ? 'Recalled ' + (used + 1) + '/' + n : 'From your last trade';
  setStatus(from + ': ' + r.desc, 0, 4000);
  if (!auto) changed();
}

function canConfirm() {
  const i = info();
  return !!(i && S.side && S.plan && S.plan.valid && S.previewId && S.planInputs === S.inputs && !S.sending && link.connected &&
            alive(S.term) && Date.now() - S.planAt >= ARM_MS && !i.problem);
}

function slipTolerance(planned) {
  return Math.max(0.01, planned * 0.005);
}

// What the chart panel says after an order (App.mqh OnSent / FillText).
function sentText(r) {
  const f = r.fill || {};
  if (f.slipped) {
    let what = 'SL/TP kept';
    if (f.notMoved) what = 'SL/TP not moved';
    else if (f.slMoved && f.tpMoved) what = 'SL/TP moved';
    else if (f.slMoved) what = 'SL moved, TP kept';
    else if (f.tpMoved) what = 'SL kept, TP moved';
    let text = 'Filled ' + Math.abs(f.slipPips).toFixed(1) + ' pips ' + (f.slipPips > 0 ? 'worse' : 'better') + '. ' + what;
    if (f.sl > 0) {
      text += Math.abs(f.risk - f.plannedRisk) <= slipTolerance(f.plannedRisk)
        ? ': risk ' + money(f.risk) + ' as planned'
        : ': risk ' + money(f.risk) + ' (plan ' + money(f.plannedRisk) + ')';
    }
    return text;
  }
  return r.type + ' ' + fmt.lots(r.lots, S.spec.volStep) + ' ' + S.symbol + (r.pending ? ' placed at ' : ' filled at ') + fmt.price(r.price, S.spec.digits);
}

async function confirm() {
  if (!canConfirm()) return;
  S.sending = true;
  render();
  const r = await link.request('send', { preview: S.previewId }, S.term);
  S.sending = false;
  if (r.ok) {
    const f = r.fill || {};
    const worse = f.slipped && f.sl > 0 && f.risk > f.plannedRisk + slipTolerance(f.plannedRisk);
    setStatus(sentText(r), worse ? 1 : 3, 10000);
    closePreview('', 0);
    S.recallSl = 0;
    S.recallTp = 0;
  } else if (r.lost) {
    closePreview('', 0);
    setStatus(r.err + ': the order may have gone through. Check Open trades before sending again', 2, 30000);
  } else {
    setStatus('Not sent: ' + r.err, 2, 8000);
    schedulePreview(0);
  }
  render();
}

//--- open trades: close, change, remove --------------------------------------------
function trades() {
  const t = term();
  return (t && t.trades && t.trades.list) || [];
}

function findTrade(ticket) {
  return trades().find((x) => x.ticket === ticket) || null;
}

let cardTimer = null;

function openCard(kind, x) {
  S.card = {
    kind,
    ticket: x.ticket,
    trade: x,
    lots: String(x.lots),
    sl: x.sl > 0 ? fmt.price(x.sl, x.digits) : '',
    tp: x.tp > 0 ? fmt.price(x.tp, x.digits) : '',
    open: fmt.price(x.open, x.digits),
    preview: '',
    result: null,
    err: '',
    busy: false,
    seq: 0,
    at: Date.now(),
    edits: 0,            // as S.inputs: the card's confirm waits for MT5's look at the latest edit
    previewEdits: -1,
  };
  if (kind !== 'cancel') scheduleCardPreview(0);
  render();
}

// The change card with the stop at the entry. MT5 decides whether the price is far enough past it
// yet, and the card says so either way.
function breakEven(x) {
  openCard('mod', x);
  S.card.sl = fmt.price(x.open, x.digits);
  S.card.edits++;
  S.card.at = Date.now();
  scheduleCardPreview(0);
  render();
}

function scheduleCardPreview(ms) {
  clearTimeout(cardTimer);
  cardTimer = setTimeout(cardPreview, ms === undefined ? 200 : ms);
}

// What a card asks MT5 for, from what the trader typed; or why it can't ask. Lots of 0 would close
// all of the position, so an empty field never stands for it: the field starts with the full size.
function cardFields(c) {
  if (c.kind === 'close') {
    const lots = fmt.parseNumber(c.lots);
    return lots > 0 ? { ticket: c.ticket, lots } : 'Type how many lots to close';
  }
  const fields = { ticket: c.ticket, sl: fmt.parseLevel(c.sl), tp: fmt.parseLevel(c.tp) };
  if (Number.isNaN(fields.sl)) return 'The stop loss is not a price';
  if (Number.isNaN(fields.tp)) return 'The take profit is not a price';
  if (c.trade.kind === 'order') {
    fields.open = fmt.parseNumber(c.open);
    if (!(fields.open > 0)) return 'Type the entry price';
  }
  return fields;
}

// Changes that need a new look before Confirm counts: not the price drifting under a close.
function cardChanged(a, b) {
  return !a || !b || a.valid !== b.valid || a.lots !== b.lots || a.left !== b.left || a.open !== b.open || a.sl !== b.sl || a.tp !== b.tp;
}

async function cardPreview() {
  const c = S.card;
  if (!c || c.kind === 'cancel') return;
  const seq = ++c.seq;
  const edits = c.edits;
  const fields = cardFields(c);
  let r;
  if (typeof fields === 'string') r = { ok: false, err: fields };
  else r = await link.request(c.kind === 'close' ? 'closePreview' : 'modPreview', fields, S.term);
  if (S.card !== c || seq !== c.seq) return;
  const result = r.ok ? r.close || r.mod : null;
  const err = r.ok ? '' : r.err;
  if (err !== c.err || edits !== c.previewEdits || cardChanged(c.result, result)) {
    c.at = Date.now();
    renderWhenArmed();
  }
  c.previewEdits = edits;
  c.preview = r.ok ? r.preview : '';
  c.result = result;
  c.err = err;
  render();
}

function cardReady(c) {
  if (!c || c.busy || !alive(S.term) || Date.now() - c.at < ARM_MS) return false;
  if (c.kind === 'cancel') return true;
  return !!(c.preview && c.previewEdits === c.edits && c.result && c.result.valid);
}

async function cardConfirm() {
  const c = S.card;
  if (!cardReady(c)) return;
  c.busy = true;
  render();
  let r;
  if (c.kind === 'close') r = await link.request('close', { preview: c.preview }, S.term);
  else if (c.kind === 'mod') r = await link.request('modSend', { preview: c.preview }, S.term);
  else r = await link.request('cancel', { ticket: c.ticket }, S.term);
  if (r.lost) {
    setStatus(r.err + ': check #' + c.ticket + ' in Open trades before trying again', 2, 30000);
    if (S.card === c) S.card = null;
    render();
    return;
  }
  // A type change whose new order was refused after the old one was removed: there is no order left
  // for the card to change, and the message says so.
  if (r.removed) {
    setStatus(r.err, 2, 30000);
    if (S.card === c) S.card = null;
    render();
    return;
  }
  if (S.card !== c) return;
  c.busy = false;
  if (r.ok) {
    const x = c.trade;
    if (c.kind === 'close') setStatus('Closed ' + fmt.lots(r.lots, 0.01) + ' of ' + x.type + ' ' + x.symbol + ' at ' + fmt.price(r.price, x.digits), 3, 8000);
    else if (c.kind === 'mod' && r.replaced) setStatus(x.type + ' #' + x.ticket + ' is now ' + r.type + ' #' + r.ticket + ' ' + x.symbol, 3, 8000);
    else if (c.kind === 'mod') setStatus('Changed #' + x.ticket + ' ' + x.symbol, 3, 6000);
    else setStatus('Removed ' + x.type + ' #' + x.ticket + ' ' + x.symbol, 3, 6000);
    S.card = null;
  } else {
    c.err = r.err;
    c.at = Date.now();
    if (c.kind !== 'cancel') scheduleCardPreview(0);
  }
  render();
}

// A trade that closed or filled on the server while its card was open takes the card with it.
function syncCard() {
  const c = S.card;
  if (!c) return;
  const x = findTrade(c.ticket);
  if (!x || x.kind !== c.trade.kind) {
    setStatus('#' + c.ticket + ' is no longer ' + (c.trade.kind === 'order' ? 'pending' : 'open') + '. Nothing was changed', 1, 6000);
    S.card = null;
    return;
  }
  const moved = x.lots !== c.trade.lots || x.sl !== c.trade.sl || x.tp !== c.trade.tp || x.open !== c.trade.open;
  c.trade = x;
  // A close card shows the money at the price now: trades come each second while positions are open.
  if (!c.busy && (moved ? c.kind !== 'cancel' : c.kind === 'close')) scheduleCardPreview(0);
}

//--- drawing ----------------------------------------------------------------------
function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

function setValue(input, value) {
  if (document.activeElement !== input && input.value !== value) input.value = value;
}

function render() {
  const i = info();
  const t = term();

  // Terminal and link
  $('account').textContent = i ? i.server + ' · ' + i.login : 'ActionInna';
  const mode = $('mode');
  mode.hidden = !i;
  if (i) {
    mode.textContent = i.tradeMode === 'real' ? 'REAL' : i.tradeMode === 'contest' ? 'CONTEST' : 'DEMO';
    mode.className = 'badge' + (i.tradeMode === 'real' ? ' real' : '');
  }
  // Under the account: what stops trading when something does, else the account's money.
  let conn = S.linkText;
  let connLevel = 'muted';
  if (i) {
    const tr = t && t.trades;
    if (!alive(S.term)) { conn = 'MT5 is not answering'; connLevel = 'warnText'; }
    else if (!i.connected) { conn = 'MT5 is not connected to ' + i.server; connLevel = 'warnText'; }
    else if (i.problem) { conn = i.problem; connLevel = 'warnText'; }
    else if (tr) conn = 'Equity ' + money(tr.equity) + ' · Free ' + money(tr.freeMargin) + (i.marginMode !== 'hedging' ? ' · ' + i.marginMode : '');
    else conn = 'Connected';
  }
  $('conn').textContent = conn;
  $('conn').className = connLevel + ' grow';
  $('startMt5').hidden = !link.connected || S.terms.size > 0 || S.linkState === 'starting-mt5' || S.linkState === 'busy';
  const terms = $('terms');
  $('termRow').hidden = S.terms.size < 2;
  const termsSig = [...S.terms.entries()].map(([id, x]) => id + ':' + (x.info ? x.info.login + '@' + x.info.server : '')).join('|') + '#' + S.term;
  if (terms.dataset.sig !== termsSig) {
    terms.dataset.sig = termsSig;
    terms.replaceChildren(...[...S.terms.entries()].map(([id, x]) => {
      const o = el('option', '', x.info ? x.info.server + ' · ' + x.info.login : 'MT5 ' + id);
      o.value = id;
      o.selected = id === S.term;
      return o;
    }));
  }

  // Symbol and price
  $('symbol').textContent = S.symbol || 'No symbol yet';
  $('symbol').className = 'symbolName' + (S.symbol ? '' : ' muted');
  $('followAsk').hidden = !(browser && browser.tabs && !S.tvAccess);
  const note = followText();
  $('followNote').textContent = note.text;
  $('followNote').hidden = !note.text;
  $('followNote').className = 'small ' + (note.warn ? 'warnText' : 'muted');
  const cands = $('cands');
  cands.hidden = S.candidates.length === 0;
  if (cands.dataset.version !== String(S.candVersion)) {
    cands.dataset.version = String(S.candVersion);
    cands.replaceChildren(...(S.candidates.length ? [el('div', 'muted small', 'Which symbol is ' + S.ticker + ' at this broker?')] : []),
      ...S.candidates.map((c) => {
        const b = el('button', '', c.name + (c.description ? ' (' + c.description + ')' : ''));
        b.type = 'button';
        b.addEventListener('click', () => chooseCandidate(c.name));
        return b;
      }));
  }
  const spec = S.spec;
  const q = S.quote;
  const d = spec ? spec.digits : 5;
  $('spread').textContent = q ? fmt.pips(q.spreadPips) : '-';
  $('sellPx').textContent = q ? fmt.price(q.bid, d) : '-';
  $('buyPx').textContent = q ? fmt.price(q.ask, d) : '-';

  // Order form
  const ready = !!(spec && t);
  $('sell').setAttribute('aria-pressed', String(S.side < 0));
  $('buy').setAttribute('aria-pressed', String(S.side > 0));
  $('sell').disabled = !ready;
  $('buy').disabled = !ready;
  $('kindMarket').setAttribute('aria-pressed', String(!S.pending));
  $('kindPending').setAttribute('aria-pressed', String(S.pending));
  $('entryRow').hidden = !S.pending;
  setValue($('entry'), S.entry);
  const st = settings();
  const presets = (st && st.presets) || [1, 1.5, 2];
  document.querySelectorAll('[data-chip]').forEach((b) => {
    const n = Number(b.dataset.chip);
    b.textContent = fmt.trimZeros(String(presets[n])) + '%';
    b.setAttribute('aria-pressed', String(prefs.chip === n));
  });
  setValue($('custom'), prefs.custom[prefs.customUnit]);
  $('customUnit').textContent = { percent: '%', money: currency() === 'USD' ? '$' : currency(), lots: 'lots' }[prefs.customUnit];
  $('customUnit').setAttribute('aria-pressed', String(prefs.chip === 'custom'));
  setValue($('sl'), prefs.slValue);
  setValue($('tp'), prefs.tpValue);
  $('slMode').textContent = prefs.slMode;
  $('tpMode').textContent = prefs.tpMode === 'r' ? 'R' : prefs.tpMode;
  $('optAuto').checked = prefs.autoRecall;
  $('optBase').textContent = riskBase();

  const p = S.side ? S.plan : null;
  const has = p && p.lots > 0;
  $('nLots').textContent = has ? fmt.lots(p.lots, spec.volStep) : '-';
  $('planBox').hidden = !S.side;
  $('nRisk').textContent = has && p.riskMoney > 0 ? money(-p.riskMoney) + ' (' + p.riskPct.toFixed(2) + '%)' : '-';
  $('nRisk').className = has && p.riskMoney > 0 ? 'dangerText' : '';
  $('nReward').textContent = has && p.tp > 0 ? money(p.rewardMoney, true) + '  (' + p.rewardPct.toFixed(2) + '%)' : '-';
  $('nReward').className = has && p.tp > 0 ? 'goodText' : '';
  $('nRr').textContent = p && p.rr > 0 ? '1:' + p.rr.toFixed(2) : '-';
  $('nDist').textContent = p ? 'SL ' + fmt.pips(p.slPips) + ' · TP ' + fmt.pips(p.tpPips) : '-';
  $('nPip').textContent = has ? money(p.pipValue) : '-';
  $('nMargin').textContent = has ? money(p.margin) + '  (free ' + money(p.freeAfter) + ')' : '-';

  // Status: what the plan says, unless a message of the moment matters as much
  const status = $('status');
  let text = '';
  let level = 0;
  if (S.side && S.planErr) {
    text = S.planErr;
    level = 2;
  } else if (p && p.err) {
    text = p.err;
    level = 2;
  } else if (p && p.warn) {
    text = p.warn;
    level = 1;
  } else if (p && i && i.marginMode !== 'hedging') {
    text = 'Netting account: this order merges with any open position on the symbol and replaces its SL/TP';
    level = 1;
  } else if (S.side) text = 'Check the numbers, then confirm. Nothing is sent before that';
  else if (!S.symbol && t) text = S.tvAccess ? 'Open a TradingView chart' : 'Allow access to TradingView: the panel takes its symbol from its chart';
  if (S.status.text && Date.now() < S.status.until && S.status.level >= level) {
    text = S.status.text;
    level = S.status.level;
  }
  status.textContent = text;
  status.className = 'status l' + level;

  const btn = $('confirm');
  if (S.sending) btn.textContent = 'Sending…';
  else if (!S.side) btn.textContent = 'Confirm';
  else {
    const what = p && S.pending ? p.type : S.side > 0 ? 'BUY' : 'SELL';
    btn.textContent = (S.pending ? 'Place ' : 'Confirm ') + what + (has ? ' ' + fmt.lots(p.lots, spec.volStep) + ' lots' : '');
  }
  btn.className = 'confirm grow' + (S.side > 0 ? ' buy' : S.side < 0 ? ' sell' : '');
  btn.disabled = !canConfirm();

  renderTrades();
  syncChart();
}

// Rows are kept per ticket and only their texts change, so a click on a button never lands on a row
// that was just drawn again.
const rows = new Map();

function makeRow(x) {
  const r = { kind: x.kind, locked: !!x.locked, x };
  r.li = el('li', 'trade');
  const what = el('div', 'what');
  r.what = el('span', '');
  r.profit = el('span', '');
  what.append(r.what, r.profit);
  r.levels = el('div', 'levels');
  const acts = el('div', 'acts');
  const add = (label, kind) => {
    const b = el('button', '', label);
    b.type = 'button';
    b.addEventListener('click', () => (kind === 'be' ? breakEven(r.x) : openCard(kind, r.x)));
    acts.append(b);
  };
  if (x.kind === 'position') {
    add('Close', 'close');
    add('Change SL/TP', 'mod');
    add('Break-even', 'be');
  } else {
    if (!x.locked) add('Change', 'mod');
    add('Remove', 'cancel');
  }
  r.li.append(what, r.levels, acts);
  return r;
}

function renderTrades() {
  const list = trades();
  $('noTrades').hidden = list.length > 0;
  const ul = $('trades');
  const seen = new Set();
  list.forEach((x, idx) => {
    seen.add(x.ticket);
    let r = rows.get(x.ticket);
    if (!r || r.kind !== x.kind || r.locked !== !!x.locked) {
      if (r) r.li.remove();
      r = makeRow(x);
      rows.set(x.ticket, r);
    }
    r.x = x;
    r.what.textContent = x.type + ' ' + fmt.trimZeros(String(x.lots)) + ' ' + x.symbol + ' @ ' + fmt.price(x.open, x.digits);
    r.what.className = x.side > 0 ? 'buyText' : 'sellText';
    r.profit.textContent = x.kind === 'position' ? money(x.profit, true) : '';
    r.profit.className = x.profit >= 0 ? 'goodText' : 'dangerText';
    r.levels.textContent = 'SL ' + (x.sl > 0 ? fmt.price(x.sl, x.digits) : 'none') + ' · TP ' + (x.tp > 0 ? fmt.price(x.tp, x.digits) : 'none') + ' · #' + x.ticket;
    if (ul.children[idx] !== r.li) ul.insertBefore(r.li, ul.children[idx] || null);
  });
  for (const [ticket, r] of rows) {
    if (!seen.has(ticket)) {
      r.li.remove();
      rows.delete(ticket);
    }
  }
  renderCard();
}

// The card is built once when it opens, so typing in its fields keeps the cursor; its numbers,
// message and button are updated on every redraw.
let cardView = null;

function buildCard(c) {
  const v = { card: c, inputs: {} };
  const x = c.trade;
  const kids = [];
  v.title = el('strong', '');
  kids.push(v.title);
  const field = (label, key) => {
    const row = el('label', 'line');
    row.append(el('span', 'label', label));
    const input = el('input', 'grow');
    input.type = 'text';
    input.inputMode = 'decimal';
    input.value = c[key];
    input.addEventListener('input', () => {
      c[key] = input.value;
      c.edits++;
      c.at = Date.now();
      scheduleCardPreview();
      render();
    });
    v.inputs[key] = input;
    row.append(input);
    return row;
  };
  if (c.kind === 'close') kids.push(field('Lots', 'lots'));
  else if (c.kind === 'mod') {
    if (x.kind === 'order') kids.push(field('Entry', 'open'));
    kids.push(field('Stop loss', 'sl'));
    kids.push(field('Take profit', 'tp'));
  }
  v.line1 = el('div', 'small');
  v.line2 = el('div', 'small');
  v.msg = el('div', 'status');
  kids.push(v.line1, v.line2, v.msg);
  const acts = el('div', 'acts');
  v.go = el('button', 'go ' + (x.side > 0 ? 'buy' : 'sell'));
  v.go.type = 'button';
  v.go.addEventListener('click', cardConfirm);
  const no = el('button', '', 'Cancel');
  no.type = 'button';
  no.addEventListener('click', () => {
    S.card = null;
    setStatus('Nothing was changed', 0, 3000);
    render();
  });
  acts.append(v.go, no);
  kids.push(acts);
  $('card').replaceChildren(...kids);
  return v;
}

function renderCard() {
  const box = $('card');
  const c = S.card;
  box.hidden = !c;
  if (!c) {
    if (cardView) box.replaceChildren();
    cardView = null;
    return;
  }
  if (!cardView || cardView.card !== c) cardView = buildCard(c);
  const v = cardView;
  // A level dragged on TradingView's chart arrives in the card; a field being typed in keeps its text.
  for (const [key, input] of Object.entries(v.inputs)) setValue(input, c[key]);
  const x = c.trade;
  const r = c.result;
  v.title.textContent = { close: 'Close ', mod: 'Change ', cancel: 'Remove ' }[c.kind] + x.type + ' ' + fmt.trimZeros(String(x.lots)) + ' ' + x.symbol + ' #' + x.ticket;
  let l1 = '';
  let l2 = '';
  if (c.kind === 'close' && r) {
    l1 = 'At ' + fmt.price(r.price, x.digits) + ': ' + money(r.profit, true) + ' (swap in, commission not)';
    l2 = r.left > 0 ? fmt.trimZeros(String(r.left)) + ' lots stay open' : 'All of it closes';
  } else if (c.kind === 'mod' && r) {
    l1 = 'SL ' + (r.sl > 0 ? fmt.price(r.sl, x.digits) + ': ' + money(r.slMoney, true) + ' (was ' + money(r.oldSlMoney, true) + ')' : 'none');
    l2 = 'TP ' + (r.tp > 0 ? fmt.price(r.tp, x.digits) + ': ' + money(r.tpMoney, true) : 'none') + (r.rr > 0 ? ' · R:R 1:' + r.rr.toFixed(2) : '');
  } else if (c.kind === 'cancel') l1 = 'The order is removed from the server. Nothing else changes.';
  v.line1.textContent = l1;
  v.line2.textContent = l2;
  const hard = c.err || (r && r.err) || '';
  const soft = (r && r.warn) || (r && c.kind === 'mod' && !r.changed ? 'Nothing to change yet' : '');
  v.msg.textContent = hard || soft;
  v.msg.className = 'status l' + (hard ? 2 : soft ? 1 : 0);
  v.go.textContent = c.busy ? 'Sending…' : { close: 'Confirm close', mod: 'Confirm change', cancel: 'Remove' }[c.kind];
  v.go.disabled = !cardReady(c);
}

//--- wiring -----------------------------------------------------------------------
function wire() {
  $('startMt5').addEventListener('click', () => {
    link.post({ t: 'link.start' });
    S.linkText = 'Starting MT5…';
    render();
  });
  $('terms').addEventListener('change', (e) => {
    if (S.side) closePreview('Another MT5 was chosen: the preview was closed. Nothing was sent', 1);
    S.card = null;
    chooseTerm(e.target.value);
    render();
  });
  $('followAllow').addEventListener('click', allowTv);
  $('sell').addEventListener('click', () => onSide(-1));
  $('buy').addEventListener('click', () => onSide(1));
  const setPending = (on) => {
    if (S.pending === on) return;
    S.pending = on;
    if (on) {
      S.entry = defaultEntry();
      S.entrySet = false;
    }
    changed();
  };
  $('kindMarket').addEventListener('click', () => setPending(false));
  $('kindPending').addEventListener('click', () => setPending(true));
  $('entry').addEventListener('input', (e) => {
    S.entry = e.target.value;
    S.entrySet = true;
    changed();
  });
  document.querySelectorAll('[data-chip]').forEach((b) => b.addEventListener('click', () => {
    prefs.chip = Number(b.dataset.chip);
    changed();
  }));
  $('custom').addEventListener('input', (e) => {
    prefs.custom[prefs.customUnit] = e.target.value;
    prefs.chip = 'custom';
    changed();
  });
  $('customUnit').addEventListener('click', () => {
    prefs.customUnit = { percent: 'money', money: 'lots', lots: 'percent' }[prefs.customUnit];
    prefs.chip = 'custom';
    changed();
  });
  $('sl').addEventListener('input', (e) => {
    prefs.slValue = e.target.value;
    changed();
  });
  $('tp').addEventListener('input', (e) => {
    prefs.tpValue = e.target.value;
    changed();
  });
  $('slMode').addEventListener('click', toggleSlMode);
  $('tpMode').addEventListener('click', cycleTpMode);
  $('slLast').addEventListener('click', () => recall('sl', false));
  $('tpLast').addEventListener('click', () => recall('tp', false));
  $('confirm').addEventListener('click', confirm);
  $('optAuto').addEventListener('change', (e) => {
    prefs.autoRecall = e.target.checked;
    savePrefs();
    setStatus(prefs.autoRecall ? 'SL/TP will be set from your last trade on the symbol' : 'SL/TP stay as you typed them last', 0, 4000);
    render();
  });
  $('optBase').addEventListener('click', () => {
    prefs.riskBase = riskBase() === 'equity' ? 'balance' : 'equity';
    prefs.riskBaseInput = eaRiskBase();
    setStatus('Risk in % of ' + prefs.riskBase, 0, 3000);
    changed();
  });
  $('cancelPreview').addEventListener('click', () => {
    closePreview('Preview closed. Nothing was sent', 0);
    render();
  });
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (S.card) {
      S.card = null;
      setStatus('Nothing was changed', 0, 3000);
    } else if (S.side) closePreview('Preview closed. Nothing was sent', 0);
    render();
  });
  // Time-limited messages and the arm delay need a redraw without any event.
  setInterval(render, 250);
}

await loadPrefs();
await initFollow();
wire();
render();
link.start();
checkFront();
