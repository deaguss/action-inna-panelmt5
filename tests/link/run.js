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
  function next(pred, ms = 4000) {
    return new Promise((resolve) => {
      const t0 = Date.now();
      let done = false;
      const check = () => {
        if (done) return;
        const i = frames.findIndex(pred);
        if (i >= 0) { done = true; resolve(frames.splice(i, 1)[0]); return; }
        if (Date.now() - t0 > ms) { done = true; resolve(null); return; }
        waiters.push(check);
        setTimeout(check, 50);
      };
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
  expect(manifest && manifest.allowed_origins.includes('chrome-extension://' + DEV_ID + '/') &&
         manifest.allowed_origins.includes('chrome-extension://abcdefghijklmnopabcdefghijklmnop/') && manifest.allowed_origins.length === 2,
         'install: only the extension ids are allowed');
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
  const devCfg = JSON.parse(fs.readFileSync(path.join(devEnv.ACTIONINNA_HOME, 'link.json'), 'utf8'));
  expect(devCfg.terminals.length === 1, '--mt5: only the MT5 named');
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
  console.log('link program: ' + (pass + fail) + ' checks, ' + fail + ' failed');
  try { fs.rmSync(out, { recursive: true, force: true }); } catch (err) { /* a junction or a file still open */ }
  process.exit(fail ? 1 : 0);
})();
