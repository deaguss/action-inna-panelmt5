// Security fuzz for the side panel's code, run by run.mjs: hundreds of thousands of hostile inputs
// against what decides where the panel works and what reaches MT5.
//   - TradingView's tabs: addresses built to look like TradingView (lookalike hosts, user info,
//     other schemes, encodings) and titles carrying markup. Only TradingView's own sites count, and a
//     ticker is always a plain ticker.
//   - Levels the trader types: a typo never becomes "no stop loss".
//   - Line keys and the lines drawn on TradingView's chart.
//   - tv/bridge.js and tv/page.js, run in a sandbox standing in for TradingView's page: whatever a
//     script on that page posts, the panel hears only a line key and a price, and only lines the
//     panel sent are drawn, with what it sent.
//   - The link connection, fed messages no link should send.
// A seeded generator: a failure prints its seed, and the same seed replays it.
import fs from 'node:fs';
import vm from 'node:vm';
import * as fmt from '../../extension/lib/format.js';
import { tickerFromTab, isTradingView } from '../../extension/lib/tv.js';
import { Link } from '../../extension/lib/link.js';
import { wantedLines, parseLineKey } from '../../extension/lib/lines.js';

const KEY = /^(?:pv|t\d{1,20})-(?:entry|sl|tp)$/;
const TICKER = /^[A-Z0-9._!:]{2,40}$/;

function prng(seed) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const int = (lo, hi) => lo + Math.floor(next() * (hi - lo + 1));
  const pick = (list) => list[int(0, list.length - 1)];
  return { next, int, pick, chance: (p) => next() < p };
}

const PIECES = ['a', 'Z', '0', '9', ' ', '.', ',', '-', '+', 'e', 'E', '%', '$', '"', "'", '\\', '/', ':', '@', '#', '?', '&', '=', '<', '>',
  '\t', '\n', '\u0000', '\u00a0', '\u200b', '\u2028', 'é', '١', '٫', '０', '𝟎', '\u{1F4B0}', '\ud800', 'Infinity', 'NaN', '0x1f', '1e3', '<img src=x onerror=1>',
  '__proto__', 'constructor', 'XAUUSD', ':', '!', '(2)', '▲'];

function randText(R, max) {
  let s = '';
  for (let n = R.int(0, max); n > 0; n--) s += R.pick(PIECES);
  return s;
}

// The independent rule: WHATWG URL parsing (Chrome's too), https, and a host that is tradingview.com
// or ends in .tradingview.com.
function tvOracle(url) {
  let u;
  try {
    u = new URL(url);
  } catch (e) {
    return false;
  }
  const h = u.hostname.toLowerCase();
  return u.protocol === 'https:' && (h === 'tradingview.com' || h.endsWith('.tradingview.com'));
}

const SCHEMES = ['https://', 'http://', 'HTTPS://', 'https:', 'https:/', 'https:\\\\', 'wss://', 'ftp://', 'file:///', 'javascript:', 'data:text/html,',
  'chrome-extension://abc/', 'blob:https://', 'view-source:https://', ' https://', 'https://\t', ''];
const USERS = ['', '', '', 'tradingview.com@', 'www.tradingview.com:443@', 'user:pass@', '@', 'a@b@'];
const HOSTS = ['tradingview.com', 'www.tradingview.com', 'in.tradingview.com', 'id.tradingview.com', 'a.b.c.tradingview.com', 'WWW.TradingView.COM',
  'tradingview.com.', 'tradingview.com.evil.com', 'www.tradingview.com.evil.net', 'evil-tradingview.com', 'eviltradingview.com', 'tradingview.co',
  'tradingview.com-evil.com', 'tradingvіew.com', 'xn--tradingview-9ob.com', 'tradingview.com%2eevil.com', 'www.tradingview.com%00.evil.com',
  'tradingview%2ecom', '127.0.0.1', '[::1]', 'localhost', 'tradingview.com\\.evil.com', 'evil.com\\@tradingview.com', 'evil.com#.tradingview.com',
  'evil.com?.tradingview.com', 'evil.com/.tradingview.com', '.tradingview.com', 'tradingview..com', '0x7f.1', 'ｔｒａｄｉｎｇｖｉｅｗ.com', ''];
