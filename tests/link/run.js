// Tests for ActionInnaLink.exe (link/*.cs). They play Chrome (native messaging frames on the link's
// stdin and stdout) and up to three ActionInna EAs (frames on the named pipe) against the built exe.
// Every file the link uses and its pipe name are moved into tests/link/out, so a real set-up on this
// PC is never touched; the registry is left alone (--no-registry).
//   node tests/link/run.js [path to ActionInnaLink.exe]    (default build/ActionInnaLink.exe)
'use strict';
const { spawn, spawnSync } = require('child_process');
const fs = require('fs');
const net = require('net');
const path = require('path');

const repo = path.resolve(__dirname, '..', '..');
const exe = path.resolve(process.argv[2] || path.join(repo, 'build', 'ActionInnaLink.exe'));
const out = path.join(__dirname, 'out', String(Date.now()));
const B = String.fromCharCode(92);
const DEV_ID = 'knlcnmdecbojpcoggfahghifkbalkpdk';

let pass = 0;
let fail = 0;
function expect(ok, what) {
  if (ok) { pass++; return; }
  fail++;
  console.log('FAIL ' + what);
}

function env(name) {
  const home = path.join(out, name);
  return Object.assign({}, process.env, {
    ACTIONINNA_HOME: path.join(home, 'home'),
    ACTIONINNA_COMMON: path.join(home, 'common'),
    ACTIONINNA_TERMINALS: path.join(home, 'terminals'),
    ACTIONINNA_PIPE: 'ActionInna.Link.Test.' + process.pid + '.' + name,
  });
}

function pipePath(e) { return B + B + '.' + B + 'pipe' + B + e.ACTIONINNA_PIPE; }

function frame(obj) {
  const body = Buffer.from(typeof obj === 'string' ? obj : JSON.stringify(obj), 'utf8');
  const head = Buffer.alloc(4);
  head.writeUInt32LE(body.length, 0);
  return Buffer.concat([head, body]);
}

// Collects the frames a stream carries; next(pred) waits for the first one that matches.
function reader(stream) {
  let buf = Buffer.alloc(0);
  const frames = [];
  const raw = [];
  let waiters = [];
  stream.on('data', (d) => {
    buf = Buffer.concat([buf, d]);
    while (buf.length >= 4) {
      const len = buf.readUInt32LE(0);
      if (buf.length < 4 + len) break;
      const body = buf.slice(4, 4 + len);
      buf = buf.slice(4 + len);
      raw.push(body);
      try { frames.push(JSON.parse(body.toString('utf8'))); } catch (e) { frames.push({ unparsed: body.toString('utf8') }); }
      const w = waiters;
      waiters = [];
      w.forEach((f) => f());
    }
  });
  // One timer per wait: a timer started on every frame that arrives would pile up into thousands.
  function next(pred, ms = 4000) {
    return new Promise((resolve) => {
      let done = false;
      const finish = (v) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        resolve(v);
      };
      const check = () => {
        if (done) return;
        const i = frames.findIndex(pred);
        if (i >= 0) finish(frames.splice(i, 1)[0]);
        else waiters.push(check);
      };
      const timer = setTimeout(() => finish(null), ms);
      check();
    });
  }
  return { frames, raw, next };
}

function startHost(e) {
  const child = spawn(exe, ['chrome-extension://' + DEV_ID + '/'], { stdio: ['pipe', 'pipe', 'inherit'], env: e });
  const browser = reader(child.stdout);
  const exited = new Promise((r) => child.on('exit', (code) => r(code)));
  return { child, browser, exited, send: (obj) => child.stdin.write(frame(obj)) };
}

function connectOnce(e) {
  return new Promise((resolve) => {
    const sock = net.connect(pipePath(e));
    sock.on('connect', () => {
      const r = reader(sock);
      let closed = false;
      sock.on('close', () => { closed = true; });
      resolve({ sock, r, send: (obj) => sock.write(frame(obj)), closed: () => closed });
    });
    sock.on('error', () => resolve(null));
  });
}

