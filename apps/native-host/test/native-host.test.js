import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { test } from "node:test";

const hostPath = path.resolve("apps/native-host/bin/tacket-native-host.js");

test("native host rejects missing capture payload", async () => {
  const outputRoot = await mkdtemp(path.join(os.tmpdir(), "tacket-node-host-"));
  try {
    const response = await sendNativeMessage({ type: "saveCapture" }, outputRoot);
    assert.equal(response.ok, false);
    assert.match(response.error, /Capture payload must be a JSON object/);
  } finally {
    await rm(outputRoot, { recursive: true, force: true });
  }
});

test("native host rejects empty captures before writing a bundle", async () => {
  const outputRoot = await mkdtemp(path.join(os.tmpdir(), "tacket-node-host-"));
  try {
    const response = await sendNativeMessage({
      type: "saveCapture",
      capture: { title: "Empty", source: { url: "https://chatgpt.com/c/empty" }, messages: [] }
    }, outputRoot);
    assert.equal(response.ok, false);
    assert.match(response.error, /at least one message/);
  } finally {
    await rm(outputRoot, { recursive: true, force: true });
  }
});

test("native host honors configured capture directory", async () => {
  const configuredRoot = await mkdtemp(path.join(os.tmpdir(), "tacket-node-host-configured-"));
  const configRoot = await mkdtemp(path.join(os.tmpdir(), "tacket-node-host-config-"));
  const configFile = path.join(configRoot, "config.json");
  try {
    await writeConfig(configFile, configuredRoot);
    const response = await sendNativeMessage(validCapture("Configured"), { configFile });
    assert.equal(response.ok, true, response.error);
    assert.equal(response.bundlePath.startsWith(configuredRoot), true);
  } finally {
    await rm(configuredRoot, { recursive: true, force: true });
    await rm(configRoot, { recursive: true, force: true });
  }
});

test("native host capture directory environment override wins over config file", async () => {
  const configuredRoot = await mkdtemp(path.join(os.tmpdir(), "tacket-node-host-configured-"));
  const overrideRoot = await mkdtemp(path.join(os.tmpdir(), "tacket-node-host-override-"));
  const configRoot = await mkdtemp(path.join(os.tmpdir(), "tacket-node-host-config-"));
  const configFile = path.join(configRoot, "config.json");
  try {
    await writeConfig(configFile, configuredRoot);
    const response = await sendNativeMessage(validCapture("Override"), {
      outputRoot: overrideRoot,
      configFile
    });
    assert.equal(response.ok, true, response.error);
    assert.equal(response.bundlePath.startsWith(overrideRoot), true);
  } finally {
    await rm(configuredRoot, { recursive: true, force: true });
    await rm(overrideRoot, { recursive: true, force: true });
    await rm(configRoot, { recursive: true, force: true });
  }
});

test("native host rejects truncated native-message input", async () => {
  const body = Buffer.from(JSON.stringify(validCapture("Truncated")));
  const header = Buffer.alloc(4);
  header.writeUInt32LE(body.length + 10, 0);

  const response = await sendRawNativeMessage(Buffer.concat([header, body]));
  assert.equal(response.ok, false);
  assert.match(response.error, /shorter than declared length/);
});

test("native host rejects trailing native-message input", async () => {
  const body = Buffer.from(JSON.stringify(validCapture("Trailing")));
  const header = Buffer.alloc(4);
  header.writeUInt32LE(body.length, 0);

  const response = await sendRawNativeMessage(Buffer.concat([header, body, Buffer.from([0])]));
  assert.equal(response.ok, false);
  assert.match(response.error, /expected exactly one native message/);
});

function sendNativeMessage(message, options) {
  const body = Buffer.from(JSON.stringify(message));
  const header = Buffer.alloc(4);
  header.writeUInt32LE(body.length, 0);
  return sendRawNativeMessage(Buffer.concat([header, body]), options);
}

function sendRawNativeMessage(input, options) {
  return new Promise((resolve, reject) => {
    const env = { ...process.env };
    if (typeof options === "string") env.TACKET_CAPTURE_DIR = options;
    else {
      if (options?.outputRoot) env.TACKET_CAPTURE_DIR = options.outputRoot;
      if (options?.configFile) env.TACKET_CONFIG_FILE = options.configFile;
    }
    const child = spawn(process.execPath, [hostPath], {
      env,
      stdio: ["pipe", "pipe", "pipe"]
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code !== 0) {
        reject(new Error(`Native host exited with ${code}: ${Buffer.concat(stderr).toString("utf8")}`));
        return;
      }
      const output = Buffer.concat(stdout);
      const length = output.readUInt32LE(0);
      resolve(JSON.parse(output.subarray(4, 4 + length).toString("utf8")));
    });
    child.stdin.end(input);
  });
}

async function writeConfig(configFile, captureDirectory) {
  await mkdir(path.dirname(configFile), { recursive: true });
  await writeFile(configFile, JSON.stringify({ captureDirectory }, null, 2));
  assert.match(await readFile(configFile, "utf8"), /captureDirectory/);
}

function validCapture(title) {
  return {
    type: "saveCapture",
    capture: {
      title,
      source: { url: "https://chatgpt.com/c/test" },
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "configured output test" }]
        }
      ]
    }
  };
}
