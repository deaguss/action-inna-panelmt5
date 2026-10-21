// Copies the MQL5 sources into out/src with the few changes g++ needs, so the real code can be
// compiled against mql.h (a fake MT5). The sources themselves are never modified.
//   - string literals become string("..."), so "a" + b concatenates as it does in MQL5
//   - C'r,g,b' colour literals become AI_RGB(r,g,b)
//   - dynamic arrays (T name[] and T &name[]) become MqlArray<T>, which checks every index
//   - #property, input group and the input keyword are dropped; include paths use forward slashes
'use strict';
const fs = require('fs');
const path = require('path');

const repo = path.resolve(__dirname, '..', '..');
const srcRoot = path.join(repo, 'mql5');
const outRoot = path.join(__dirname, 'out', 'src');

function walk(dir) {
  let files = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) files = files.concat(walk(p));
    else if (/\.(mqh|mq5)$/.test(e.name)) files.push(p);
  }
  return files;
}

// Wraps string literals and rewrites colour literals in one line of code, leaving comments alone.
// inBlock carries an open /* comment */ over to the next line.
function codeLine(line, state) {
  let out = '';
  let i = 0;
  while (i < line.length) {
    if (state.inBlock) {
      const end = line.indexOf('*/', i);
      if (end < 0) { out += line.slice(i); return out; }
      out += line.slice(i, end + 2);
      i = end + 2;
      state.inBlock = false;
      continue;
    }
    const c = line[i];
    if (c === '/' && line[i + 1] === '/') { out += line.slice(i); break; }
    if (c === '/' && line[i + 1] === '*') { state.inBlock = true; out += '/*'; i += 2; continue; }
    if (c === '"') {
      let j = i + 1;
      while (j < line.length && line[j] !== '"') j += (line[j] === '\\') ? 2 : 1;
      out += 'string(' + line.slice(i, j + 1) + ')';
      i = j + 1;
      continue;
    }
    if (c === 'C' && line[i + 1] === "'" && !/[A-Za-z0-9_]/.test(line[i - 1] || '')) {
      const end = line.indexOf("'", i + 2);
      out += 'AI_RGB(' + line.slice(i + 2, end) + ')';
      i = end + 1;
      continue;
    }
    if (c === "'") {
      let j = i + 1;
      while (j < line.length && line[j] !== "'") j += (line[j] === '\\') ? 2 : 1;
      out += line.slice(i, j + 1);
      i = j + 1;
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

function transform(text) {
  const state = { inBlock: false };
  const out = [];
  for (let line of text.split(/\r?\n/)) {
    if (/^\s*#property\b/.test(line) || /^\s*input\s+group\b/.test(line)) { out.push(''); continue; }
    const inc = line.match(/^(\s*#include\s+)<([^>]+)>/);
    if (inc) { out.push(inc[1] + '<' + inc[2].replace(/\\/g, '/') + '>'); continue; }
    if (/^\s*#include\s+"/.test(line)) { out.push(line); continue; }
    line = line.replace(/^(\s*)(?:input|sinput)\s+/, '$1');
    // Array parameters: T &name[] and const T &name[].
    line = line.replace(/\b([A-Za-z_]\w*)\s*&\s*([A-Za-z_]\w*)\s*\[\s*\]/g, 'MqlArray<$1> &$2');
    // Array declarations: T name[];
    line = line.replace(/^(\s*)([A-Za-z_]\w*)\s+([A-Za-z_]\w*)\s*\[\s*\]\s*;/, '$1MqlArray<$2> $3;');
    out.push(codeLine(line, state));
  }
  return out.join('\n');
}

let count = 0;
for (const file of walk(srcRoot)) {
  const rel = path.relative(srcRoot, file);
  const dest = path.join(outRoot, rel);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, transform(fs.readFileSync(file, 'utf8')));
  count++;
}
console.log('mql2cpp: ' + count + ' files -> ' + path.relative(repo, outRoot));
