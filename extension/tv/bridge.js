// Runs in TradingView's tab beside tv/page.js, in the extension's own world: passes the side
// panel's lines to page.js, and a line the trader dragged back to the panel. A drag only changes
// what the panel shows; nothing is sent to MT5 until the trader confirms in the panel.
(() => {
  if (globalThis.__actionInnaBridge) return;
  globalThis.__actionInnaBridge = true;

  chrome.runtime.onMessage.addListener((msg, sender, reply) => {
    if (sender.id !== chrome.runtime.id || !msg || msg.t !== 'ai-lines' || !Array.isArray(msg.lines)) return;
    window.postMessage({ actionInna: 'lines', lines: msg.lines }, location.origin);
    reply({ ok: true });
  });

  // Any script on TradingView's page can post here: only a line key and a price pass.
  window.addEventListener('message', (e) => {
    if (e.source !== window || !e.data || e.data.actionInna !== 'moved') return;
    const key = e.data.key;
    const price = e.data.price;
    if (typeof key !== 'string' || !/^(?:pv|t\d{1,20})-(?:entry|sl|tp)$/.test(key) || typeof price !== 'number' || !Number.isFinite(price) || price <= 0) return;
    chrome.runtime.sendMessage({ t: 'ai-moved', key, price }).catch(() => {});
  });
})();
