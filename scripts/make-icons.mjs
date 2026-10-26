// Draws the side panel's icons, extension/icons/icon{16,32,48,128}.png: a long-position box, the
// take profit above the entry line and the stop loss below it, at 2R, in the colours of DESIGN.md.
// The 128 px one keeps 16 px clear around it, as the Chrome Web Store asks. No dependencies:
//   node scripts/make-icons.mjs
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';

const out = join(dirname(fileURLToPath(import.meta.url)), '..', 'extension', 'icons');
const TILE = [23, 25, 31];     // panel, dark theme
const TP = [22, 124, 74];      // TP tag
const SL = [200, 48, 62];      // SELL fill and SL tag
const ENTRY = [232, 234, 239]; // text, dark theme

const CRC = new Uint32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});

function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = CRC[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const head = Buffer.alloc(4);
  head.writeUInt32BE(data.length);
  const tail = Buffer.alloc(4);
  tail.writeUInt32BE(crc32(body));
  return Buffer.concat([head, body, tail]);
}

// RGBA pixels to a PNG file: 8 bits per channel, no filtering.
function png(size, px) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const row = size * 4 + 1;
  const raw = Buffer.alloc(size * row);
  for (let y = 0; y < size; y++) px.copy(raw, y * row + 1, y * size * 4, (y + 1) * size * 4);
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

function icon(size, pad) {
  const px = Buffer.alloc(size * size * 4);
  const fill = (x0, y0, x1, y1, c) => {
    for (let y = y0; y < y1; y++) {
      for (let x = x0; x < x1; x++) {
        const i = (y * size + x) * 4;
        px[i] = c[0];
        px[i + 1] = c[1];
        px[i + 2] = c[2];
        px[i + 3] = 255;
      }
    }
  };
  const t0 = pad;
  const t1 = size - pad;
  fill(t0, t0, t1, t1, TILE);
  const margin = Math.max(2, Math.round((t1 - t0) * 0.17));
  const x0 = t0 + margin;
  const x1 = t1 - margin;
  const y0 = t0 + margin;
  const y1 = t1 - margin;
  const line = Math.max(1, Math.round((t1 - t0) / 16));
  const sl = Math.max(2, Math.round((y1 - y0 - line) / 3));
  const entry = y1 - sl - line;
  fill(x0, y0, x1, entry, TP);
  fill(x0, entry, x1, entry + line, ENTRY);
  fill(x0, entry + line, x1, y1, SL);
  return png(size, px);
}

mkdirSync(out, { recursive: true });
for (const [size, pad] of [[16, 0], [32, 0], [48, 0], [128, 16]]) {
  writeFileSync(join(out, 'icon' + size + '.png'), icon(size, pad));
}
console.log('icons written to ' + out);
