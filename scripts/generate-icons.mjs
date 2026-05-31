import { mkdir, writeFile } from "node:fs/promises";
import { createDeflate } from "node:zlib";
import { once } from "node:events";
import path from "node:path";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const extensionDir = path.join(root, "apps/chrome-extension/icons");
const storeAssetsDir = path.join(root, "store-assets/chrome-web-store");
const websiteDir = path.join(root, "website/assets");
const iconsetDir = path.join(root, "dist/Tacket.iconset");

await mkdir(extensionDir, { recursive: true });
await mkdir(storeAssetsDir, { recursive: true });
await mkdir(websiteDir, { recursive: true });
await mkdir(iconsetDir, { recursive: true });

for (const size of [16, 32, 48, 128]) {
  await writeFile(path.join(extensionDir, `tacket-${size}.png`), await renderPng(size));
}

await writeFile(path.join(websiteDir, "icon-180.png"), await renderPng(180));
await writeFile(path.join(websiteDir, "favicon.png"), await renderPng(32));
await writeFile(path.join(storeAssetsDir, "small-promo-440x280.png"), await renderPromoPng(440, 280));

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
  return pngFromPixels(size, size, renderIconAtSize(size));
}

async function renderPromoPng(width, height) {
  const pixels = Buffer.alloc(width * height * 4);
  const bg = [0xf8, 0xf7, 0xf4, 0xff];
  const accent = [0x24, 0x5f, 0x73, 0xff];
  const ink = [0x15, 0x15, 0x15, 0xff];
  const muted = [0x5f, 0x63, 0x68, 0xff];
  const line = [0xdd, 0xd8, 0xce, 0xff];
  const tack = [0xd9, 0xb4, 0x5b, 0xff];

  fill(pixels, width, height, bg);
  drawRect(pixels, width, height, 0, 0, width, 12, accent);
  drawRoundedRect(pixels, width, height, 34, 52, 174, 174, 36, [0xff, 0xff, 0xff, 0xff]);
  drawIcon(pixels, width, height, 57, 75, 128);

  drawRoundedRect(pixels, width, height, 236, 54, 156, 28, 8, accent);
  drawRoundedRect(pixels, width, height, 236, 98, 116, 14, 5, ink);
  drawRoundedRect(pixels, width, height, 236, 126, 136, 10, 5, muted);
  drawRoundedRect(pixels, width, height, 236, 148, 122, 10, 5, muted);

  drawRoundedRect(pixels, width, height, 236, 184, 56, 20, 6, tack);
  drawRoundedRect(pixels, width, height, 304, 184, 86, 20, 6, line);
  drawRoundedRect(pixels, width, height, 236, 224, 154, 2, 1, line);

  drawRoundedRect(pixels, width, height, 32, 238, 376, 10, 5, line);
  drawRoundedRect(pixels, width, height, 32, 238, 250, 10, 5, accent);

  return pngFromPixels(width, height, pixels);
}

function renderIconPixels(size) {
  const pixels = Buffer.alloc(size * size * 4);
  const radius = size * 0.22;
  const bg = [0x07, 0x5a, 0x91, 0xff];
  const paper = [0xfb, 0xfa, 0xf7, 0xff];
  const rule = [0xd7, 0xda, 0xda, 0xff];
  const brass = [0xff, 0xd0, 0x6a, 0xff];
  const brassLight = [0xff, 0xf1, 0xb6, 0xff];
  const brassDark = [0xff, 0xc0, 0x48, 0xff];
  const transparent = [0, 0, 0, 0];

  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      let color = roundedRectContains(x, y, size, size, radius, size) ? bg : transparent;

      if (inTriangle(x, y, size, 0.627, 0.643, 0.654, 0.615, 0.803, 0.791)) color = brass;
      if (inTriangle(x, y, size, 0.641, 0.629, 0.654, 0.615, 0.803, 0.791)) color = brassDark;
      if (inSoftRotatedRect(x, y, size, 0.498, 0.501, 0.64, 0.38, 0, 0.047)) color = paper;
      if (inRect(x, y, size, 0.326, 0.426, 0.34, 0.02)) color = rule;
      if (inRect(x, y, size, 0.326, 0.5, 0.34, 0.02)) color = rule;
      if (inRect(x, y, size, 0.326, 0.575, 0.34, 0.02)) color = rule;
      if (inTriangle(x, y, size, 0.416, 0.436, 0.436, 0.416, 0.506, 0.491)) color = brass;
      if (inTriangle(x, y, size, 0.416, 0.436, 0.506, 0.491, 0.486, 0.51)) color = brass;
      if (inTriangle(x, y, size, 0.436, 0.416, 0.506, 0.491, 0.496, 0.5)) color = brassDark;
      if (inCircle(x, y, size, 0.33, 0.342, 0.17)) color = brass;
      if (inCircle(x, y, size, 0.271, 0.283, 0.03)) color = brassLight;
      const offset = (y * size + x) * 4;
      pixels[offset] = color[0];
      pixels[offset + 1] = color[1];
      pixels[offset + 2] = color[2];
      pixels[offset + 3] = color[3];
    }
  }

  return pixels;
}

function renderIconAtSize(size) {
  const scale = size <= 64 ? 4 : 2;
  return downsamplePixels(renderIconPixels(size * scale), size * scale, size * scale, size, size);
}