const PORTS = ['', '', ':443', ':8443', ':0', ':99999', ':abc'];
const PATHS = ['/chart/abc/?symbol=OANDA%3AXAUUSD', '/symbols/OANDA-XAUUSD/', '/', '', '/chart', '/chart/?symbol=%3Cscript%3E', '\\@tradingview.com/',
  '#@tradingview.com', '?u=https://www.tradingview.com/', '/symbols/' + 'A'.repeat(60) + '/', '/chart/?symbol=FX:EURUSD&symbol=<b>',
  '/symbols/%E2%80%AEXAUUSD/', '/symbols/%ZZ/'];

function hostileUrl(R) {
  if (R.chance(0.05)) return R.pick([undefined, null, '', 'not a url', 42, {}, 'https://', '//www.tradingview.com/chart/']);
  return R.pick(SCHEMES) + R.pick(USERS) + R.pick(HOSTS) + R.pick(PORTS) + R.pick(PATHS) + (R.chance(0.1) ? randText(R, 4) : '');
}

function hostileTitle(R) {
  return R.pick(['', 'XAUUSD 2,650.12 ▲ +0.45% Unnamed', '(3) EURUSD 1.09', 'Unnamed', '<script>alert(1)</script> 1', 'OANDA:XAUUSD 1',
    'BTCUSDT.P 67,000', 'A'.repeat(50) + ' 1']) + (R.chance(0.5) ? randText(R, 10) : '');
}

function testTabs(R, rounds, expect) {
  let tv = 0;
  for (let i = 0; i < rounds; i++) {
    const url = hostileUrl(R);
    const title = hostileTitle(R);
    let is;
    let ticker;
    try {
      is = isTradingView(url);
      ticker = tickerFromTab(url, title);
    } catch (e) {
      expect(false, 'tabs: reading a tab never throws: ' + String(url) + ': ' + e.message);
      continue;
    }
    const want = tvOracle(url);
    if (want) tv++;
    expect(is === want, 'tabs: TradingView only on its own sites over https: ' + JSON.stringify(url) + ' gave ' + is);
    expect(want || ticker === '', 'tabs: no ticker from a tab that is not TradingView: ' + JSON.stringify(url) + ' gave ' + ticker);
    expect(ticker === '' || TICKER.test(ticker), 'tabs: a ticker is a plain ticker: ' + JSON.stringify(ticker));
  }
  expect(tv > rounds / 50, 'tabs: the fuzz also made real TradingView addresses (' + tv + ')');
}

// A stop loss, take profit or entry as typed: empty is none (0); anything else is a positive number
// or NaN. A typo must never come back as 0, which MT5 would take as "no stop loss".
function testLevels(R, rounds, expect) {
  for (let i = 0; i < rounds; i++) {
    const s = R.chance(0.3) ? String(R.int(0, 99999) / Math.pow(10, R.int(0, 6))) + randText(R, 1) : randText(R, 6);
    const v = fmt.parseLevel(s);
    const n = fmt.parseNumber(s);
    expect(v === 0 ? s.trim() === '' : Number.isNaN(v) || (Number.isFinite(v) && v > 0),
      'levels: ' + JSON.stringify(s) + ' -> ' + v + ' (only an empty field is no level)');
    expect(Number.isNaN(n) || Number.isFinite(n), 'levels: a typed number is finite or not a number: ' + JSON.stringify(s) + ' -> ' + n);
    expect(!(v > 0) || /\d/.test(s), 'levels: a level comes from digits: ' + JSON.stringify(s));
  }
  // Every plain decimal is read as itself.
  for (let i = 0; i < rounds / 4; i++) {
    const v = R.int(1, 9999999) / Math.pow(10, R.int(0, 7));
    const text = v.toFixed(R.int(0, 8)).replace(/\.0+$/, (m) => (R.chance(0.5) ? m : ''));
    if (Number(text) <= 0) continue;
    expect(fmt.parseLevel(text) === Number(text), 'levels: ' + text + ' reads as ' + Number(text));
    expect(fmt.parseLevel(text.replace('.', ',')) === Number(text), 'levels: ' + text.replace('.', ',') + ' with a decimal comma');
  }
}

