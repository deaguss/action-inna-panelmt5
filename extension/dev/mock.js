// A stand-in for the link and MT5, for working on the panel as a plain web page
// (node tests/extension/serve.js, then http://127.0.0.1:8137/panel.html). It speaks
// docs/protocol.md with made-up prices and simple math: the real numbers and rules are the EA's.
// The published extension leaves this folder out.
//
// The address picks a scene:
//   ?scene=nolink  the link is not installed
//   ?scene=nomt5   no MT5 runs until Start MT5 is pressed
//   ?scene=noea    MT5 runs, but no chart serves the panel
//   ?terms=2       a second MT5 is connected too (a EUR netting account)
// In the console, actioninnaMock pokes it:
//   actioninnaMock.gone('1')    that MT5 stops serving the panel; .back('1') brings it back
//   actioninnaMock.problem('1', 'Turn on Algo Trading (toolbar button) to send orders')
//   actioninnaMock.slip = 3     the next market fill is 3 pips worse (-3: better; null: now and then)
//   actioninnaMock.dropReply = 'send'   the next send is carried out, but its reply never comes
//   actioninnaMock.stopLink()   the link exits; the panel starts it again
//   actioninnaMock.last         the last request the panel sent

const LAG_MS = 25;
const params = new URLSearchParams(location.search);
const scene = params.get('scene') || '';

const SPECS = {
  XAUUSDm: { market: 'XAUUSD', description: 'Gold vs US Dollar', digits: 3, pipSize: 0.1, contractSize: 100, volMin: 0.01, volMax: 200, volStep: 0.01, base: 'XAU', profit: 'USD', mid: 2650, spread: 0.16, move: 0.06 },
  EURUSDm: { market: 'EURUSD', description: 'Euro vs US Dollar', digits: 5, pipSize: 0.0001, contractSize: 100000, volMin: 0.01, volMax: 200, volStep: 0.01, base: 'EUR', profit: 'USD', mid: 1.09, spread: 0.00008, move: 0.00002 },
  GBPUSDm: { market: 'GBPUSD', description: 'Great Britain Pound vs US Dollar', digits: 5, pipSize: 0.0001, contractSize: 100000, volMin: 0.01, volMax: 200, volStep: 0.01, base: 'GBP', profit: 'USD', mid: 1.295, spread: 0.0001, move: 0.00002 },
  USDJPYm: { market: 'USDJPY', description: 'US Dollar vs Japanese Yen', digits: 3, pipSize: 0.01, contractSize: 100000, volMin: 0.01, volMax: 200, volStep: 0.01, base: 'USD', profit: 'JPY', mid: 151.2, spread: 0.012, move: 0.003 },
  US30m: { market: 'US30', description: 'US Wall Street 30 Index', digits: 1, pipSize: 1, contractSize: 1, volMin: 0.1, volMax: 100, volStep: 0.1, base: '', profit: 'USD', mid: 42150, spread: 2, move: 1.2 },
  DJ30m: { market: 'US30', description: 'Dow Jones Industrial Average Cash', digits: 1, pipSize: 1, contractSize: 1, volMin: 0.1, volMax: 100, volStep: 0.1, base: '', profit: 'USD', mid: 42153, spread: 2.4, move: 1.2 },
};
const OTHER_NAMES = { GOLD: 'XAUUSD', DJI: 'US30', DJ30: 'US30', WS30: 'US30', YM1: 'US30' };
const SETTINGS = {
  presets: [1, 1.5, 2], riskBase: 'equity', maxRiskPct: 5, commissionRT: 0, requireSL: true, requireTP: true,
  pipMode: 'trader', defaultSLPips: 20, defaultTPMode: 'r', defaultTPValue: 2, pendingOffsetPips: 10, slipPolicy: 'follow',
};

function round(v, d) {
  return Number(Number(v).toFixed(d));
}

//--- prices: a random walk that stays near where it started -------------------------
const PRICES = {};
for (const [name, s] of Object.entries(SPECS)) PRICES[name] = { mid: s.mid, bid: 0, ask: 0 };

