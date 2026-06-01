import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
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

test("transfer rejects invalid chunk sizes before copying", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-cli-transfer-"));
  try {
    const sample = await runCli(["sample", "--out", root]);
    assert.equal(sample.status, 0, sample.stderr);
    const bundlePath = sample.stdout.trim();
    const result = await runCli(["transfer", bundlePath, "--to", "codex", "--dry-run", "--chunk-size", "nope"]);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /Invalid chunk size/u);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("transfer rejects bundles with drifted target transcripts before copying", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-cli-transfer-drift-"));
  try {
    const sample = await runCli(["sample", "--out", root]);
    assert.equal(sample.status, 0, sample.stderr);
    const bundlePath = sample.stdout.trim();
    await writeFile(path.join(bundlePath, "targets", "codex.md"), "drifted target\n");
    const result = await runCli(["transfer", bundlePath, "--to", "codex", "--dry-run"]);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /targets\/codex\.md must match transcript\.md exactly/u);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("library commands index, list, search, and remove missing bundles", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-cli-library-"));
  try {
    const db = path.join(root, "library.sqlite");
    const sample = await runCli(["sample", "--out", root]);
    assert.equal(sample.status, 0, sample.stderr);
    const bundlePath = sample.stdout.trim();

    const index = await runCli(["library-index", "--folder", root, "--db", db]);
    assert.equal(index.status, 0, index.stderr);
    assert.equal(JSON.parse(index.stdout).indexed, 1);

    const search = await runCli(["library-search", "raw transcript", "--db", db]);
    assert.equal(search.status, 0, search.stderr);
    const results = JSON.parse(search.stdout);
    assert.equal(results.length, 1);
    assert.match(results[0].title, /Tacket sample thread/u);

    const list = await runCli(["library-list", "--db", db]);
    assert.equal(list.status, 0, list.stderr);
    assert.equal(JSON.parse(list.stdout).length, 1);

    await rm(bundlePath, { recursive: true, force: true });
    const removed = await runCli(["library-remove-missing", "--db", db]);
    assert.equal(removed.status, 0, removed.stderr);
    assert.equal(JSON.parse(removed.stdout).removed, 1);
  } finally {
    await rm(root, { recursive: true, force: true });
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
