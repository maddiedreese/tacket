import { mkdir, writeFile } from "node:fs/promises";
import { createDeflate } from "node:zlib";
import { once } from "node:events";
import path from "node:path";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const extensionDir = path.join(root, "apps/chrome-extension/icons");
const websiteDir = path.join(root, "website/assets");
const iconsetDir = path.join(root, "dist/Tacket.iconset");

await mkdir(extensionDir, { recursive: true });
await mkdir(websiteDir, { recursive: true });
await mkdir(iconsetDir, { recursive: true });

for (const size of [16, 32, 48, 128]) {
  await writeFile(path.join(extensionDir, `tacket-${size}.png`), await renderPng(size));
}

await writeFile(path.join(websiteDir, "icon-180.png"), await renderPng(180));
await writeFile(path.join(websiteDir, "favicon.png"), await renderPng(32));

const iconsetSizes = [
  ["icon_16x16.png", 16],
  ["icon_16x16@2x.png", 32],
  ["icon_32x32.png", 32],
  ["icon_32x32@2x.png", 64],
  ["icon_128x128.png", 128],
  ["icon_128x128@2x.png", 256],
  ["icon_256x256.png", 256],
  ["icon_256x256@2x.png", 512],
  ["icon_512x512.png", 512],
  ["icon_512x512@2x.png", 1024]
];

for (const [name, size] of iconsetSizes) {
  await writeFile(path.join(iconsetDir, name), await renderPng(size));
}

console.log("Generated Tacket icons.");

async function renderPng(size) {
  const pixels = Buffer.alloc(size * size * 4);
  const radius = size * 0.22;
  const bg = [0x24, 0x5f, 0x73, 0xff];
  const paper = [0xf8, 0xf7, 0xf4, 0xff];
  const tack = [0xd9, 0xc8, 0x8f, 0xff];
  const transparent = [0, 0, 0, 0];

  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      let color = roundedRectContains(x, y, size, size, radius, size) ? bg : transparent;
      if (inRect(x, y, size, 0.27, 0.28, 0.46, 0.11)) color = paper;
      if (inRect(x, y, size, 0.445, 0.36, 0.11, 0.36)) color = paper;
      if (inRect(x, y, size, 0.28, 0.50, 0.44, 0.07)) color = [0xf8, 0xf7, 0xf4, 0xea];
      if (inRect(x, y, size, 0.28, 0.63, 0.19, 0.09)) color = tack;
      if (inRect(x, y, size, 0.525, 0.63, 0.19, 0.09)) color = tack;
      const offset = (y * size + x) * 4;
      pixels[offset] = color[0];
      pixels[offset + 1] = color[1];
      pixels[offset + 2] = color[2];
      pixels[offset + 3] = color[3];
    }
  }

  const raw = Buffer.alloc((size * 4 + 1) * size);
  for (let y = 0; y < size; y += 1) {
    const rowStart = y * (size * 4 + 1);
    raw[rowStart] = 0;
    pixels.copy(raw, rowStart + 1, y * size * 4, (y + 1) * size * 4);
  }

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr(size, size)),
    chunk("IDAT", await deflate(raw)),
    chunk("IEND", Buffer.alloc(0))
  ]);
}

function inRect(x, y, size, left, top, width, height) {
  return x >= size * left && x <= size * (left + width) &&
    y >= size * top && y <= size * (top + height);
}

function roundedRectContains(x, y, width, height, radius) {
  const cx = x < radius ? radius : x > width - radius ? width - radius : x;
  const cy = y < radius ? radius : y > height - radius ? height - radius : y;
  return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2;
}

function ihdr(width, height) {
  const buffer = Buffer.alloc(13);
  buffer.writeUInt32BE(width, 0);
  buffer.writeUInt32BE(height, 4);
  buffer[8] = 8;
  buffer[9] = 6;
  buffer[10] = 0;
  buffer[11] = 0;
  buffer[12] = 0;
  return buffer;
}

async function deflate(buffer) {
  const stream = createDeflate();
  const chunks = [];
  stream.on("data", (chunk) => chunks.push(chunk));
  stream.end(buffer);
  await once(stream, "end");
  return Buffer.concat(chunks);
}

function chunk(type, data) {
  const typeBuffer = Buffer.from(type, "ascii");
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const crcBuffer = Buffer.alloc(4);
  crcBuffer.writeUInt32BE(crc(Buffer.concat([typeBuffer, data])), 0);
  return Buffer.concat([length, typeBuffer, data, crcBuffer]);
}

function crc(buffer) {
  let value = 0xffffffff;
  for (const byte of buffer) {
    value ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      value = value & 1 ? (value >>> 1) ^ 0xedb88320 : value >>> 1;
    }
  }
  return (value ^ 0xffffffff) >>> 0;
}