function setQuote(name) {
  const s = SPECS[name];
  const p = PRICES[name];
  p.bid = round(p.mid - s.spread / 2, s.digits);
  p.ask = round(p.bid + s.spread, s.digits);
}

function walk() {
  for (const [name, s] of Object.entries(SPECS)) {
    if (Math.random() < 0.4) continue;
    const p = PRICES[name];
    p.mid += (Math.random() - 0.5) * 2 * s.move + (s.mid - p.mid) * 0.01;
    setQuote(name);
  }
}
Object.keys(SPECS).forEach(setQuote);

// The profit currency's worth of a 1.0 move for one lot, in USD.
function usdPerUnit(s) {
  return s.profit === 'JPY' ? s.contractSize / PRICES.USDJPYm.mid : s.contractSize;
}

//--- one MT5 terminal with its account -----------------------------------------------
class Terminal {
  constructor(id, acct, trades, memory) {
    this.id = id;
    this.acct = acct;
    this.balance = acct.balance;
    this.problem = '';
    this.trades = trades;
    this.memory = memory;     // symbol -> SL/TP records, newest first
    this.picks = {};
    this.previews = new Map();
    this.nextPreview = 1;
    this.nextTicket = acct.firstTicket;
    this.watch = '';
    this.sentQuote = '';
    this.serving = false;
    this.tradeTimer = null;
  }

  emit(m) {
    if (this.serving) deliver(Object.assign(m, { term: this.id }));
  }

  toAcct(usd) {
    return this.acct.currency === 'EUR' ? usd / PRICES.EURUSDm.mid : usd;
  }

  perPip(s) {
    return this.toAcct(usdPerUnit(s) * s.pipSize);
  }

  marginFor(s, lots, price) {
    const notional = s.base === 'USD' ? lots * s.contractSize : lots * s.contractSize * price;
    return this.toAcct(notional / 100);
  }

  revalue() {
    for (const x of this.trades) {
      if (x.kind !== 'position') continue;
      const s = SPECS[x.symbol];
      const q = PRICES[x.symbol];
      const close = x.side > 0 ? q.bid : q.ask;
      x.profit = round(this.toAcct((close - x.open) * x.side * x.lots * usdPerUnit(s)), 2);
    }
  }

  equity() {
    this.revalue();
    return this.trades.reduce((sum, x) => sum + (x.kind === 'position' ? x.profit : 0), this.balance);
  }

  margin() {
    return this.trades.reduce((sum, x) => sum + (x.kind === 'position' ? this.marginFor(SPECS[x.symbol], x.lots, x.open) : 0), 0);
  }

  freeMargin() {
    return this.equity() - this.margin();
  }

  info() {
    const a = this.acct;
    return {
      t: 'terminal', ver: 1, login: a.login, server: a.server, company: a.company, currency: a.currency,
      currencyDigits: 2, tradeMode: 'demo', marginMode: a.marginMode, hedgeAllowed: a.marginMode === 'hedging', fifo: false,
      connected: true, problem: this.problem, settings: SETTINGS,
    };
  }

  tradesMsg() {
    return {
      t: 'trades', balance: round(this.balance, 2), equity: round(this.equity(), 2), margin: round(this.margin(), 2),
      freeMargin: round(this.freeMargin(), 2), list: this.trades.map((x) => Object.assign({}, x)),
    };
  }

  changed() {
    clearTimeout(this.tradeTimer);
    this.tradeTimer = setTimeout(() => this.emit(this.tradesMsg()), 60);
  }

  find(ticket) {
    return this.trades.find((x) => x.ticket === ticket) || null;
  }

  addPreview(kind, fields) {
    const id = 'p' + this.nextPreview++;
    const now = Date.now();
    for (const [k, pv] of this.previews) if (now - pv.at > 120000) this.previews.delete(k);
    this.previews.set(id, Object.assign({ kind, at: now, used: false }, fields));
    return id;
  }

  // The preview a confirm names, used up; or why it can't be used (Bridge.mqh UsePreview).
  usePreview(id, kind) {
    const pv = this.previews.get(id);
    if (!pv || pv.kind !== kind) return 'Unknown preview. Preview again';
    if (pv.used) return 'This preview was already confirmed. Preview again';
    if (Date.now() - pv.at > 60000) return 'The preview is more than a minute old. Preview again';
    pv.used = true;
    return pv;
  }

