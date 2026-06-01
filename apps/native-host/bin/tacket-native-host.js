#!/usr/bin/env node
import os from "node:os";
import path from "node:path";
import { mkdir, readFile } from "node:fs/promises";
import { writeBundle } from "@tacket/thread-format";

main().catch((error) => {
  writeNativeMessage({ ok: false, error: error?.message ?? String(error) });
});

async function main() {
  const message = await readNativeMessage();
  if (message?.type !== "saveCapture") {
    writeNativeMessage({ ok: false, error: "Unsupported native host message." });
    return;
  }

  const outputRoot = await captureDirectory();
  await mkdir(outputRoot, { recursive: true });
  const result = await writeBundle(message.capture, outputRoot);
  writeNativeMessage({
    ok: true,
    bundlePath: result.bundlePath,
    transcriptPath: result.transcriptPath,
    manifest: result.manifest
  });
}

async function readNativeMessage() {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let settled = false;

    function finish(fn, value) {
      if (settled) return;
      settled = true;
      process.stdin.pause();
      process.stdin.removeAllListeners("data");
      process.stdin.removeAllListeners("end");
      process.stdin.removeAllListeners("error");
      fn(value);
    }

    process.stdin.on("data", (chunk) => {
      if (settled) return;
      chunks.push(chunk);
      const buffer = Buffer.concat(chunks);
      if (buffer.length < 4) return;
      const length = buffer.readUInt32LE(0);
      const expectedLength = 4 + length;
      if (buffer.length < expectedLength) return;
      if (buffer.length > expectedLength) {
        finish(reject, new Error("Native host expected exactly one native message."));
        return;
      }
      const body = buffer.subarray(4, 4 + length).toString("utf8");
      try {
        finish(resolve, JSON.parse(body));
      } catch (error) {
        finish(reject, error);
      }
    });

    process.stdin.on("end", () => {
      if (settled) return;
      const buffer = Buffer.concat(chunks);
      if (buffer.length < 4) {
        finish(reject, new Error("No native message received."));
        return;
      }
      finish(reject, new Error("Native message body was shorter than declared length."));
    });

    process.stdin.on("error", (error) => finish(reject, error));
    process.stdin.resume();
  });
}

function writeNativeMessage(message) {
  const body = Buffer.from(JSON.stringify(message), "utf8");
  const header = Buffer.alloc(4);
  header.writeUInt32LE(body.length, 0);
  process.stdout.write(Buffer.concat([header, body]));
}

function expandHome(value) {
  if (value === "~") return os.homedir();
  if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2));
  return value;
}

async function captureDirectory() {
  if (process.env.TACKET_CAPTURE_DIR) return expandHome(process.env.TACKET_CAPTURE_DIR);

  const configPath = process.env.TACKET_CONFIG_FILE
    ? expandHome(process.env.TACKET_CONFIG_FILE)
    : path.join(os.homedir(), "Library", "Application Support", "Tacket", "config.json");

  try {
    const config = JSON.parse(await readFile(configPath, "utf8"));
    if (config.captureDirectory) return expandHome(String(config.captureDirectory));
  } catch {
    // Missing or malformed config falls back to the default save folder.
  }

  return path.join(os.homedir(), "Documents", "Tacket Captures");
}