function testKeys(R, rounds, expect) {
  const roles = ['entry', 'sl', 'tp'];
  for (let i = 0; i < rounds; i++) {
    const s = R.chance(0.5) ? randText(R, 8) : R.pick(['pv-', 't', 't-', 'pv-sl', 't12-tp', 't' + '9'.repeat(21) + '-sl', 'pv-SL', 'PV-sl', ' pv-sl', 'pv-sl ',
      'pv-sl\n', 't-1-sl', 't1.5-sl', 't1e3-sl', 'tpv-sl']) + (R.chance(0.3) ? randText(R, 2) : '');
    const k = parseLineKey(s);
    expect(k === null || (KEY.test(s) && roles.includes(k.role) && Number.isInteger(k.ticket) && k.ticket >= 0),
      'keys: only a line key is read as one: ' + JSON.stringify(s) + ' -> ' + JSON.stringify(k));
    const ticket = R.int(1, 2 ** 31) * R.int(1, 2 ** 21);
    const role = R.pick(roles);
    const back = parseLineKey('t' + ticket + '-' + role);
    expect(back && back.ticket === ticket && back.role === role, 'keys: t' + ticket + '-' + role + ' reads back');
  }
}

// Lines for random previews, open trades and cards: each one is a line tv/page.js draws (its own
// valid() rules), so none silently goes missing, and each says what the panel holds.
function testLines(R, rounds, expect) {
  const money = (v, sign) => fmt.money(v, 'USD', 2, sign);
  const types = ['BUY', 'SELL', 'BUY LIMIT', 'SELL LIMIT', 'BUY STOP', 'SELL STOP', 'BUY STOP LIMIT'];
  const px = () => R.int(1, 99999999) / Math.pow(10, R.int(0, 5));
  for (let i = 0; i < rounds; i++) {
    const trades = Array.from({ length: R.int(0, 4) }, () => {
      const order = R.chance(0.4);
      return { ticket: R.int(1, 2 ** 31) * R.int(1, 2 ** 20), kind: order ? 'order' : 'position', type: R.pick(types), side: R.pick([1, -1]),
        lots: R.int(1, 10000) / 100, open: px(), sl: R.chance(0.7) ? px() : 0, tp: R.chance(0.7) ? px() : 0, profit: (R.next() - 0.5) * 1e6, locked: order && R.chance(0.1) };
    });
    const preview = R.chance(0.6) ? { pending: R.chance(0.4), type: R.pick(types), entry: px(), sl: R.chance(0.8) ? px() : 0, tp: R.chance(0.8) ? px() : 0,
      lots: R.int(0, 100000) / 100, riskMoney: R.next() * 1e6, riskPct: R.next() * 100, rewardMoney: R.next() * 1e6, rr: R.next() * 20 } : null;
    const x = trades.length && R.chance(0.5) ? R.pick(trades) : null;
    const card = x ? { ticket: x.ticket, open: R.chance(0.7) ? px() : NaN, sl: R.chance(0.7) ? px() : NaN, tp: R.chance(0.7) ? px() : NaN, type: R.chance(0.2) ? R.pick(types) : '' } : null;
    const lines = wantedLines({ preview, trades, card, volStep: R.pick([0.01, 0.1, 1, 0.001]), money });
    const keys = new Set();
    for (const l of lines) {
      expect(KEY.test(l.key) && ['entry', 'sl', 'tp'].includes(l.role) && Number.isFinite(l.price) && l.price > 0 && typeof l.text === 'string' &&
        l.text.length <= 80 && typeof l.qty === 'string' && l.qty.length <= 20, 'lines: tv/page.js draws every line the panel asks for: ' + JSON.stringify(l));
      expect(!keys.has(l.key), 'lines: one line per key: ' + l.key);
      keys.add(l.key);
      const k = parseLineKey(l.key);
      if (k && k.ticket) {
        const t = trades.find((y) => y.ticket === k.ticket);
        expect(t && (k.role !== 'entry' || l.editable === (t.kind === 'order' && !t.locked)) && (!t.locked || !l.editable),
          "lines: a trade's line is draggable only where MT5 lets it change: " + JSON.stringify(l));
      }
    }
  }
}