  request(m) {
    const fn = HANDLERS[m.t];
    let r;
    try {
      r = fn ? fn.call(this, m) : { ok: false, err: 'Unknown request ' + m.t };
    } catch (e) {
      r = { ok: false, err: String((e && e.message) || e) };
    }
    if (mock.dropReply === m.t) {
      mock.dropReply = '';
      return;
    }
    this.emit(Object.assign({ t: 'reply', id: m.id }, r.ok === false ? r : Object.assign({ ok: true }, r)));
  }

  // A new order's plan: AiBuildPlan's checks in their order, with simpler money.
  plan(m) {
    const s = SPECS[m.symbol];
    if (!s) return { ok: false, err: 'Unknown symbol ' + m.symbol };
    const side = m.side === 'buy' ? 1 : m.side === 'sell' ? -1 : 0;
    if (!side) return { ok: false, err: 'side must be "buy" or "sell"' };
    const q = PRICES[m.symbol];
    const pip = s.pipSize;
    const problems = [];
    const p = {
      valid: false, err: '', warn: '', type: side > 0 ? 'BUY' : 'SELL', entry: 0, sl: 0, tp: 0, lots: 0, riskMoney: 0,
      riskPct: 0, rewardMoney: 0, rewardPct: 0, rr: 0, slPips: 0, tpPips: 0, pipValue: 0, margin: 0, freeAfter: 0,
      commission: 0, spreadPips: round((q.ask - q.bid) / pip, 1), bid: q.bid, ask: q.ask,
    };
    const entry = m.pending ? round(Number(m.entry) || 0, s.digits) : side > 0 ? q.ask : q.bid;
    p.entry = entry;
    if (m.pending) {
      if (!(entry > 0)) problems.push('Type the entry price');
      else p.type = side > 0 ? (entry < q.ask ? 'BUY LIMIT' : 'BUY STOP') : (entry > q.bid ? 'SELL LIMIT' : 'SELL STOP');
    }
    const slv = Number(m.slValue) || 0;
    const tpv = Number(m.tpValue) || 0;
    if (slv > 0) p.sl = round(m.slMode === 'price' ? slv : entry - side * slv * pip, s.digits);
    const slDist = p.sl > 0 ? (entry - p.sl) * side : 0;
    if (!(p.sl > 0)) problems.push('Set a stop loss');
    else if (slDist <= 0) problems.push('The stop loss must be ' + (side > 0 ? 'below' : 'above') + ' the entry');
    if (tpv > 0) {
      if (m.tpMode === 'price') p.tp = round(tpv, s.digits);
      else if (m.tpMode === 'pips') p.tp = round(entry + side * tpv * pip, s.digits);
      else if (slDist > 0) p.tp = round(entry + side * tpv * slDist, s.digits);
    }
    const tpDist = p.tp > 0 ? (p.tp - entry) * side : 0;
    if (!(p.tp > 0)) problems.push('Set a take profit');
    else if (tpDist <= 0) problems.push('The take profit must be ' + (side > 0 ? 'above' : 'below') + ' the entry');
    p.slPips = round(Math.max(slDist, 0) / pip, 1);
    p.tpPips = round(Math.max(tpDist, 0) / pip, 1);
    const perPip = this.perPip(s);
    const base = m.riskBase === 'balance' ? this.balance : this.equity();
    const rv = Number(m.riskValue) || 0;
    let lots = 0;
    if (!(rv > 0)) problems.push('Set the risk');
    else if (m.riskMode === 'lots') lots = rv;
    else if (p.slPips > 0) lots = (m.riskMode === 'money' ? rv : (base * rv) / 100) / (p.slPips * perPip);
    lots = Math.min(round(Math.floor(lots / s.volStep + 1e-9) * s.volStep, 6), s.volMax);
    if (rv > 0 && p.slPips > 0 && lots < s.volMin) problems.push('The risk is too small for ' + s.volMin + ' lots, the least ' + m.symbol + ' takes');
    p.lots = lots;
    p.pipValue = round(lots * perPip, 2);
    p.riskMoney = round(lots * p.slPips * perPip, 2);
    p.rewardMoney = round(lots * p.tpPips * perPip, 2);
    p.riskPct = round((p.riskMoney / base) * 100, 2);
    p.rewardPct = round((p.rewardMoney / base) * 100, 2);
    p.rr = p.slPips > 0 ? round(p.tpPips / p.slPips, 2) : 0;
    p.margin = round(this.marginFor(s, lots, entry), 2);
    p.freeAfter = round(this.freeMargin() - p.margin, 2);
    if (p.riskPct > SETTINGS.maxRiskPct + 1e-9) problems.push('Risk ' + p.riskPct.toFixed(2) + '% is above your ' + SETTINGS.maxRiskPct + '% safety cap');
    if (p.freeAfter < 0) problems.push('Not enough free margin for ' + lots + ' lots');
    p.err = problems[0] || '';
    if (!p.err && p.spreadPips > p.slPips / 4) p.warn = 'The spread (' + p.spreadPips + ' pips) is a big part of this stop';
    p.valid = !p.err;
    return { plan: p };
  }

