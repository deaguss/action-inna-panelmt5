// The connection to the link program, and through it to the MT5 terminals (docs/protocol.md).
// request() sends a request with an id and resolves with its reply; everything else that arrives
// goes to the handlers registered with on(type). The link restarts by itself when it stops.
//
// A reply with lost:true means the request reached MT5 (or may have) but its answer never came
// back: MT5 may have carried it out. One without lost was not carried out.

const REPLY_TIMEOUT_MS = 15000;
const RETRY_MS = 2000;

export class Link {
  // openPort returns a port: chrome.runtime.connectNative(...) in the extension, a stand-in in tests.
  // times overrides the waits, for tests: { replyMs, retryMs }.
  constructor(openPort, lastError, times) {
    this.openPort = openPort;
    this.lastError = lastError || (() => '');
    this.replyMs = (times && times.replyMs) || REPLY_TIMEOUT_MS;
    this.retryMs = (times && times.retryMs) || RETRY_MS;
    this.port = null;
    this.nextId = 1;
    this.pending = new Map();
    this.handlers = new Map();
    this.connected = false;
    this.error = '';
    this.retry = null;
  }

  on(type, fn) {
    if (!this.handlers.has(type)) this.handlers.set(type, []);
    this.handlers.get(type).push(fn);
  }

  emit(type, msg) {
    for (const fn of this.handlers.get(type) || []) fn(msg);
    for (const fn of this.handlers.get('*') || []) fn(msg);
  }

  start() {
    clearTimeout(this.retry);
    let port;
    try {
      port = this.openPort();
    } catch (e) {
      this.stopped(String((e && e.message) || e));
      return;
    }
    this.port = port;
    this.connected = true;
    this.error = '';
    port.onMessage.addListener((m) => this.receive(m));
    port.onDisconnect.addListener(() => {
      if (this.port !== port) return;
      this.stopped(this.lastError() || '');
    });
    this.emit('link-open', {});
  }

  stopped(why) {
    this.port = null;
    this.connected = false;
    this.error = why;
    this.abandon(null, 'The link stopped before MT5 answered');
    this.emit('link-stopped', { error: why });
    this.retry = setTimeout(() => this.start(), this.retryMs);
  }

  // Gives up on the requests waiting for one terminal's answer (null: every terminal's).
  abandon(term, err) {
    for (const p of [...this.pending.values()]) {
      if (term !== null && p.term !== term) continue;
      clearTimeout(p.timer);
      this.pending.delete(p.id);
      p.resolve({ t: 'reply', id: p.id, ok: false, lost: true, err });
    }
  }

  receive(m) {
    if (!m || typeof m !== 'object') return;
    if (m.t === 'reply' && this.pending.has(m.id)) {
      const p = this.pending.get(m.id);
      this.pending.delete(m.id);
      clearTimeout(p.timer);
      p.resolve(m);
      return;
    }
    this.emit(m.t, m);
  }

  // A message that needs no reply (link.status, link.start).
  post(msg) {
    if (!this.port) return false;
    try {
      this.port.postMessage(msg);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Resolves with the reply; a reply with ok:false when the link is down or MT5 doesn't answer.
  request(type, fields, term) {
    const id = this.nextId++;
    const msg = Object.assign({ term: term || '', t: type, id }, fields || {});
    return new Promise((resolve) => {
      if (!this.port) {
        resolve({ t: 'reply', id, ok: false, err: 'The link is not running' });
        return;
      }
      const timer = setTimeout(() => {
        this.pending.delete(id);
        resolve({ t: 'reply', id, ok: false, lost: true, err: 'MT5 did not answer' });
      }, this.replyMs);
      this.pending.set(id, { id, term: msg.term, resolve, timer });
      if (!this.post(msg)) {
        clearTimeout(timer);
        this.pending.delete(id);
        resolve({ t: 'reply', id, ok: false, err: 'The link is not running' });
      }
    });
  }
}

// What Chrome's errors mean for the trader.
export function explainLinkError(err) {
  const e = String(err || '');
  if (/not found/i.test(e)) return 'The ActionInna link is not installed: run ActionInnaLink.exe --install';
  if (/forbidden/i.test(e)) return 'The ActionInna link does not know this extension. Run ActionInnaLink.exe --install again';
  if (!e || /exited/i.test(e)) return 'The ActionInna link stopped. Trying again';
  return 'The link stopped (' + e.replace(/\.$/, '') + '). Trying again';
}
