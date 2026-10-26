// Tests for the side panel's libraries (extension/lib): numbers as the panel writes and reads them,
// the TradingView symbol read from a tab, and the link connection's requests and replies, played
// against a stand-in port.
//   node tests/extension/run.mjs
import * as fmt from '../../extension/lib/format.js';
import { tickerFromTab } from '../../extension/lib/tv.js';
import { Link, explainLinkError } from '../../extension/lib/link.js';

let pass = 0;
let fail = 0;
function expect(ok, what) {
  if (ok) {
    pass++;
    return;
  }
  fail++;
  console.log('FAIL ' + what);
}
function same(got, want, what) {
  const show = (v) => (Number.isNaN(v) ? 'NaN' : JSON.stringify(v));
  expect(Object.is(got, want), what + ': got ' + show(got) + ', want ' + show(want));
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

//--- numbers ---------------------------------------------------------------------
function testFormat() {
  same(fmt.group(12345.6, 2), '12,345.60', 'thousands separators');
  same(fmt.group(999.999, 2), '1,000.00', 'rounding up past a thousand');
  same(fmt.group(7, 0), '7', 'no decimals');
  same(fmt.money(1234.5, 'USD'), '$1,234.50', 'dollars');
  same(fmt.money(-1234.5, 'USD'), '-$1,234.50', 'a loss');
  same(fmt.money(12.4, 'USD', 2, true), '+$12.40', 'a gain with its sign');
  same(fmt.money(0, 'USD', 2, true), '$0.00', 'zero has no sign');
  same(fmt.money(-0.004, 'USD'), '$0.00', 'a loss that rounds to zero has no minus');
  same(fmt.money(-45.87, 'EUR'), '-45.87 EUR', 'another currency goes after the number');
  same(fmt.money(1500, 'JPY', 0), '1,500 JPY', 'a currency without decimals');
  same(fmt.money(12.5, 'USC'), '12.50 USC', 'a cent account');
  same(fmt.money(NaN, 'USD'), '-', 'no value');
  same(fmt.trimZeros('2.500'), '2.5', 'trailing zeros go');
  same(fmt.trimZeros('2.000'), '2', 'and the dot with them');
  same(fmt.trimZeros('200'), '200', 'a whole number keeps its zeros');
  same(fmt.stepDigits(0.01), 2, 'lot step 0.01');
  same(fmt.stepDigits(0.25), 2, 'step 0.25');
  same(fmt.stepDigits(0.1), 1, 'step 0.1');
  same(fmt.stepDigits(1), 0, 'step 1');
  same(fmt.stepDigits(0.001), 3, 'step 0.001');
  same(fmt.stepDigits(0), 2, 'no step: 2 decimals');
  same(fmt.price(2650.1, 3), '2650.100', 'a price with the symbol digits');
  same(fmt.price(1.08, 5), '1.08000', 'five digits');
  same(fmt.price(0, 3), '-', 'no price');
  same(fmt.pips(1.6), '1.6', 'pips with one decimal');
  same(fmt.pips(20), '20', 'whole pips');
  same(fmt.pips(NaN), '-', 'no pips');
  same(fmt.lots(0.2, 0.01), '0.20', 'lots with the step decimals');
  same(fmt.lots(3, 1), '3', 'whole lots');
  same(fmt.pct(1.25), '1.25%', 'percent');
  same(fmt.pct(-0.5, true), '-0.50%', 'a negative percent');
  same(fmt.pct(0.5, true), '+0.50%', 'a positive percent with its sign');
  same(fmt.pct(0.004, true), '0.00%', 'a percent that rounds to zero');

  same(fmt.parseNumber('1,5'), 1.5, 'a decimal comma');
  same(fmt.parseNumber(' 25 '), 25, 'spaces');
  same(fmt.parseNumber('2%'), 2, 'a percent sign');
  same(fmt.parseNumber('$100'), 100, 'a dollar sign');
  same(fmt.parseNumber('.5'), 0.5, 'no leading zero');
  same(fmt.parseNumber('5.'), 5, 'a trailing dot');
  same(fmt.parseNumber('-1'), -1, 'a minus');
  same(fmt.parseNumber('abc'), NaN, 'letters');
  same(fmt.parseNumber(''), NaN, 'nothing');
  same(fmt.parseNumber('1.2.3'), NaN, 'two dots');
  same(fmt.parseNumber('2,650.50'), NaN, 'a thousands separator is not guessed at');
  same(fmt.parseNumber('1e3'), NaN, 'no exponents');
  same(fmt.parseNumber(null), NaN, 'null');

  same(fmt.parseLevel(''), 0, 'an empty level is none');
  same(fmt.parseLevel('   '), 0, 'spaces are none too');
  same(fmt.parseLevel(undefined), 0, 'so is a missing one');
  same(fmt.parseLevel('2650.5'), 2650.5, 'a price');
  same(fmt.parseLevel('2650,5'), 2650.5, 'a price with a decimal comma');
  same(fmt.parseLevel('50'), 50, 'pips');
  same(fmt.parseLevel('26a0'), NaN, 'a typo is not "none"');
  same(fmt.parseLevel('0'), NaN, 'zero is not a level');
  same(fmt.parseLevel('-5'), NaN, 'nor is a negative');
}

//--- TradingView tabs ---------------------------------------------------------------
function testTradingView() {
  const t = tickerFromTab;
  same(t('https://www.tradingview.com/chart/abc/?symbol=OANDA%3AXAUUSD', ''), 'OANDA:XAUUSD', 'a chart with the symbol in its address');
  same(t('https://tradingview.com/chart/?symbol=FX:EURUSD', ''), 'FX:EURUSD', 'without www');
  same(t('https://in.tradingview.com/chart/x/?symbol=NSE%3ANIFTY', ''), 'NSE:NIFTY', "a country's site");
  same(t('https://www.tradingview.com/chart/abc/?symbol=CME_MINI%3AES1%21', ''), 'CME_MINI:ES1!', 'a continuous future');
  same(t('https://www.tradingview.com/symbols/OANDA-XAUUSD/', ''), 'OANDA:XAUUSD', 'a symbol page');
  same(t('https://www.tradingview.com/symbols/XAUUSD/', ''), 'XAUUSD', 'a symbol page without an exchange');
  same(t('https://www.tradingview.com/chart/abc/', 'XAUUSD 2,650.12 ▲ +0.45% Unnamed'), 'XAUUSD', "a chart's title");
  same(t('https://www.tradingview.com/chart/abc/', 'OANDA:XAUUSD 2,650.12 ▲ +0.45%'), 'OANDA:XAUUSD', 'a title with the exchange');
  same(t('https://www.tradingview.com/chart/abc/', 'Unnamed'), '', 'a title without a symbol');
  same(t('https://www.tradingview.com/', 'TradingView — Track All Markets'), '', 'the home page');
  same(t('https://www.tradingview.com/chart/abc/?symbol=%3Cscript%3E', ''), '', 'a symbol with characters no ticker has');
  same(t('https://www.tradingview.com.example.net/chart/?symbol=XAUUSD', ''), '', 'a lookalike host');
  same(t('https://nottradingview.com/chart/?symbol=XAUUSD', ''), '', 'a site whose name ends the same');
  same(t('http://localhost/chart?symbol=XAUUSD', ''), '', 'not TradingView');
  same(t('not an address', 'XAUUSD 1'), '', 'not an address');
}

//--- the link connection -------------------------------------------------------------
function fakePort() {
  const p = {
    sent: [],
    listeners: [],
    goneListeners: [],
    open: true,
    onMessage: { addListener: (fn) => p.listeners.push(fn) },
    onDisconnect: { addListener: (fn) => p.goneListeners.push(fn) },
    postMessage(m) {
      if (!p.open) throw new Error('Attempting to use a disconnected port object');
      p.sent.push(m);
    },
    say(m) {
      p.listeners.forEach((fn) => fn(m));
    },
    drop() {
      p.open = false;
      p.goneListeners.forEach((fn) => fn());
    },
  };
  return p;
}

async function testLink() {
  const ports = [];
  const link = new Link(() => {
    const p = fakePort();
    ports.push(p);
    return p;
  }, () => '', { replyMs: 150, retryMs: 50 });
  const opened = [];
  const quotes = [];
  const stops = [];
  const types = [];
  link.on('link-open', () => opened.push(1));
  link.on('quote', (m) => quotes.push(m));
  link.on('link-stopped', (m) => stops.push(m.error));
  link.on('*', (m) => types.push(m.t));
  link.start();
  expect(link.connected && opened.length === 1, 'start opens the port');

  const a = link.request('watch', { symbol: 'XAUUSD' }, '1');
  const b = link.request('symbols', { ticker: 'EURUSD' }, '2');
  const [ma, mb] = ports[0].sent;
  expect(ma.t === 'watch' && ma.term === '1' && ma.symbol === 'XAUUSD' && ma.id > 0, 'a request carries its type, terminal, id and fields');
  expect(mb.t === 'symbols' && mb.term === '2' && mb.id !== ma.id, 'each request has its own id');
  ports[0].say({ t: 'quote', term: '1', symbol: 'XAUUSD', bid: 1, ask: 2 });
  ports[0].say({ t: 'reply', id: mb.id, ok: true, term: '2', pick: 'EURUSDm' });
  ports[0].say({ t: 'reply', id: ma.id, ok: true, term: '1', spec: { digits: 3 } });
  const ra = await a;
  const rb = await b;
  expect(ra.ok && ra.spec.digits === 3 && rb.ok && rb.pick === 'EURUSDm', 'replies find their requests, in any order');
  expect(quotes.length === 1 && types.includes('quote') && !types.includes('reply'), 'other messages go to their handlers, replies to their request');
  const heard = types.length;
  ports[0].say('not an object');
  ports[0].say(null);
  expect(types.length === heard, 'anything that is not a message is dropped');

  const c = link.request('send', { preview: 'p1' }, '1');
  const rc = await c;
  expect(!rc.ok && rc.lost && rc.err === 'MT5 did not answer', 'no answer in time: lost, since MT5 may have carried it out');
  const lateId = ports[0].sent[2].id;
  const d = link.request('watch', { symbol: 'XAUUSD' }, '1');
  ports[0].say({ t: 'reply', id: lateId, ok: true });
  ports[0].say({ t: 'reply', id: ports[0].sent[3].id, ok: true, spec: {} });
  const rd = await d;
  expect(rd.ok && rd.spec, 'a late reply is not taken for another request');

  const e1 = link.request('send', { preview: 'p2' }, '1');
  const e2 = link.request('watch', { symbol: 'EURUSD' }, '2');
  link.abandon('1', 'MT5 stopped serving the panel before it answered');
  const re1 = await e1;
  expect(!re1.ok && re1.lost && /before it answered/.test(re1.err), "a terminal that went away: its requests are lost");
  ports[0].say({ t: 'reply', id: ports[0].sent[5].id, ok: true, spec: {} });
  const re2 = await e2;
  expect(re2.ok, "another terminal's request still gets its reply");

  const f = link.request('close', { preview: 'p3' }, '1');
  ports[0].drop();
  const rf = await f;
  expect(!rf.ok && rf.lost && /link stopped/.test(rf.err), 'the link stops: requests on their way are lost');
  expect(!link.connected && stops.length === 1 && stops[0] === '', 'and the panel hears it');
  const g = await link.request('watch', {}, '1');
  expect(!g.ok && !g.lost && g.err === 'The link is not running', 'while it is down nothing is sent, and the reply says so');
  expect(!link.post({ t: 'link.start' }), 'nor is a message without a reply');
  await sleep(120);
  expect(ports.length === 2 && link.connected && opened.length === 2, 'it starts again by itself');

  ports[1].open = false;
  const h = await link.request('send', { preview: 'p4' }, '1');
  expect(!h.ok && !h.lost, 'a request that could not be handed to the link was not sent');

  let tries = 0;
  const missing = new Link(() => {
    tries++;
    throw new Error('Specified native messaging host not found.');
  }, () => '', { retryMs: 30 });
  const why = [];
  missing.on('link-stopped', (m) => why.push(m.error));
  missing.start();
  await sleep(100);
  clearTimeout(missing.retry);
  expect(tries >= 2 && why.length === tries && /not found/.test(why[0]), 'a link that is not installed: it keeps trying');
}

function testExplain() {
  same(explainLinkError('Specified native messaging host not found.'), 'The ActionInna link is not installed: run ActionInnaLink.exe --install', 'not installed');
  same(explainLinkError('Access to the specified native messaging host is forbidden.'),
    'The ActionInna link does not know this extension. Run ActionInnaLink.exe --install again', 'another extension id');
  same(explainLinkError('Native host has exited.'), 'The ActionInna link stopped. Trying again', 'the link exited');
  same(explainLinkError(''), 'The ActionInna link stopped. Trying again', 'no reason given');
  same(explainLinkError('Error when communicating with the native messaging host.'),
    'The link stopped (Error when communicating with the native messaging host). Trying again', "Chrome's words otherwise");
}

testFormat();
testTradingView();
await testLink();
testExplain();
console.log('extension tests: ' + pass + ' checks, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