  remember(m) {
    const list = this.memory[m.symbol] || (this.memory[m.symbol] = []);
    const rec = { slMode: m.slMode, slValue: Number(m.slValue), tpMode: m.tpMode, tpValue: Number(m.tpValue) };
    const same = list.findIndex((r) => JSON.stringify(r) === JSON.stringify(rec));
    if (same >= 0) list.splice(same, 1);
    list.unshift(rec);
    list.length = Math.min(list.length, 5);
  }

  // A market fill: a new position, or on a netting account a change to the one already there.
  open(symbol, side, lots, price, sl, tp) {
    const s = SPECS[symbol];
    const ticket = this.nextTicket++;
    const was = this.acct.marginMode === 'netting' ? this.trades.find((x) => x.kind === 'position' && x.symbol === symbol) : null;
    if (!was) {
      this.trades.push({ ticket, symbol, kind: 'position', type: side > 0 ? 'BUY' : 'SELL', side, lots, open: price, sl, tp, profit: 0, digits: s.digits, openMsc: Date.now() });
      return ticket;
    }
    const net = round(was.side * was.lots + side * lots, 6);
    if (Math.abs(net) < 1e-9) {
      this.revalue();
      this.balance += was.profit * (lots / was.lots);
      this.trades = this.trades.filter((x) => x !== was);
      return was.ticket;
    }
    if (Math.sign(net) === was.side && side === was.side) was.open = round((was.open * was.lots + price * lots) / (was.lots + lots), s.digits);
    else if (Math.sign(net) !== was.side) was.open = price;
    was.side = Math.sign(net);
    was.type = was.side > 0 ? 'BUY' : 'SELL';
    was.lots = Math.abs(net);
    was.sl = sl;
    was.tp = tp;
    return was.ticket;
  }
}

