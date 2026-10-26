// Serves extension/ on 127.0.0.1 for working on the side panel in a plain browser tab, where
// extension/dev/mock.js stands in for the link and MT5:
//   node tests/extension/serve.js [port]    then open http://127.0.0.1:8137/panel.html
// The page's address picks a scene (see dev/mock.js), for example /panel.html?terms=2.
'use strict';
const fs = require('fs');
const http = require('http');
const path = require('path');

const root = path.resolve(__dirname, '..', '..', 'extension');
const port = Number(process.argv[2]) || 8137;
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
};

http.createServer((req, res) => {
  let rel;
  try {
    rel = decodeURIComponent(new URL(req.url, 'http://127.0.0.1').pathname);
  } catch (e) {
    res.writeHead(400).end();
    return;
  }
  if (rel === '/') {
    res.writeHead(302, { Location: '/panel.html' }).end();
    return;
  }
  const file = path.join(root, path.normalize(rel));
  if (!file.startsWith(root + path.sep)) {
    res.writeHead(403).end();
    return;
  }
  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Not found');
      return;
    }
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(data);
  });
}).listen(port, '127.0.0.1', () => console.log('side panel: http://127.0.0.1:' + port + '/panel.html'));