// As the EA does, tries again for a while: between two connections the link makes a new pipe instance.
async function connectEa(e, tries = 10) {
  for (let i = 0; i < tries; i++) {
    const c = await connectOnce(e);
    if (c) return c;
    await sleep(100);
  }
  return null;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function testRouting() {
  const e = env('routing');
  const h = startHost(e);
  expect(await h.browser.next((f) => f.t === 'link' && f.state === 'listening'), 'the link says it listens');
  const keyFile = path.join(e.ACTIONINNA_COMMON, 'link.key');
  const key = fs.existsSync(keyFile) ? fs.readFileSync(keyFile, 'ascii').trim() : '';
  expect(/^[0-9a-f]{32}$/.test(key), 'a key of 32 hex characters is made: ' + key);

  const ea1 = await connectEa(e);
  expect(ea1, 'an EA can open the pipe');
  if (!ea1) { h.child.kill(); return; }
  const k1 = await ea1.r.next(() => true);
  expect(k1 && k1.t === 'link' && k1.key === key, 'the key is the first frame an EA gets');
  ea1.send({ t: 'terminal', login: 111, server: 'Broker-Demo' });
  const st1 = await h.browser.next((f) => f.t === 'link' && f.state === 'terminal-connected');
  expect(st1 && st1.term === '1' && st1.text === '111@Broker-Demo', 'the panel learns terminal 1 and its account');
  const tm1 = await h.browser.next((f) => f.t === 'terminal');
  expect(tm1 && tm1.term === '1' && tm1.login === 111, 'messages from an EA carry its term');
  ea1.send({});
  const empty = await h.browser.next((f) => Object.keys(f).length === 1 && f.term === '1');
  expect(empty, 'even an empty object gets its term');

  const req = '{"term":"1","t":"watch","id":5,"symbol":"XAUUSDm"}';
  h.send(req);
  await sleep(150);
  expect(ea1.r.raw.length >= 2 && ea1.r.raw[ea1.r.raw.length - 1].toString('utf8') === req, 'a request reaches its terminal byte for byte');

  const ea2 = await connectEa(e);
  await ea2.r.next(() => true);
  ea2.send({ t: 'terminal', login: 222, server: 'Other-Live' });
  expect(await h.browser.next((f) => f.state === 'terminal-connected' && f.term === '2'), 'a second MT5 is terminal 2');
  const before1 = ea1.r.raw.length;
  h.send({ term: '2', t: 'watch', id: 6 });
  expect(await ea2.r.next((f) => f.id === 6), 'term 2 goes to the second MT5');
  await sleep(100);
  expect(ea1.r.raw.length === before1, 'and not to the first');

  h.send({ t: 'preview', id: 7 });
  let r = await h.browser.next((f) => f.t === 'reply' && f.id === 7);
  expect(r && r.ok === false && /not connected/.test(r.err), 'with two MT5s, a request without a term is answered, not guessed');
  h.send({ term: '9', t: 'preview', id: 8 });
  r = await h.browser.next((f) => f.t === 'reply' && f.id === 8);
  expect(r && r.ok === false, 'an unknown term is answered too');
  h.send({ term: '9', t: 'beat' });
  await sleep(100);
  expect(!h.browser.frames.some((f) => f.t === 'reply' && f.id === undefined), 'a message without an id gets no reply');
  h.child.stdin.write(frame('not json'));
  expect(await h.browser.next((f) => f.t === 'error'), 'a frame that is not JSON gets an error');

  const ea3 = await connectEa(e);
  await ea3.r.next(() => true);
  ea3.send({ t: 'terminal', login: 111, server: 'Broker-Demo' });
  expect(await h.browser.next((f) => f.state === 'terminal-gone' && f.term === '1'), 'a newer connection for the same account replaces the older');
  expect(await h.browser.next((f) => f.state === 'terminal-connected' && f.term === '3'), 'and becomes terminal 3');
  await sleep(150);
  expect(ea1.closed(), 'the older connection is closed');

  h.send({ t: 'link.status' });
  expect(await h.browser.next((f) => f.state === 'listening'), 'link.status: the link');
  const s2 = await h.browser.next((f) => f.state === 'terminal-connected' && f.term === '2');
  const s3 = await h.browser.next((f) => f.state === 'terminal-connected' && f.term === '3');
  expect(s2 && s3, 'link.status: every terminal connected');

  ea2.sock.end();
  expect(await h.browser.next((f) => f.state === 'terminal-gone' && f.term === '2'), 'an EA that leaves is reported gone');

  const big = Buffer.alloc(4);
  big.writeUInt32LE(2 * 1024 * 1024, 0);
  ea3.sock.write(big);
  expect(await h.browser.next((f) => f.state === 'terminal-gone' && f.term === '3'), 'an EA sending a frame over 1 MiB is dropped');

  const second = startHost(e);
  const busy = await second.browser.next((f) => f.state === 'busy');
  expect(busy && /another browser window/.test(busy.text), 'a second copy of the link says the panel is open elsewhere');
  expect((await second.exited) === 2, 'and stops');

  h.child.stdin.end();
  expect((await h.exited) === 0, 'the link stops when the browser closes it');
  await sleep(100);
  expect(!(await connectEa(e, 1)), 'and its pipe goes with it');
}

async function testMt5Start() {
  let e = env('nomt5');
  let h = startHost(e);
  let s = await h.browser.next((f) => f.t === 'link' && f.state === 'no-mt5', 6000);
  expect(s && /--install/.test(s.text), 'no MT5 set up: the panel is told to run the installer');
  h.child.stdin.end();
  await h.exited;

  e = env('missing');
  fs.mkdirSync(e.ACTIONINNA_HOME, { recursive: true });
  fs.writeFileSync(path.join(e.ACTIONINNA_HOME, 'link.json'), JSON.stringify({ startMt5: true, terminals: [{ name: 'Gone', exe: path.join(out, 'nowhere', 'terminal64.exe') }] }));
  h = startHost(e);
  s = await h.browser.next((f) => f.state === 'mt5-missing', 6000);
  expect(s && /no longer at/.test(s.text), 'an MT5 that moved: the panel is told');
  h.child.stdin.end();
  await h.exited;

  // node itself stands in for a running terminal64.exe
  e = env('running');
  fs.mkdirSync(e.ACTIONINNA_HOME, { recursive: true });
  fs.writeFileSync(path.join(e.ACTIONINNA_HOME, 'link.json'), JSON.stringify({ startMt5: true, terminals: [{ name: 'Node', exe: process.execPath }] }));
  h = startHost(e);
  s = await h.browser.next((f) => f.state === 'no-ea', 6000);
  expect(s && /put ActionInna on a chart/.test(s.text), 'MT5 already running but no EA: nothing is started, the panel says what to do');
  h.child.stdin.end();
  await h.exited;

  e = env('serving');
  fs.mkdirSync(e.ACTIONINNA_HOME, { recursive: true });
  fs.writeFileSync(path.join(e.ACTIONINNA_HOME, 'link.json'), JSON.stringify({ startMt5: true, terminals: [{ name: 'Gone', exe: path.join(out, 'nowhere', 'terminal64.exe') }] }));
  h = startHost(e);
  await h.browser.next((f) => f.state === 'listening');
  const ea = await connectEa(e);
  expect(ea, 'an EA connects');
  if (!ea) { h.child.kill(); return; }
  await ea.r.next(() => true);
  ea.send({ t: 'terminal', login: 1, server: 'S' });
  await sleep(3800);
  expect(!h.browser.frames.some((f) => f.state === 'mt5-missing' || f.state === 'no-mt5'), 'with an EA connected, MT5 is left alone');
  h.child.stdin.end();
  await h.exited;
}

function makeTerminal(root, name, opts) {
  const install = path.join(root, 'install', name);
  fs.mkdirSync(install, { recursive: true });
  fs.writeFileSync(path.join(install, 'terminal64.exe'), '');
  const data = path.join(root, 'terminals', name.toUpperCase() + '0000');
  fs.mkdirSync(path.join(data, 'MQL5', 'Experts'), { recursive: true });
  fs.writeFileSync(path.join(data, 'origin.txt'), Buffer.from('﻿' + install, 'utf16le'));
  if (opts && opts.junctionTo) {
    fs.mkdirSync(opts.junctionTo, { recursive: true });
    fs.symlinkSync(opts.junctionTo, path.join(data, 'MQL5', 'Experts', 'ActionInna'), 'junction');
  }
  return { install, data };
}

function testInstaller() {
  const e = env('install');
  const root = path.join(out, 'install');
  const t1 = makeTerminal(root, 'Broker One');
  const repoLike = path.join(root, 'repo', 'mql5', 'Experts', 'ActionInna');
  const t2 = makeTerminal(root, 'Broker Two', { junctionTo: repoLike });
  fs.mkdirSync(path.join(root, 'terminals', 'COMMON'), { recursive: true });   // MT5's Common folder: no MQL5, not a terminal
  const release = path.join(root, 'release');
  fs.mkdirSync(release, { recursive: true });
  const relExe = path.join(release, 'ActionInnaLink.exe');
  fs.copyFileSync(exe, relExe);
  fs.writeFileSync(path.join(release, 'ActionInna.ex5'), 'fake ex5');

  let r = spawnSync(relExe, ['--install', '--no-registry', '--quiet', '--extension-id', 'abcdefghijklmnopabcdefghijklmnop'], { env: e, encoding: 'utf8' });
  expect(r.status === 0, 'install: exit code 0 (' + r.status + ') ' + (r.stderr || ''));
  const home = e.ACTIONINNA_HOME;
  const installed = path.join(home, 'ActionInnaLink.exe');
  expect(fs.existsSync(installed), 'install: the link is copied to its home');
  let manifest = null;
  try { manifest = JSON.parse(fs.readFileSync(path.join(home, 'com.actioninna.link.json'), 'utf8')); } catch (err) { manifest = null; }
  expect(manifest && manifest.name === 'com.actioninna.link' && manifest.type === 'stdio' && path.resolve(manifest.path) === path.resolve(installed),
         'install: the browser manifest points at the installed link');
  expect(manifest && manifest.allowed_origins.includes('chrome-extension://abcdefghijklmnopabcdefghijklmnop/') && manifest.allowed_origins.length === 1,
         'install: only the extension ids are allowed, and not the development id, whose key is public: ' + JSON.stringify(manifest && manifest.allowed_origins));
  const key = fs.readFileSync(path.join(e.ACTIONINNA_COMMON, 'link.key'), 'ascii').trim();
  expect(/^[0-9a-f]{32}$/.test(key), 'install: the key is made');
  let cfg = null;
  try { cfg = JSON.parse(fs.readFileSync(path.join(home, 'link.json'), 'utf8')); } catch (err) { cfg = null; }
  const exes = cfg ? cfg.terminals.map((t) => path.resolve(t.exe)).sort() : [];
  expect(cfg && cfg.startMt5 === true && exes.length === 2 && exes[0] === path.resolve(t1.install, 'terminal64.exe') &&
         exes[1] === path.resolve(t2.install, 'terminal64.exe'), 'install: link.json lists both MT5s: ' + JSON.stringify(cfg));
  const copied = path.join(t1.data, 'MQL5', 'Experts', 'ActionInna', 'ActionInna.ex5');
  expect(fs.existsSync(copied) && fs.readFileSync(copied, 'utf8') === 'fake ex5', 'install: ActionInna.ex5 is copied into MT5');
  expect(!fs.existsSync(path.join(repoLike, 'ActionInna.ex5')), 'install: a folder linked to a repository is left alone');
  expect(/development set-up/.test(r.stdout) && /Left to do/.test(r.stdout), 'install: says what it did and what is left');

  r = spawnSync(installed, ['--install', '--no-registry', '--quiet'], { env: e, encoding: 'utf8' });
  expect(r.status === 0 && fs.readFileSync(path.join(e.ACTIONINNA_COMMON, 'link.key'), 'ascii').trim() === key,
         'install again: the key is kept, so running EAs keep working');

  r = spawnSync(relExe, ['--uninstall', '--no-registry', '--quiet'], { env: e, encoding: 'utf8' });
  expect(r.status === 0 && !fs.existsSync(path.join(home, 'com.actioninna.link.json')) && !fs.existsSync(path.join(home, 'link.json')) &&
         !fs.existsSync(path.join(e.ACTIONINNA_COMMON, 'link.key')) && !fs.existsSync(installed), 'uninstall: everything it made is gone');
  expect(fs.existsSync(copied), 'uninstall: ActionInna.ex5 stays in MT5');

  const devEnv = env('dev');
  r = spawnSync(relExe, ['--install', '--dev', '--no-registry', '--quiet', '--mt5', t1.data], { env: devEnv, encoding: 'utf8' });
  let devManifest = null;
  try { devManifest = JSON.parse(fs.readFileSync(path.join(devEnv.ACTIONINNA_HOME, 'com.actioninna.link.json'), 'utf8')); } catch (err) { devManifest = null; }
  expect(r.status === 0 && devManifest && path.resolve(devManifest.path) === path.resolve(relExe) &&
         !fs.existsSync(path.join(devEnv.ACTIONINNA_HOME, 'ActionInnaLink.exe')), '--dev: the manifest points at the build, nothing is copied');
  expect(devManifest && devManifest.allowed_origins.length === 1 && devManifest.allowed_origins[0] === 'chrome-extension://' + DEV_ID + '/',
         '--dev: the unpacked panel may start the link');
  const devCfg = JSON.parse(fs.readFileSync(path.join(devEnv.ACTIONINNA_HOME, 'link.json'), 'utf8'));
  expect(devCfg.terminals.length === 1, '--mt5: only the MT5 named');
}

//--- security ---------------------------------------------------------------------------
// The pipe's owner and access list, read through a client connection as Windows reports them:
// owned as this user's token owns new objects (the user, or the Administrators group when it runs
// elevated, as on CI), NETWORK (another PC, over file sharing) denied first, this user allowed.
async function testPipeSecurity() {
  const e = env('acl');
  const h = startHost(e);
  await h.browser.next((f) => f.state === 'listening');
  const ps = "$c = New-Object System.IO.Pipes.NamedPipeClientStream('.', '" + e.ACTIONINNA_PIPE + "', [System.IO.Pipes.PipeDirection]::InOut);" +
    ' $c.Connect(3000); $a = $c.GetAccessControl(); $sid = [System.Security.Principal.SecurityIdentifier];' +
    " 'owner ' + $a.GetOwner($sid).Value; 'me ' + [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value;" +
    " 'tokenowner ' + [System.Security.Principal.WindowsIdentity]::GetCurrent().Owner.Value;" +
    " $a.GetAccessRules($true, $true, $sid) | ForEach-Object { 'rule ' + $_.IdentityReference.Value + ' ' + $_.AccessControlType }; $c.Dispose()";
  const r = spawnSync('powershell', ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(ps, 'utf16le').toString('base64')], { encoding: 'utf8' });
  const lines = (r.stdout || '').split(/\r?\n/).filter((l) => /^(owner|me|tokenowner|rule) /.test(l));
  const me = (lines.find((l) => l.startsWith('me ')) || '').slice(3);
  const tokenOwner = (lines.find((l) => l.startsWith('tokenowner ')) || '').slice(11);
  const rules = lines.filter((l) => l.startsWith('rule ')).map((l) => l.slice(5));
  // The link refuses a pipe whose owner isn't its token's owner (Host.NewPipe); this checks Windows agrees.
  expect(tokenOwner && lines.includes('owner ' + tokenOwner), 'the pipe is owned as this user\'s token owns new objects: ' + lines.join(' / '));
  expect(rules.length === 2 && rules[0] === 'S-1-5-2 Deny' && rules[1] === me + ' Allow',
         'the pipe denies NETWORK first and allows only this user: ' + rules.join(', '));
  h.child.stdin.end();
  await h.exited;
}