// TradingView's page in a sandbox: a window whose message listeners the test calls with whatever a
// script on the page could post, and the panel's runtime messages. Inside the sandbox `window` is
// its global object (`page`), which is what a message from the page itself carries as its source.
function pageSandbox() {
  const listeners = [];
  const posted = [];
  const win = {
    location: { origin: 'https://www.tradingview.com' },
    addEventListener: (type, fn) => {
      if (type === 'message') listeners.push(fn);
    },
    postMessage: (data, origin) => posted.push({ data: structuredClone(data), origin }),
    setInterval: () => 0,
  };
  win.window = win;
  const ctx = vm.createContext(win);
  const run = (code) => vm.runInContext(code, ctx);
  return { win, page: run('globalThis'), run, listeners, posted };
}

async function testBridgeScript(R, rounds, expect) {
  const code = fs.readFileSync(new URL('../../extension/tv/bridge.js', import.meta.url), 'utf8');
  const sb = pageSandbox();
  const sent = [];
  let onRuntime = null;
  sb.win.chrome = {
    runtime: {
      id: 'ours',
      onMessage: { addListener: (fn) => (onRuntime = fn) },
      sendMessage: (m) => {
        sent.push(structuredClone(m));
        return Promise.resolve();
      },
    },
  };
  sb.run(code);
  sb.run(code);   // put in twice (the panel does when a send fails): one listener
  expect(sb.listeners.length === 1 && onRuntime, 'bridge.js: listens once, however often it is put in');
  const other = { postMessage() {} };
  let real = 0;
  for (let i = 0; i < rounds; i++) {
    const keyish = R.pick(['pv-sl', 'pv-tp', 'pv-entry', 't4327679330-sl', 't1-entry', 'pv-sl ', 'pv-xx', 't-sl', 'pv-sl\u0000', randText(R, 5),
      't' + '1'.repeat(25) + '-tp']);
    const priceish = R.pick([2650.5, 0, -1, NaN, Infinity, -Infinity, 1e308, '2650.5', '1e3', '', null, true, [2650], { valueOf: 1 }, 1e-300, Number.MAX_VALUE]);
    let data = R.pick([
      { actionInna: 'moved', key: keyish, price: priceish },
      { actionInna: 'moved', key: keyish, price: priceish, t: 'ai-lines', lines: [] },
      { actionInna: 'lines', lines: [{ key: 'pv-sl', price: 1 }] },
      { actionInna: 'Moved', key: 'pv-sl', price: 1 },
      { t: 'ai-moved', key: 'pv-sl', price: 1 },
      'moved', null, 42, [1, 2],
      { actionInna: 'moved', key: { toString: 'pv-sl' }, price: 5 },
      { actionInna: 'moved', key: ['pv-sl'], price: 5 },
    ]);
    try {
      data = structuredClone(data);
    } catch (e) {
      data = null;
    }
    const fromPage = R.chance(0.8);
    const before = sent.length;
    try {
      sb.listeners[0]({ source: fromPage ? sb.page : other, data, origin: R.pick(['https://www.tradingview.com', 'https://evil.com', 'null']) });
    } catch (e) {
      expect(false, 'bridge.js: a message from the page never throws: ' + e.message);
    }
    for (const m of sent.slice(before)) {
      real++;
      expect(m.t === 'ai-moved' && Object.keys(m).length === 3 && KEY.test(m.key) && typeof m.price === 'number' && Number.isFinite(m.price) && m.price > 0,
        'bridge.js: only a line key and a price reach the panel: ' + JSON.stringify(m));
      expect(fromPage, 'bridge.js: only from the page itself, not another frame');
    }
    expect(sent.length - before <= 1, 'bridge.js: one message at most per drag');

    // the panel's lines, and messages that claim to be from elsewhere
    const beforePost = sb.posted.length;
    const sender = { id: R.pick(['ours', 'ours', 'other-extension', undefined, '']) };
    const msg = structuredClone(R.pick([{ t: 'ai-lines', lines: [] }, { t: 'ai-lines', lines: 'x' }, { t: 'ai-lines' }, { t: 'other', lines: [] }, null]));
    let replied = false;
    onRuntime(msg, sender, () => (replied = true));
    const shouldPass = sender.id === 'ours' && msg && msg.t === 'ai-lines' && Array.isArray(msg.lines);
    expect((sb.posted.length - beforePost === 1) === !!shouldPass && replied === !!shouldPass,
      'bridge.js: lines pass to the page only from this extension: ' + JSON.stringify([sender, msg]));
    for (const p of sb.posted.slice(beforePost)) expect(p.origin === 'https://www.tradingview.com', 'bridge.js: posted to its own page only');
  }
  expect(real > 0, 'bridge.js: the fuzz made real drags too (' + real + ')');
}

