import { execFile, spawn } from "node:child_process";
import { mkdtemp, rm, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const root = path.resolve(new URL("..", import.meta.url).pathname);
const cli = path.join(root, "apps", "cli", "bin", "tacket.js");
const nativeHost = path.join(root, "apps", "native-host", "bin", "tacket-native-host.js");
const extensionId = "abcdefghijklmnopabcdefghijklmnop";

const home = await mkdtemp(path.join(os.tmpdir(), "tacket-first-run-home-"));
const captureDir = await mkdtemp(path.join(os.tmpdir(), "tacket-first-run-captures-"));

try {
  await assertNativeHostStatus(false);
  await run(process.execPath, [cli, "install-native-host", "--extension-id", extensionId], { HOME: home });
  await assertNativeHostStatus(true);

  const response = await sendCapture();
  assert(response.ok === true, response.error ?? "native host capture failed");
  assert(response.bundlePath.startsWith(captureDir), `bundle was not written to isolated capture dir: ${response.bundlePath}`);

  await run(process.execPath, ["scripts/validate-bundle.mjs", response.bundlePath]);
  await assertReadable(path.join(response.bundlePath, "transcript.md"));
  await assertReadable(path.join(response.bundlePath, "messages.jsonl"));
  await assertReadable(path.join(response.bundlePath, "manifest.json"));

  await run(process.execPath, [cli, "transfer", response.bundlePath, "--to", "codex", "--dry-run", "--chunk-size", "1000"], { HOME: home });
  await run(process.execPath, [cli, "transfer", response.bundlePath, "--to", "claude-code", "--dry-run", "--chunk-size", "1000"], { HOME: home });

  await run(process.execPath, [cli, "uninstall-native-host"], { HOME: home });
  await assertNativeHostStatus(false);
  console.log("First-run smoke passed.");
} finally {
  await rm(home, { recursive: true, force: true });
  await rm(captureDir, { recursive: true, force: true });
}

async function assertNativeHostStatus(expectedInstalled) {
  const output = await run(process.execPath, [cli, "status-native-host"], { HOME: home });
  const status = JSON.parse(output);
  assert(status.installed === expectedInstalled, `expected installed=${expectedInstalled}, found ${status.installed}`);
  if (expectedInstalled) {
    assert(status.allowedOrigins?.includes(`chrome-extension://${extensionId}/`), "native host status missing extension origin");
  }
}

function sendCapture() {
  const body = Buffer.from(JSON.stringify({
    type: "saveCapture",
    capture: {
      title: "First-run smoke thread",
      source: {
        platform: "chatgpt",
        url: "https://chatgpt.com/c/first-run-smoke"
      },
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "Please transfer this full conversation into Codex." }]
        },
        {
          role: "assistant",
          content: [
            { type: "text", text: "I will preserve the full conversation and avoid summarizing it." },
            { type: "code", language: "bash", text: "npm run smoke:first-run" }
          ]
        }
      ]
    }
  }));
  const header = Buffer.alloc(4);
  header.writeUInt32LE(body.length, 0);
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [nativeHost], {
      cwd: root,
      env: {
        ...process.env,
        HOME: home,
        TACKET_CAPTURE_DIR: captureDir
      },
      stdio: ["pipe", "pipe", "pipe"]
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code !== 0) {
        reject(new Error(`native host exited with ${code}: ${Buffer.concat(stderr).toString("utf8")}`));
        return;
      }
      const output = Buffer.concat(stdout);
      const length = output.readUInt32LE(0);
      resolve(JSON.parse(output.subarray(4, 4 + length).toString("utf8")));
    });
    child.stdin.end(Buffer.concat([header, body]));
  });
}

async function assertReadable(file) {
  const info = await stat(file);
  assert(info.isFile(), `expected file: ${file}`);
  assert(info.size > 0, `expected non-empty file: ${file}`);
}

async function run(command, args, env = {}) {
  const { stdout } = await execFileAsync(command, args, {
    cwd: root,
    env: { ...process.env, ...env },
    maxBuffer: 1024 * 1024 * 10
  });
  return stdout.trim();
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
