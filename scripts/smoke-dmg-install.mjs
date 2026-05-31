import { execFile } from "node:child_process";
import { cp, mkdtemp, rm, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const root = path.resolve(new URL("..", import.meta.url).pathname);
const dmg = path.join(root, "dist", "Tacket.dmg");

const mountPoint = await mkdtemp(path.join(os.tmpdir(), "tacket-dmg-mount-"));
const installRoot = await mkdtemp(path.join(os.tmpdir(), "tacket-install-root-"));
const home = await mkdtemp(path.join(os.tmpdir(), "tacket-dmg-home-"));
const captureDir = await mkdtemp(path.join(os.tmpdir(), "tacket-dmg-captures-"));

try {
  await run("hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mountPoint, dmg]);

  const mountedApp = path.join(mountPoint, "Tacket.app");
  const installedApp = path.join(installRoot, "Applications", "Tacket.app");
  await cp(mountedApp, installedApp, { recursive: true });

  const hostPath = path.join(installedApp, "Contents", "MacOS", "TacketNativeHost");
  await assertExecutable(hostPath);

  const response = await sendCapture(hostPath);
  assert(response.ok === true, response.error ?? "packaged native host capture failed");
  assert(response.bundlePath.startsWith(captureDir), `bundle was not written to isolated capture dir: ${response.bundlePath}`);

  await run(process.execPath, ["scripts/validate-bundle.mjs", response.bundlePath]);
  await assertReadable(path.join(response.bundlePath, "manifest.json"));
  await assertReadable(path.join(response.bundlePath, "messages.jsonl"));
  await assertReadable(path.join(response.bundlePath, "transcript.md"));
  await assertReadable(path.join(response.bundlePath, "targets", "codex.md"));
  await assertReadable(path.join(response.bundlePath, "targets", "claude-code.md"));

  console.log("DMG install smoke passed.");
} finally {
  await run("hdiutil", ["detach", mountPoint]).catch(() => {});
  await rm(mountPoint, { recursive: true, force: true });
  await rm(installRoot, { recursive: true, force: true });
  await rm(home, { recursive: true, force: true });
  await rm(captureDir, { recursive: true, force: true });
}

function sendCapture(hostPath) {
  const body = Buffer.from(JSON.stringify({
    type: "saveCapture",
    capture: {
      title: "DMG install smoke thread",
      source: {
        platform: "chatgpt",
        url: "https://chatgpt.com/c/dmg-install-smoke"
      },
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "Please preserve this direct-download install test thread." }]
        },
        {
          role: "assistant",
          content: [
            { type: "text", text: "The packaged native host should write a local .tacket bundle." },
            { type: "code", language: "bash", text: "npm run smoke:dmg-install" }
          ]
        }
      ]
    }
  }));
  const header = Buffer.alloc(4);
  header.writeUInt32LE(body.length, 0);

  return new Promise((resolve, reject) => {
    const child = execFile(hostPath, {
      cwd: root,
      env: {
        ...process.env,
        HOME: home,
        TACKET_CAPTURE_DIR: captureDir
      },
      maxBuffer: 1024 * 1024 * 10,
      encoding: "buffer"
    }, (error, stdout, stderr) => {
      if (error) {
        reject(new Error(`packaged native host failed: ${stderr.toString("utf8") || error.message}`));
        return;
      }
      try {
        const length = stdout.readUInt32LE(0);
        resolve(JSON.parse(stdout.subarray(4, 4 + length).toString("utf8")));
      } catch (parseError) {
        reject(parseError);
      }
    });
    child.stdin.end(Buffer.concat([header, body]));
  });
}

async function assertReadable(file) {
  const info = await stat(file);
  assert(info.isFile(), `expected file: ${file}`);
  assert(info.size > 0, `expected non-empty file: ${file}`);
}

async function assertExecutable(file) {
  const info = await stat(file);
  assert(info.isFile(), `expected executable: ${file}`);
  await run("test", ["-x", file]);
}

async function run(command, args) {
  const { stdout } = await execFileAsync(command, args, {
    cwd: root,
    maxBuffer: 1024 * 1024 * 10
  });
  return stdout.trim();
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