async function pngFromPixels(width, height, pixels) {
  const rowStride = width * 4 + 1;
  const raw = Buffer.alloc(rowStride * height);
  for (let y = 0; y < height; y += 1) {
    const rowStart = y * rowStride;
    raw[rowStart] = 0;
    pixels.copy(raw, rowStart + 1, y * width * 4, (y + 1) * width * 4);
  }

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr(width, height)),
    chunk("IDAT", await deflate(raw)),
    chunk("IEND", Buffer.alloc(0))
  ]);
}

function fill(pixels, width, height, color) {
  drawRect(pixels, width, height, 0, 0, width, height, color);
}

function drawIcon(pixels, canvasWidth, canvasHeight, left, top, size) {
  const icon = renderIconAtSize(size);
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const source = (y * size + x) * 4;
      const alpha = icon[source + 3] / 255;
      if (alpha === 0) continue;
      blendPixel(
        pixels,
        canvasWidth,
        canvasHeight,
        left + x,
        top + y,
        [icon[source], icon[source + 1], icon[source + 2], icon[source + 3]]
      );
    }
  }
}

function drawRoundedRect(pixels, canvasWidth, canvasHeight, left, top, width, height, radius, color) {
  for (let y = Math.floor(top); y < Math.ceil(top + height); y += 1) {
    for (let x = Math.floor(left); x < Math.ceil(left + width); x += 1) {
      if (roundedRectContains(x - left, y - top, width, height, radius)) {
        blendPixel(pixels, canvasWidth, canvasHeight, x, y, color);
      }
    }
  }
}

function drawRect(pixels, canvasWidth, canvasHeight, left, top, width, height, color) {
  for (let y = Math.max(0, Math.floor(top)); y < Math.min(canvasHeight, Math.ceil(top + height)); y += 1) {
    for (let x = Math.max(0, Math.floor(left)); x < Math.min(canvasWidth, Math.ceil(left + width)); x += 1) {
      blendPixel(pixels, canvasWidth, canvasHeight, x, y, color);
    }
  }
}

function blendPixel(pixels, width, height, x, y, color) {
  if (x < 0 || y < 0 || x >= width || y >= height) return;
  const offset = (Math.floor(y) * width + Math.floor(x)) * 4;
  const alpha = color[3] / 255;
  pixels[offset] = Math.round(color[0] * alpha + pixels[offset] * (1 - alpha));
  pixels[offset + 1] = Math.round(color[1] * alpha + pixels[offset + 1] * (1 - alpha));
  pixels[offset + 2] = Math.round(color[2] * alpha + pixels[offset + 2] * (1 - alpha));
  pixels[offset + 3] = Math.max(pixels[offset + 3], color[3]);
}

function inRect(x, y, size, left, top, width, height) {
  return x >= size * left && x <= size * (left + width) &&
    y >= size * top && y <= size * (top + height);
}

function inCircle(x, y, size, centerX, centerY, radius) {
  return (x - size * centerX) ** 2 + (y - size * centerY) ** 2 <= (size * radius) ** 2;
}

function inTriangle(x, y, size, ax, ay, bx, by, cx, cy) {
  const px = x / size;
  const py = y / size;
  const d1 = triangleSign(px, py, ax, ay, bx, by);
  const d2 = triangleSign(px, py, bx, by, cx, cy);
  const d3 = triangleSign(px, py, cx, cy, ax, ay);
  const hasNegative = d1 < 0 || d2 < 0 || d3 < 0;
  const hasPositive = d1 > 0 || d2 > 0 || d3 > 0;
  return !(hasNegative && hasPositive);
}

function triangleSign(px, py, ax, ay, bx, by) {
  return (px - bx) * (ay - by) - (ax - bx) * (py - by);
}

function inSoftRotatedRect(x, y, size, centerX, centerY, width, height, angle, radius) {
  const dx = x / size - centerX;
  const dy = y / size - centerY;
  const cos = Math.cos(-angle);
  const sin = Math.sin(-angle);
  const rx = dx * cos - dy * sin + width / 2;
  const ry = dx * sin + dy * cos + height / 2;
  return roundedRectContains(rx * size, ry * size, width * size, height * size, radius * size);
}

function roundedRectContains(x, y, width, height, radius) {
  const cx = x < radius ? radius : x > width - radius ? width - radius : x;
  const cy = y < radius ? radius : y > height - radius ? height - radius : y;
  return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2;
}

function mix(start, end, amount) {
  return [
    Math.round(start[0] * (1 - amount) + end[0] * amount),
    Math.round(start[1] * (1 - amount) + end[1] * amount),
    Math.round(start[2] * (1 - amount) + end[2] * amount),
    0xff
  ];
}

function downsamplePixels(source, sourceWidth, sourceHeight, width, height) {
  const pixels = Buffer.alloc(width * height * 4);
  const scaleX = sourceWidth / width;
  const scaleY = sourceHeight / height;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      let red = 0;
      let green = 0;
      let blue = 0;
      let alpha = 0;
      let count = 0;
      for (let sy = Math.floor(y * scaleY); sy < Math.floor((y + 1) * scaleY); sy += 1) {
        for (let sx = Math.floor(x * scaleX); sx < Math.floor((x + 1) * scaleX); sx += 1) {
          const sourceOffset = (sy * sourceWidth + sx) * 4;
          red += source[sourceOffset];
          green += source[sourceOffset + 1];
          blue += source[sourceOffset + 2];
          alpha += source[sourceOffset + 3];
          count += 1;
        }
      }
      const offset = (y * width + x) * 4;
      pixels[offset] = Math.round(red / count);
      pixels[offset + 1] = Math.round(green / count);
      pixels[offset + 2] = Math.round(blue / count);
      pixels[offset + 3] = Math.round(alpha / count);
    }
  }
  return pixels;
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
