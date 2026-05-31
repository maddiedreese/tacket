import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { test } from "node:test";

const cliPath = path.resolve("apps/cli/bin/tacket.js");
const validExtensionId = "abcdefghijklmnopabcdefghijklmnop";

test("install-native-host rejects malformed Chrome extension IDs", async () => {
  const home = await mkdtemp(path.join(os.tmpdir(), "tacket-cli-home-"));
  try {
    const result = await runCli(["install-native-host", "--extension-id", "not-a-real-id"], { HOME: home });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Invalid Chrome extension ID/);
  } finally {
    await rm(home, { recursive: true, force: true });
  }
});

test("install-native-host writes an allowed origin for a valid Chrome extension ID", async () => {
  const home = await mkdtemp(path.join(os.tmpdir(), "tacket-cli-home-"));
  try {
    const result = await runCli(["install-native-host", "--extension-id", validExtensionId], { HOME: home });
    assert.equal(result.status, 0, result.stderr);

    const manifestPath = path.join(
      home,
      "Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.tacket.host.json"
    );
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    assert.equal(manifest.name, "dev.tacket.host");
    assert.deepEqual(manifest.allowed_origins, [`chrome-extension://${validExtensionId}/`]);
  } finally {
    await rm(home, { recursive: true, force: true });
  }
});

function runCli(args, env = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [cliPath, ...args], {
      env: { ...process.env, ...env },
      stdio: ["ignore", "pipe", "pipe"]
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", reject);
    child.on("exit", (status) => {
      resolve({
        status,
        stdout: Buffer.concat(stdout).toString("utf8"),
        stderr: Buffer.concat(stderr).toString("utf8")
      });
    });
  });
}
