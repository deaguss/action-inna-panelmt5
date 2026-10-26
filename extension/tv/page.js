// Runs inside TradingView's own page (the main world), put there by the side panel. It draws the
// panel's lines on the active chart with TradingView's order lines, and tells the panel when the
// trader drags one. It reads and changes nothing else on the page.
// It uses TradingView's internal chart object (window.TradingViewApi), which is not a public
// interface: when it is missing or changes, nothing is drawn, and the panel works as before.
(() => {
  if (window.__actionInnaChart) return;
  const COLORS = { entry: 'rgb(120,123,134)', sl: 'rgb(200,48,62)', tp: 'rgb(22,124,74)' };
  const ROLES = new Set(['entry', 'sl', 'tp']);
  const KEY = /^(?:pv|t\d{1,20})-(?:entry|sl|tp)$/;
  const SILENCE_MS = 6000;   // the panel sends its lines every 2 s; without them it was closed
  const drawn = new Map();   // key -> { line, spec }
  let queue = Promise.resolve();
  let heard = 0;
  window.__actionInnaChart = { drawn };

  window.addEventListener('message', (e) => {
    if (e.source !== window || !e.data || e.data.actionInna !== 'lines' || !Array.isArray(e.data.lines)) return;
    heard = Date.now();
    const lines = e.data.lines;
    queue = queue.then(() => draw(lines)).catch(() => {});
  });

  setInterval(() => {
    if (drawn.size && Date.now() - heard > SILENCE_MS) queue = queue.then(() => draw([])).catch(() => {});
  }, 1000);

  function chart() {
    try {
      return window.TradingViewApi ? window.TradingViewApi.activeChart() : null;
    } catch (e) {
      return null;
    }
  }

  function valid(l) {
    return l && typeof l.key === 'string' && KEY.test(l.key) && ROLES.has(l.role) && Number.isFinite(l.price) && l.price > 0 &&
      typeof l.text === 'string' && l.text.length <= 80 && typeof l.qty === 'string' && l.qty.length <= 20;
  }

  async function draw(lines) {
    const wanted = new Map(lines.filter(valid).map((l) => [l.key, l]));
    for (const [key, d] of drawn) {
      if (wanted.has(key)) continue;
      call(d.line, 'remove');
      drawn.delete(key);
    }
    const c = chart();
    for (const [key, spec] of wanted) {
      let d = drawn.get(key);
      if (!d) {
        if (!c || typeof c.createOrderLine !== 'function') return;
        let line;
        try {
          line = await c.createOrderLine();
        } catch (e) {
          return;
        }
        if (!line) return;
        d = { line, spec: null };
        drawn.set(key, d);
        call(line, 'setCancellable', false);
        call(line, 'onMove', () => moved(key, d));
      }
      paint(d, spec);
    }
  }

  // Calls only what changed, so TradingView doesn't redraw a line that stayed the same.
  function paint(d, s) {
    const l = d.line;
    const o = d.spec || {};
    if (o.price !== s.price) call(l, 'setPrice', s.price);
    if (o.text !== s.text) call(l, 'setText', s.text);
    if (o.qty !== s.qty) call(l, 'setQuantity', s.qty);
    if (o.role !== s.role || o.trade !== s.trade || o.unsent !== s.unsent) {
      const color = COLORS[s.role];
      for (const m of ['setLineColor', 'setBodyBorderColor', 'setBodyTextColor', 'setQuantityBackgroundColor', 'setQuantityBorderColor']) call(l, m, color);
      call(l, 'setLineStyle', s.trade && !s.unsent ? 2 : 0);
    }
    if (o.editable !== s.editable) call(l, 'setEditable', !!s.editable);
    d.spec = s;
  }

  function moved(key, d) {
    // The panel answers with where the line belongs, which may be where it was before the drag.
    d.spec = Object.assign({}, d.spec, { price: NaN });
    const price = Number(call(d.line, 'getPrice'));
    if (Number.isFinite(price) && price > 0) window.postMessage({ actionInna: 'moved', key, price }, location.origin);
  }

  function call(obj, method, ...args) {
    try {
      return typeof obj[method] === 'function' ? obj[method](...args) : undefined;
    } catch (e) {
      return undefined;
    }
  }
})();