async function testPageScript(R, rounds, expect) {
  const code = fs.readFileSync(new URL('../../extension/tv/page.js', import.meta.url), 'utf8');
  const sb = pageSandbox();
  const calls = [];
  const live = new Set();
  let made = 0;
  const lineObj = () => {
    const id = ++made;
    let price = 0;
    let onMove = null;
    const rec = (m) => (...a) => {
      calls.push({ id, m, a });
      return obj;
    };
    const obj = {
      setCancellable: rec('setCancellable'), setText: rec('setText'), setQuantity: rec('setQuantity'), setLineColor: rec('setLineColor'),
      setBodyBorderColor: rec('setBodyBorderColor'), setBodyTextColor: rec('setBodyTextColor'), setQuantityBackgroundColor: rec('setQuantityBackgroundColor'),
      setQuantityBorderColor: rec('setQuantityBorderColor'), setLineStyle: rec('setLineStyle'), setEditable: rec('setEditable'),
      setPrice: (p) => {
        calls.push({ id, m: 'setPrice', a: [p] });
        price = p;
        return obj;
      },
      getPrice: () => price,
      onMove: (fn) => (onMove = fn),
      remove: () => {
        calls.push({ id, m: 'remove', a: [] });
        live.delete(obj);
      },
      drag: (p) => {
        price = p;
        if (onMove) onMove();
      },
    };
    live.add(obj);
    return obj;
  };
  sb.win.TradingViewApi = { activeChart: () => ({ createOrderLine: async () => lineObj() }) };
  sb.run(code);
  expect(sb.win.__actionInnaChart === true, 'page.js: leaves no line data on the page');
  const COLORS = new Set(['rgb(120,123,134)', 'rgb(200,48,62)', 'rgb(22,124,74)']);
  const flush = () => new Promise((r) => setImmediate(r));
  for (let i = 0; i < rounds; i++) {
    const lines = Array.from({ length: R.int(0, 6) }, () => ({
      key: R.pick(['pv-entry', 'pv-sl', 'pv-tp', 't1-sl', 't2-tp', 't3-entry', 'pv-xx', 'x', '__proto__', 't' + '1'.repeat(22) + '-sl']),
      role: R.pick(['entry', 'sl', 'tp', 'sl', 'constructor', '']),
      price: R.pick([1.08, 2650.5, 0, -1, NaN, Infinity, '1.08', 42]),
      text: R.pick(['SL -$100.00', 'TP', '', 'x'.repeat(81), 5, '<img src=x onerror=alert(1)>']),
      qty: R.pick(['0.20', '', 'y'.repeat(21), 0.2]),
      editable: R.chance(0.5),
      trade: R.chance(0.5),
      unsent: R.chance(0.2),
    }));
    const valid = lines.filter((l) => KEY.test(l.key) && ['entry', 'sl', 'tp'].includes(l.role) && typeof l.price === 'number' && Number.isFinite(l.price) &&
      l.price > 0 && typeof l.text === 'string' && l.text.length <= 80 && typeof l.qty === 'string' && l.qty.length <= 20);
    const want = new Map(valid.map((l) => [l.key, l]));
    const from = R.chance(0.9) ? sb.page : { other: true };
    const tag = R.chance(0.95) ? 'lines' : 'line';
    const start = calls.length;
    sb.listeners[0]({ source: from, data: structuredClone({ actionInna: tag, lines }) });
    await flush();
    await flush();
    const mine = calls.slice(start);
    for (const c of mine) {
      if (c.m === 'setText') expect(typeof c.a[0] === 'string' && c.a[0].length <= 80, 'page.js: a text the panel sent, short: ' + JSON.stringify(c.a));
      if (c.m === 'setQuantity') expect(typeof c.a[0] === 'string' && c.a[0].length <= 20, 'page.js: a quantity the panel sent: ' + JSON.stringify(c.a));
      if (c.m === 'setPrice') expect(typeof c.a[0] === 'number' && Number.isFinite(c.a[0]) && c.a[0] > 0, 'page.js: a price above 0: ' + JSON.stringify(c.a));
      if (c.m.endsWith('Color')) expect(COLORS.has(c.a[0]), 'page.js: one of its own colours: ' + c.a[0]);
    }
    if (from === sb.page && tag === 'lines') {
      expect(live.size === want.size, 'page.js: draws exactly the valid lines sent (' + live.size + ' drawn, ' + want.size + ' sent)');
    } else expect(mine.length === 0, 'page.js: a message from another frame, or not tagged as lines, draws nothing');

    // a drag on one of the drawn lines tells the panel its key and price, nothing else
    if (live.size && R.chance(0.3)) {
      const obj = [...live][R.int(0, live.size - 1)];
      const before = sb.posted.length;
      obj.drag(R.pick([2651.25, 0, -3, NaN]));
      for (const p of sb.posted.slice(before)) {
        expect(p.origin === 'https://www.tradingview.com' && p.data.actionInna === 'moved' && KEY.test(p.data.key) && p.data.price > 0 &&
          Object.keys(p.data).length === 3, 'page.js: a drag posts a key and a price above 0: ' + JSON.stringify(p));
      }
    }
  }
}

