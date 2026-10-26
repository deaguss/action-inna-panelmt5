// The lines the side panel draws on TradingView's chart: the order being previewed, and the open
// trades on the chart's symbol. The panel passes its state in, and tv/page.js draws what comes out:
//   { key, role: 'entry' | 'sl' | 'tp', price, text, qty, editable, trade, unsent }
// trade: the line belongs to an open trade (drawn dashed). unsent: a change on its card, not sent.
import * as fmt from './format.js';

// s: {
//   preview: the plan being previewed and how it was asked for: { pending, type, entry, sl, tp, lots,
//            riskMoney, riskPct, rewardMoney, rr }, or null
//   trades:  the open positions and pending orders on the chart's symbol (the trades message's list)
//   card:    an open change card: { ticket, open, sl, tp } as typed (NaN for a typo), and type when
//            MT5 said the order becomes the other type; or null
//   volStep: the symbol's volume step, money: (value, withSign) => text in the account currency }
export function wantedLines(s) {
  const out = [];
  // A plan MT5 refused still has its levels: they stay on the chart, to be dragged right.
  const lots = (v) => (v > 0 ? fmt.lots(v, s.volStep) : '-');
  const p = s.preview;
  if (p && p.entry > 0) {
    out.push({ key: 'pv-entry', role: 'entry', price: p.entry, text: p.pending ? p.type : p.type + ' at market', qty: lots(p.lots), editable: !!p.pending, trade: false, unsent: false });
    if (p.sl > 0) {
      const risk = p.riskMoney > 0 ? ' ' + s.money(-p.riskMoney) + ' (' + p.riskPct.toFixed(2) + '%)' : '';
      out.push({ key: 'pv-sl', role: 'sl', price: p.sl, text: 'SL' + risk, qty: lots(p.lots), editable: true, trade: false, unsent: false });
    }
    if (p.tp > 0) {
      const reward = (p.rewardMoney > 0 ? ' ' + s.money(p.rewardMoney, true) : '') + (p.rr > 0 ? ' 1:' + p.rr.toFixed(2) : '');
      out.push({ key: 'pv-tp', role: 'tp', price: p.tp, text: 'TP' + reward, qty: lots(p.lots), editable: true, trade: false, unsent: false });
    }
  }
  for (const x of s.trades || []) {
    const c = s.card && s.card.ticket === x.ticket ? s.card : null;
    const pick = (typed, now) => (c && Number.isFinite(typed) ? typed : now);
    const open = x.kind === 'order' ? pick(c && c.open, x.open) : x.open;
    const sl = pick(c && c.sl, x.sl);
    const tp = pick(c && c.tp, x.tp);
    const qty = fmt.trimZeros(String(x.lots));
    const k = 't' + x.ticket + '-';
    const line = (role, price, was, text, editable) => {
      const unsent = Math.abs(price - was) > 1e-12;
      out.push({ key: k + role, role, price, text: text + (unsent ? ' (not sent)' : ''), qty, editable, trade: true, unsent });
    };
    // An entry moved across the market makes the order the other type: the line names what it becomes.
    const type = c && c.type ? c.type : x.type;
    line('entry', open, x.open, type + (x.kind === 'position' ? ' ' + s.money(x.profit, true) : ''), x.kind === 'order' && !x.locked);
    if (sl > 0) line('sl', sl, x.sl, 'SL', !x.locked);
    if (tp > 0) line('tp', tp, x.tp, 'TP', !x.locked);
  }
  return out;
}

// "pv-sl" -> { ticket: 0, role: 'sl' }; "t4327679330-tp" -> { ticket: 4327679330, role: 'tp' }; null for anything else.
export function parseLineKey(key) {
  const m = /^(?:pv|t(\d{1,20}))-(entry|sl|tp)$/.exec(String(key || ''));
  return m ? { ticket: m[1] ? Number(m[1]) : 0, role: m[2] } : null;
}
