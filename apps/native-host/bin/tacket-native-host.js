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
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  const buffer = Buffer.concat(chunks);
  if (buffer.length < 4) throw new Error("No native message received.");
  const length = buffer.readUInt32LE(0);
  const expectedLength = 4 + length;
  if (buffer.length < expectedLength) {
    throw new Error("Native message body was shorter than declared length.");
  }
  if (buffer.length > expectedLength) {
    throw new Error("Native host expected exactly one native message.");
  }
  const body = buffer.subarray(4, 4 + length).toString("utf8");
  return JSON.parse(body);
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
    // Missing or malformed config falls back to the default capture folder.
  }

  return path.join(os.homedir(), "Documents", "Tacket Captures");
}