// Messages no link should send: the connection never throws, a request only takes a reply with its
// own id, and handlers only get objects.
async function testLinkMessages(R, rounds, expect) {
  let port;
  const link = new Link(() => {
    port = { listeners: [], onMessage: { addListener: (fn) => port.listeners.push(fn) }, onDisconnect: { addListener() {} }, postMessage() {} };
    return port;
  }, () => '', { replyMs: 100000, retryMs: 100000 });
  const seen = [];
  link.on('*', (m) => seen.push(m));
  link.start();
  const waiting = new Map();
  for (let i = 0; i < 50; i++) {
    const p = link.request('preview', {}, '1');
    const id = link.nextId - 1;
    waiting.set(id, { got: null });
    p.then((r) => (waiting.get(id).got = r));
  }
  for (let i = 0; i < rounds; i++) {
    const ids = [...waiting.keys()];
    const id = R.chance(0.3) ? R.pick(ids) : R.pick([String(R.pick(ids)), R.pick(ids) + 0.5, -1, 0, null, undefined, '__proto__', NaN, [R.pick(ids)]]);
    let m = R.pick([{ t: 'reply', id, ok: R.chance(0.5) }, { t: R.pick(['quote', 'trades', '__proto__', 'constructor', '*', '']), id }, 'text', 42, null, [1],
      { t: 'reply' }]);
    m = structuredClone(m);
    try {
      port.listeners.forEach((fn) => fn(m));
    } catch (e) {
      expect(false, 'link: a message never throws: ' + e.message);
    }
    await null;
  }
  await new Promise((r) => setImmediate(r));
  for (const [id, w] of waiting) {
    if (w.got) expect(w.got.t === 'reply' && w.got.id === id, 'link: a request took only its own reply: ' + id + ' got ' + JSON.stringify(w.got));
  }
  expect(seen.every((m) => m && typeof m === 'object'), 'link: handlers only get objects');
  expect([...waiting.values()].some((w) => w.got), 'link: some replies were real');
  clearTimeout(link.retry);
  for (const p of link.pending.values()) clearTimeout(p.timer);
}

export async function fuzz(expect, seed = 20261026, scale = 1) {
  const R = prng(seed);
  let n = 0;
  const count = (ok, what) => {
    n++;
    expect(ok, what + ' (seed ' + seed + ')');
  };
  testTabs(R, 60000 * scale, count);
  testLevels(R, 60000 * scale, count);
  testKeys(R, 30000 * scale, count);
  testLines(R, 15000 * scale, count);
  await testBridgeScript(R, 40000 * scale, count);
  await testPageScript(R, 6000 * scale, count);
  await testLinkMessages(R, 30000 * scale, count);
  return n;
}