// A small seeded generator, so a failing run can be replayed with its seed.
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

const PIECES = ['a', 'Z', '0', ' ', '"', "'", '\\', '/', '{', '}', '[', ']', ':', ',', '\n', '\t', '\u0001', '\u001f', '\u007f', 'é', '€', '中',
  '\u{1F4B0}', '\ud800', '\udc00', ' ', '<script>', '</', '%00', '${x}', '__proto__', 'constructor'];

function randText(R, max) {
  let s = '';
  const n = R.int(0, max);
  for (let i = 0; i < n; i++) s += R.pick(PIECES);
  return s;
}

function randValue(R, depth) {
  const k = R.int(0, depth > 3 ? 5 : 7);
  if (k === 0) return R.int(-1e6, 1e6);
  if (k === 1) return R.pick([0, -0, 1.5, -2.25e-7, 1e300, -1e300, 4327679330, 9007199254740993, 0.1 + 0.2]);
  if (k === 2) return randText(R, 12);
  if (k === 3) return R.pick([true, false, null]);
  if (k === 4 || k === 5) return R.pick(['XAUUSDm', '', 'p1', '1']);
  if (k === 6) return Array.from({ length: R.int(0, 4) }, () => randValue(R, depth + 1));
  return randObject(R, depth + 1);
}