const HANDLERS = {
  symbols(m) {
    const ticker = String(m.ticker || '').toUpperCase().replace(/^.*:/, '').replace(/[^A-Z0-9.#_]/g, '');
    const market = OTHER_NAMES[ticker] || ticker;
    const candidates = Object.entries(SPECS)
      .filter(([, s]) => s.market === market)
      .map(([name, s]) => ({ name, description: s.description, visible: true }));
    let pick = this.picks[ticker] || '';
    if (!pick && candidates.length === 1) pick = candidates[0].name;
    return { ticker, pick, candidates };
  },

  pick(m) {
    if (!SPECS[m.symbol]) return { ok: false, err: 'Unknown symbol ' + m.symbol };
    this.picks[String(m.ticker || '').toUpperCase()] = m.symbol;
    return {};
  },

  watch(m) {
    const s = SPECS[m.symbol];
    if (!s) return { ok: false, err: m.symbol + ' is not in this MT5' };
    this.watch = m.symbol;
    this.sentQuote = '';
    const point = round(Math.pow(10, -s.digits), s.digits);
    return {
      spec: {
        symbol: m.symbol, digits: s.digits, point, tickSize: point, pipSize: s.pipSize, volMin: s.volMin, volMax: s.volMax,
        volStep: s.volStep, stopsLevel: 0, freezeLevel: 0, execution: 'market', tradeMode: 'full',
        orders: { market: true, limit: true, stop: true, sl: true, tp: true }, contractSize: s.contractSize, base: s.base, profit: s.profit,
      },
    };
  },

  preview(m) {
    const r = this.plan(m);
    if (r.ok === false) return r;
    return { preview: this.addPreview('order', { input: m, plan: r.plan }), plan: r.plan };
  },

  send(m) {
    const pv = this.usePreview(m.preview, 'order');
    if (typeof pv === 'string') return { ok: false, err: pv };
    if (this.problem) return { ok: false, err: this.problem };
    const now = this.plan(pv.input).plan;
    if (!now.valid) return { ok: false, err: now.err };
    if (now.riskMoney > pv.plan.riskMoney * 1.05 + 0.01) return { ok: false, err: 'The risk grew since the preview. Check it and confirm again' };
    const input = pv.input;
    const s = SPECS[input.symbol];
    const side = input.side === 'buy' ? 1 : -1;
    this.remember(input);
    if (input.pending) {
      const ticket = this.nextTicket++;
      this.trades.push({ ticket, symbol: input.symbol, kind: 'order', type: now.type, side, lots: now.lots, open: now.entry, sl: now.sl, tp: now.tp, profit: 0, digits: s.digits, expiration: 0, locked: false });
      this.changed();
      return { ticket, type: now.type, pending: true, price: now.entry, lots: now.lots, fill: { slipped: false, slipPips: 0, slMoved: false, tpMoved: false, notMoved: '', sl: now.sl, tp: now.tp, risk: now.riskMoney, plannedRisk: now.riskMoney } };
    }
    let slip = mock.slip;
    mock.slip = null;
    if (slip === null) slip = Math.random() < 0.3 ? round(0.5 + Math.random() * 2.5, 1) : 0;
    const price = round(now.entry + side * slip * s.pipSize, s.digits);
    let sl = now.sl;
    let tp = now.tp;
    if (slip) {
      // SL/TP follow the fill as the SL mode says (AiFollowFill): a price stays put.
      const d = price - now.entry;
      if (input.slMode !== 'price') sl = round(sl + d, s.digits);
      if (input.tpMode === 'pips') tp = round(tp + d, s.digits);
      else if (input.tpMode === 'r') tp = round(price + side * Number(input.tpValue) * Math.abs(price - sl), s.digits);
    }
    const ticket = this.open(input.symbol, side, now.lots, price, sl, tp);
    this.changed();
    const risk = round(now.lots * (Math.abs(price - sl) / s.pipSize) * this.perPip(s), 2);
    return {
      ticket, type: now.type, pending: false, price, lots: now.lots,
      fill: { slipped: slip !== 0, slipPips: slip, slMoved: sl !== now.sl, tpMoved: tp !== now.tp, notMoved: '', sl, tp, risk, plannedRisk: pv.plan.riskMoney },
    };
  },

  // From record 'back' on, the first that holds the levels asked for (Bridge.mqh DoRecall).
  recall(m) {
    const which = m.which || 'both';
    const what = which === 'sl' ? 'stop loss' : which === 'tp' ? 'take profit' : 'SL/TP';
    const list = this.memory[m.symbol] || [];
    const back = Math.max(0, Number(m.back) || 0);
    for (let k = 0; k < list.length; k++) {
      const index = (back + k) % list.length;
      const r = list[index];
      const parts = [];
      if (which !== 'tp' && r.slValue > 0) parts.push('SL ' + (r.slMode === 'price' ? r.slValue : r.slValue + ' pips'));
      if (which !== 'sl' && r.tpValue > 0) parts.push('TP ' + (r.tpMode === 'r' ? r.tpValue + 'R' : r.tpMode === 'pips' ? r.tpValue + ' pips' : r.tpValue));
      if (!parts.length) continue;
      return { slMode: r.slMode, slValue: r.slValue, tpMode: r.tpMode, tpValue: r.tpValue, desc: parts.join(', '), index, count: list.length };
    }
    return { ok: false, err: 'No earlier ' + what + ' saved for ' + m.symbol };
  },

  // AiBuildModPlan's checks in their order, with simpler money.
  modPreview(m) {
    const x = this.find(m.ticket);
    if (!x) return { ok: false, err: '#' + m.ticket + ' is not open' };
    const s = SPECS[x.symbol];
    const q = PRICES[x.symbol];
    const open = x.kind === 'order' && m.open > 0 ? round(m.open, s.digits) : x.open;
    const sl = 'sl' in m ? round(Number(m.sl) || 0, s.digits) : x.sl;
    const tp = 'tp' in m ? round(Number(m.tp) || 0, s.digits) : x.tp;
    const perPip = this.perPip(s);
    const at = (from, level) => (level > 0 ? round((((level - from) * x.side) / s.pipSize) * perPip * x.lots, 2) : 0);
    const base = this.equity();
    const r = {
      valid: false, changed: open !== x.open || sl !== x.sl || tp !== x.tp, err: '', warn: '', open, sl, tp,
      slMoney: at(open, sl), slPct: 0, oldSlMoney: at(x.open, x.sl), tpMoney: at(open, tp), tpPct: 0, rr: 0, slPips: 0, tpPips: 0,
    };
    r.slPct = round((r.slMoney / base) * 100, 2);
    r.tpPct = round((r.tpMoney / base) * 100, 2);
    const slDist = sl > 0 ? Math.abs(open - sl) : 0;
    const tpDist = tp > 0 ? Math.abs(tp - open) : 0;
    r.slPips = round(slDist / s.pipSize, 1);
    r.tpPips = round(tpDist / s.pipSize, 1);
    if (sl > 0 && (sl - open) * x.side < 0) r.rr = round(tpDist / slDist, 2);
    const now = x.side > 0 ? q.bid : q.ask;
    const ref = x.kind === 'position' ? now : open;
    const refWord = x.kind === 'position' ? 'the price now (' + now.toFixed(s.digits) + ')' : 'the entry';
    if (x.locked) r.err = 'A stop-limit order can only be changed in MT5';
    else if (!(sl > 0)) r.err = 'Set a stop loss';
    else if (!(tp > 0)) r.err = 'Set a take profit';
    else if ((sl - ref) * x.side >= 0) r.err = 'The stop loss must be ' + (x.side > 0 ? 'below ' : 'above ') + refWord;
    else if ((tp - ref) * x.side <= 0) r.err = 'The take profit must be ' + (x.side > 0 ? 'above ' : 'below ') + refWord;
    else if (-r.slPct > SETTINGS.maxRiskPct + 1e-9 && x.sl > 0 && -r.slMoney > -r.oldSlMoney + 0.01) r.err = 'Risk ' + (-r.slPct).toFixed(2) + '% is above your ' + SETTINGS.maxRiskPct + '% safety cap';
    r.valid = !r.err && r.changed;
    return { preview: this.addPreview('mod', { ticket: x.ticket, open, sl, tp }), mod: r };
  },

  modSend(m) {
    const pv = this.usePreview(m.preview, 'mod');
    if (typeof pv === 'string') return { ok: false, err: pv };
    if (this.problem) return { ok: false, err: this.problem };
    const x = this.find(pv.ticket);
    if (!x) return { ok: false, err: '#' + pv.ticket + ' is already closed' };
    if (x.kind === 'order') x.open = pv.open;
    x.sl = pv.sl;
    x.tp = pv.tp;
    this.changed();
    return { ticket: x.ticket };
  },

  closePreview(m) {
    const x = this.find(m.ticket);
    if (!x || x.kind !== 'position') return { ok: false, err: '#' + m.ticket + ' is not an open position' };
    const s = SPECS[x.symbol];
    const q = PRICES[x.symbol];
    let lots = round(Number(m.lots) || 0, 6);
    if (lots <= 0) lots = x.lots;
    const left = round(x.lots - lots, 6);
    let err = '';
    if (Math.abs(lots / s.volStep - Math.round(lots / s.volStep)) > 1e-6) err = 'Lots must be a multiple of ' + s.volStep;
    else if (left < -1e-9) err = '#' + x.ticket + ' has only ' + x.lots + ' lots';
    else if (left > 1e-9 && left < s.volMin - 1e-9) err = 'What stays open must be at least ' + s.volMin + ' lots';
    this.revalue();
    return {
      preview: this.addPreview('close', { ticket: x.ticket, lots, wasLots: x.lots }),
      close: { valid: !err, err, lots, left: err ? 0 : Math.max(left, 0), price: x.side > 0 ? q.bid : q.ask, profit: round((x.profit * lots) / x.lots, 2) },
    };
  },

  close(m) {
    const pv = this.usePreview(m.preview, 'close');
    if (typeof pv === 'string') return { ok: false, err: pv };
    if (this.problem) return { ok: false, err: this.problem };
    const x = this.find(pv.ticket);
    if (!x || x.kind !== 'position') return { ok: false, err: '#' + pv.ticket + ' is already closed' };
    if (Math.abs(x.lots - pv.wasLots) > 1e-9) return { ok: false, err: '#' + x.ticket + ' changed size since the preview. Check it and confirm again' };
    this.revalue();
    const q = PRICES[x.symbol];
    this.balance = round(this.balance + (x.profit * pv.lots) / x.lots, 2);
    x.lots = round(x.lots - pv.lots, 6);
    if (x.lots <= 1e-9) this.trades = this.trades.filter((y) => y !== x);
    this.changed();
    return { ticket: x.ticket, price: x.side > 0 ? q.bid : q.ask, lots: pv.lots };
  },

  cancel(m) {
    const x = this.find(m.ticket);
    if (!x || x.kind !== 'order') return { ok: false, err: '#' + m.ticket + ' is not a pending order' };
    if (this.problem) return { ok: false, err: this.problem };
    this.trades = this.trades.filter((y) => y !== x);
    this.changed();
    return {};
  },
};

//--- the link: the panel's port, and which terminals it serves ----------------------
const terms = new Map();
let port = null;
let mt5Running = scene !== 'nomt5';
let ticking = false;

function makeTerminals() {
  const hourAgo = Date.now() - 3600000;
  terms.set('1', new Terminal('1',
    { login: 12345678, server: 'Demo-Server', company: 'Demo Broker Ltd', currency: 'USD', marginMode: 'hedging', balance: 10000, firstTicket: 4327679340 },
    [
      { ticket: 4327679330, symbol: 'XAUUSDm', kind: 'position', type: 'BUY', side: 1, lots: 0.2, open: 2648.58, sl: 2643.58, tp: 2658.58, profit: 0, digits: 3, openMsc: hourAgo },
      { ticket: 4327679331, symbol: 'EURUSDm', kind: 'order', type: 'SELL LIMIT', side: -1, lots: 0.5, open: 1.0941, sl: 1.0961, tp: 1.0901, profit: 0, digits: 5, expiration: 0, locked: false },
      { ticket: 4327679332, symbol: 'XAUUSDm', kind: 'order', type: 'BUY STOP LIMIT', side: 1, lots: 0.1, open: 2662, sl: 2655, tp: 2680, profit: 0, digits: 3, expiration: 0, locked: true },
    ],
    { XAUUSDm: [{ slMode: 'pips', slValue: 50, tpMode: 'r', tpValue: 2 }, { slMode: 'pips', slValue: 30, tpMode: 'pips', tpValue: 90 }] }));
  if (params.get('terms') === '2') {
    terms.set('2', new Terminal('2',
      { login: 87654321, server: 'Other-Demo', company: 'Other Broker AG', currency: 'EUR', marginMode: 'netting', balance: 5000, firstTicket: 900001 },
      [], {}));
  }
}

function deliver(m) {
  if (port) port.deliver(m);
}

function linkSays(state, term, text) {
  const m = { t: 'link', state };
  if (term) m.term = term;
  if (text) m.text = text;
  deliver(m);
}

function serve(t) {
  if (!port || t.serving) return;
  t.serving = true;
  linkSays('terminal-connected', t.id, t.acct.login + '@' + t.acct.server);
  t.emit(t.info());
  t.emit(t.tradesMsg());
}

function stopServing(t) {
  if (!t.serving) return;
  t.serving = false;
  t.watch = '';
  linkSays('terminal-gone', t.id);
}

function tick() {
  walk();
  for (const t of terms.values()) {
    if (!t.serving || !t.watch) continue;
    const q = PRICES[t.watch];
    const key = q.bid + '/' + q.ask;
    if (key === t.sentQuote) continue;
    t.sentQuote = key;
    t.emit({ t: 'quote', symbol: t.watch, bid: q.bid, ask: q.ask, spreadPips: round((q.ask - q.bid) / SPECS[t.watch].pipSize, 1), timeMsc: Date.now() });
  }
}

function everySecond() {
  for (const t of terms.values()) {
    if (!t.serving) continue;
    if (t.trades.some((x) => x.kind === 'position')) t.emit(t.tradesMsg());
    t.emit({ t: 'beat' });
  }
}

function handle(m) {
  if (!m || typeof m !== 'object') return;
  mock.last = m;
  if (m.t === 'link.status') {
    linkSays('listening');
    for (const t of terms.values()) if (t.serving) linkSays('terminal-connected', t.id, t.acct.login + '@' + t.acct.server);
    return;
  }
  if (m.t === 'link.start') {
    if (mt5Running) {
      if (scene === 'noea') linkSays('no-ea', '', 'MT5 is running, but no chart serves the panel: put ActionInna on a chart, with Algo Trading on');
      return;
    }
    mt5Running = true;
    linkSays('starting-mt5', '', 'Starting MT5');
    setTimeout(() => terms.forEach(serve), 4000);
    return;
  }
  let t = terms.get(m.term);
  if (!m.term) {
    const serving = [...terms.values()].filter((x) => x.serving);
    if (serving.length === 1) t = serving[0];
  }
  if (!t || !t.serving) {
    deliver({ t: 'reply', id: m.id, ok: false, err: 'MT5 is not connected' });
    return;
  }
  t.request(m);
}

function makePort() {
  const onMessage = [];
  const onDisconnect = [];
  const p = {
    open: true,
    onMessage: { addListener: (fn) => onMessage.push(fn) },
    onDisconnect: { addListener: (fn) => onDisconnect.push(fn) },
    postMessage(m) {
      if (!p.open) throw new Error('Attempting to use a disconnected port object');
      const copy = JSON.parse(JSON.stringify(m));
      setTimeout(() => p.open && handle(copy), LAG_MS);
    },
    disconnect() {
      p.open = false;
    },
    deliver(m) {
      const copy = JSON.parse(JSON.stringify(m));
      setTimeout(() => p.open && onMessage.forEach((fn) => fn(copy)), LAG_MS);
    },
    drop() {
      p.open = false;
      onDisconnect.forEach((fn) => fn());
    },
  };
  return p;
}

export function connect() {
  if (scene === 'nolink') throw new Error('Specified native messaging host not found.');
  if (!terms.size) makeTerminals();
  if (!ticking) {
    ticking = true;
    setInterval(tick, 150);
    setInterval(everySecond, 1000);
  }
  port = makePort();
  linkSays('listening');
  // The EAs find the new pipe within a couple of seconds.
  if (mt5Running && scene !== 'noea') setTimeout(() => terms.forEach(serve), 400);
  if (scene === 'noea') setTimeout(() => linkSays('no-ea', '', 'MT5 is running, but no chart serves the panel: put ActionInna on a chart, with Algo Trading on'), 3000);
  return port;
}

const mock = {
  slip: null,
  dropReply: '',
  last: null,
  gone(id = '1') {
    if (terms.has(id)) stopServing(terms.get(id));
  },
  back(id = '1') {
    if (terms.has(id)) serve(terms.get(id));
  },
  problem(id = '1', text = '') {
    const t = terms.get(id);
    if (!t) return;
    t.problem = text;
    t.emit(t.info());
  },
  stopLink() {
    if (!port) return;
    const p = port;
    port = null;
    terms.forEach((t) => {
      t.serving = false;
      t.watch = '';
    });
    p.drop();
  },
};
globalThis.actioninnaMock = mock;