// Without a prototype, so a "__proto__" key is sent as a key, and never read back through one.
function randObject(R, depth) {
  const o = Object.create(null);
  const n = R.int(0, 5);
  for (let i = 0; i < n; i++) o[R.chance(0.5) ? R.pick(['t', 'id', 'term', 'preview', 'symbol', 'key', 'lots']) : randText(R, 6)] = randValue(R, depth);
  return o;
}

// What Chrome takes from the link: valid UTF-8 holding a JSON object with finite numbers and no lone
// surrogates, starting with '{'. The link must pass on an EA's frame exactly when it is that.
function chromeTakes(buf) {
  if (!buf.length || buf[0] !== 0x7b) return false;
  let text;
  try { text = new TextDecoder('utf-8', { fatal: true }).decode(buf); } catch (e) { return false; }
  let v;
  try { v = JSON.parse(text); } catch (e) { return false; }
  const ok = (x, depth) => {
    if (typeof x === 'number') return Number.isFinite(x);
    if (typeof x === 'string') return !/[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/.test(x);
    if (depth > 201) return false;
    if (Array.isArray(x)) return x.every((y) => ok(y, depth + 1));
    if (x && typeof x === 'object') return Object.keys(x).every((k) => ok(k, depth)) && Object.values(x).every((y) => ok(y, depth + 1));
    return true;
  };
  return v !== null && typeof v === 'object' && !Array.isArray(v) && ok(v, 1);
}

// The link's own words to the browser, which may come between the frames under test.
const isLinkState = (f) => f && f.t === 'link' && typeof f.state === 'string';

// What the link should make of an EA's JSON object: the same bytes with "term" put first.
function tagged(body, term) {
  let j = 1;
  while (j < body.length && (body[j] === 0x20 || body[j] === 0x09 || body[j] === 0x0d || body[j] === 0x0a)) j++;
  return Buffer.concat([Buffer.from('{"term":"' + term + '"' + (body[j] === 0x7d ? '' : ','), 'utf8'), body.slice(1)]);
}

// A frame an EA might send: valid JSON, or valid JSON broken in one of the ways a parser can be fooled.
function eaFrame(R) {
  let o = randObject(R, 0);
  if (o.t === 'terminal' || o.t === 'seq') o.t = 'x';
  let s = JSON.stringify(o);
  const how = R.int(0, 14);
  if (how === 1) s = s.slice(0, R.int(0, s.length - 1));
  else if (how === 2) { const i = R.int(0, s.length); s = s.slice(0, i) + R.pick([',', '}', ']', '"', '\\', 'x', '\u0001', "'", ':', '{']) + s.slice(i); }
  else if (how === 3) s = s.replace(/"/g, "'");
  else if (how === 4) s = R.pick([' ', '\n', '﻿']) + s;
  else if (how === 5) s = s + R.pick([' ', '\n', ' x', '{}', ',', ']']);
  else if (how === 6) s = '{' + R.pick(['a:1', '"a":01', '"a":.5', '"a":1.', '"a":+1', '"a":NaN', '"a":Infinity', '"a":1e400', '"a":-1e999', '"a":1,',
    '"a":"\\x41"', '"a":"\\u12"', '"a":"\\ud800"', '"a":"\\udc00x"', '"a":"\\ud83d\\ude00"', '"a":true,"b":nul', '"a":[1,]', '"a" 1', '}']) + '}';
  else if (how === 7) s = R.pick(['[]', '[{}]', '"x"', '1', 'null', '{}', '{ }', '{\n}', '{"a":{"b":{"c":[[[[]]]]}}}', '{"a":1}{"b":2}', '']);
  else if (how === 8) s = '{"d":' + '['.repeat(R.int(60, 70)) + ']'.repeat(R.int(60, 70)) + '}';
  let buf = Buffer.from(s, 'utf8');
  if (how === 9 && buf.length > 2) {
    const bad = R.pick([[0xff], [0xc3], [0xc0, 0xaf], [0xed, 0xa0, 0x80], [0xf4, 0x90, 0x80, 0x80], [0xe2, 0x82]]);
    const i = R.int(1, buf.length - 1);
    buf = Buffer.concat([buf.slice(0, i), Buffer.from(bad), buf.slice(i)]);
  }
  return buf;
}

// Differential fuzz: thousands of frames from Chrome and from an EA, each followed by a sentinel, and
// what the link passes on checked frame by frame against what it should pass on. Also: the key
// never reaches the browser, every frame the browser gets is one Chrome takes, broken pipe framing
// only drops that connection, and the link outlives all of it.
async function testFuzz(rounds, seed) {
  const R = prng(seed);
  const e = env('fuzz');
  const h = startHost(e);
  await h.browser.next((f) => f.state === 'listening');
  const key = fs.readFileSync(path.join(e.ACTIONINNA_COMMON, 'link.key'), 'ascii').trim();
  const ea = await connectEa(e);
  expect(ea, 'fuzz: an EA connects');
  if (!ea) { h.child.kill(); return; }
  await ea.r.next(() => true);
  ea.send({ t: 'terminal', login: 7, server: 'Fuzz' });
  await h.browser.next((f) => f.state === 'terminal-connected');
  await h.browser.next((f) => f.t === 'terminal');
  let checks = 0;
  const check = (ok, what) => { checks++; expect(ok, what); };

  // 1. Chrome to the EA: where each request goes.
  const terms = ['1', '2', '', 1, 2, null, undefined, '01', ' 1', true, ['1'], {}];
  const routes = (term) => term === '1' || term === 1 || term === '' || term === null || term === undefined;
  const sentFromChrome = [];
  const startEa = ea.r.raw.length;
  const startBrowser = h.browser.raw.length;
  for (let i = 0; i < rounds; i++) {
    const kind = R.int(0, 9);
    let body;
    let expectEa = false;
    let expectReply = null;
    let expectError = false;
    if (kind <= 6) {
      const o = randObject(R, 0);
      if (o.t === 'link.status' || o.t === 'link.start') o.t = 'x';
      delete o.term;
      delete o.id;
      const term = R.pick(terms);
      if (term !== undefined) o.term = term;
      if (R.chance(0.7)) o.id = R.int(1, 999999);
      body = JSON.stringify(o);
      expectEa = routes(term);
      if (!expectEa && o.id !== undefined) expectReply = o.id;
    } else if (kind === 7) {
      body = JSON.stringify(randValue(R, 5));
      if (body !== undefined && body.startsWith('{')) body = '[' + body + ']';
      expectError = true;
    } else {
      body = R.pick(['', '{', 'not json', '{"t":', '\u0000', '{"a":1}}', '[1,2', '"unterminated']) + randText(R, 20);
      // Anything but an object is answered with an error. What the link's lenient reader makes of
      // a broken object is left open: only liveness and well-formed output are checked for it.
      expectError = /^\s*\{/.test(body) ? null : true;
    }
    sentFromChrome.push({ i, body, expectEa, expectReply, expectError });
    h.child.stdin.write(frame(body));
    h.send({ term: '1', t: 'seq', n: i });
    h.send({ term: 'nobody', t: 'seq', id: 2000000 + i });
  }
  const t0 = Date.now();
  const last = await h.browser.next((f) => f.t === 'reply' && f.id === 2000000 + rounds - 1, 60000 + rounds * 50);
  const ms1 = Date.now() - t0;
  check(last, 'fuzz: the link answered all ' + rounds + ' frames from Chrome');
  await sleep(300);
  const eaGot = ea.r.raw.slice(startEa).map((b) => b.toString('utf8'));
  const brGot = h.browser.raw.slice(startBrowser).map((b) => { try { return JSON.parse(b.toString('utf8')); } catch (err) { return { unparsed: true }; } })
    .filter((f) => !isLinkState(f));
  let ei = 0;
  let bi = 0;
  for (const s of sentFromChrome) {
    if (s.expectError === null && eaGot[ei] === s.body) ei++;
    if (s.expectEa) {
      check(eaGot[ei] === s.body, 'fuzz ' + s.i + ': a request for terminal 1 reaches it byte for byte: ' + JSON.stringify(s.body).slice(0, 120));
      if (eaGot[ei] === s.body) ei++;
    }
    const seqEa = eaGot[ei] ? JSON.parse(eaGot[ei]) : null;
    check(seqEa && seqEa.t === 'seq' && seqEa.n === s.i, 'fuzz ' + s.i + ': nothing else reaches the EA (got ' + String(eaGot[ei]).slice(0, 120) + ')');
    ei++;
    if (s.expectError === true) {
      check(brGot[bi] && brGot[bi].t === 'error', 'fuzz ' + s.i + ': a frame that is not a JSON object gets an error: ' + JSON.stringify(s.body).slice(0, 80));
      bi++;
    } else if (s.expectError === null && brGot[bi] && brGot[bi].t === 'error') bi++;
    if (s.expectReply !== null) {
      check(brGot[bi] && brGot[bi].t === 'reply' && brGot[bi].id === s.expectReply && brGot[bi].ok === false,
            'fuzz ' + s.i + ': a request for no connected terminal is answered: ' + JSON.stringify(brGot[bi]));
      bi++;
    } else if (s.expectError === null && brGot[bi] && brGot[bi].t === 'reply' && brGot[bi].id !== 2000000 + s.i) bi++;
    check(brGot[bi] && brGot[bi].t === 'reply' && brGot[bi].id === 2000000 + s.i, 'fuzz ' + s.i + ': and nothing else is said to the browser: ' + JSON.stringify(brGot[bi]));
    bi++;
  }

  // 2. An EA to Chrome: only frames Chrome takes are passed on, with the EA's term added.
  const startBrowser2 = h.browser.raw.length;
  const sentFromEa = [];
  for (let i = 0; i < rounds; i++) {
    const buf = eaFrame(R);
    sentFromEa.push({ i, buf, pass: chromeTakes(buf) });
    const head = Buffer.alloc(4);
    head.writeUInt32LE(buf.length, 0);
    ea.sock.write(Buffer.concat([head, buf]));
    ea.send({ t: 'seq', n: i });
  }
  const t1 = Date.now();
  await h.browser.next((f) => f.t === 'seq' && f.n === rounds - 1, 60000 + rounds * 50);
  const ms2 = Date.now() - t1;
  await sleep(300);
  const got2 = h.browser.raw.slice(startBrowser2).filter((b) => {
    try { return !isLinkState(JSON.parse(b.toString('utf8'))); } catch (err) { return true; }
  });
  let gi = 0;
  let passed = 0;
  for (const s of sentFromEa) {
    const g = got2[gi];
    check(g && chromeTakes(g), 'fuzz ' + s.i + ': every frame the browser gets is one Chrome takes: ' + (g ? g.toString('utf8').slice(0, 120) : 'none'));
    if (s.pass) {
      check(g && g.equals(tagged(s.buf, '1')), 'fuzz ' + s.i + ': a valid frame is passed on byte for byte, with its term: ' + s.buf.toString('utf8').slice(0, 120) +
            ' -> ' + (g ? g.toString('utf8').slice(0, 120) : 'none'));
      gi++;
      passed++;
    }
    const seq = got2[gi] ? (() => { try { return JSON.parse(got2[gi].toString('utf8')); } catch (err) { return null; } })() : null;
    check(seq && seq.t === 'seq' && seq.n === s.i && seq.term === '1', 'fuzz ' + s.i + ': a frame Chrome would refuse is dropped, not passed on: ' +
          JSON.stringify(s.buf.toString('utf8')).slice(0, 120) + ' -> ' + (got2[gi] ? got2[gi].toString('utf8').slice(0, 80) : 'none'));
    gi++;
  }
  check(passed > rounds / 4 && passed < rounds, 'fuzz: the EA frames were a mix of valid and broken (' + passed + ' of ' + rounds + ' valid)');
  check(!ea.closed(), 'fuzz: the EA stays connected through frames it should not have sent');

  // 3. Broken framing on other connections: each is dropped, the first EA and the link go on.
  const framings = [
    () => { const b = Buffer.alloc(4); b.writeInt32LE(-1, 0); return b; },
    () => { const b = Buffer.alloc(4); b.writeUInt32LE(1024 * 1024 + 1, 0); return b; },
    () => { const b = Buffer.alloc(4); b.writeUInt32LE(0x7fffffff, 0); return b; },
    () => Buffer.concat([frame({ t: 'x' }).slice(0, 7)]),
    () => Buffer.from([1, 0]),
  ];
  for (let k = 0; k < framings.length * 4; k++) {
    const bad = await connectEa(e);
    if (!bad) { check(false, 'fuzz: a second connection opens'); continue; }
    await bad.r.next(() => true);
    bad.sock.write(framings[k % framings.length]());
    if (k % framings.length >= 3) bad.sock.end();
    await sleep(80);
  }
  await sleep(300);
  h.send({ term: '1', t: 'seq', n: -1 });
  check(await ea.r.next((f) => f.t === 'seq' && f.n === -1), 'fuzz: after broken framing on other connections, terminal 1 is still served');

  const all = Buffer.concat(h.browser.raw).toString('latin1');
  check(!all.includes(key), 'fuzz: the key never reaches the browser');
  check(h.browser.raw.every((b) => chromeTakes(b)), 'fuzz: all ' + h.browser.raw.length + ' frames to the browser are ones Chrome takes');

  // 4. Last: a frame over 1 MiB from the browser ends the link (the browser starts it again).
  const head = Buffer.alloc(4);
  head.writeUInt32LE(1024 * 1024 + 1, 0);
  h.child.stdin.write(head);
  const code = await Promise.race([h.exited, sleep(5000).then(() => 'still running')]);
  check(code === 0, 'fuzz: a frame over 1 MiB from the browser ends the link: ' + code);
  if (code === 'still running') h.child.kill();
  console.log('link fuzz: ' + checks + ' checks over ' + rounds + ' frames each way (seed ' + seed + '; ' + ms1 + ' ms and ' + ms2 + ' ms)');
}

(async () => {
  if (!fs.existsSync(exe)) {
    console.log('Build the link first: ' + exe + ' is missing');
    process.exit(1);
  }
  fs.mkdirSync(out, { recursive: true });
  await testRouting();
  await testMt5Start();
  testInstaller();
  await testPipeSecurity();
  await testFuzz(Number(process.env.FUZZ_ROUNDS) || 5000, Number(process.env.FUZZ_SEED) || 20261026);
  console.log('link program: ' + (pass + fail) + ' checks, ' + fail + ' failed');
  // A failed run keeps its files (link.log) for a look.
  if (!fail) try { fs.rmSync(out, { recursive: true, force: true }); } catch (err) { /* a junction or a file still open */ }
  process.exit(fail ? 1 : 0);
})();
