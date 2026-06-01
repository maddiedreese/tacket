import assert from "node:assert/strict";
import { access, chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
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
    assert.equal(manifest.path, path.join(path.dirname(manifestPath), "dev.tacket.host.sh"));
    assert.deepEqual(manifest.allowed_origins, [`chrome-extension://${validExtensionId}/`]);
    const launcher = await readFile(manifest.path, "utf8");
    assert.match(launcher, new RegExp(`^#!/bin/sh\\nexec '${escapeRegex(process.execPath)}' `, "u"));
    assert.match(launcher, /apps\/native-host\/bin\/tacket-native-host\.js'/u);
  } finally {
    await rm(home, { recursive: true, force: true });
  }
});

test("uninstall-native-host removes the manifest and launcher", async () => {
  const home = await mkdtemp(path.join(os.tmpdir(), "tacket-cli-home-"));
  try {
    const install = await runCli(["install-native-host", "--extension-id", validExtensionId], { HOME: home });
    assert.equal(install.status, 0, install.stderr);

    const manifestPath = path.join(
      home,
      "Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.tacket.host.json"
    );
    const launcherPath = path.join(path.dirname(manifestPath), "dev.tacket.host.sh");
    await access(manifestPath, constants.R_OK);
    await access(launcherPath, constants.R_OK);

    const uninstall = await runCli(["uninstall-native-host"], { HOME: home });
    assert.equal(uninstall.status, 0, uninstall.stderr);
    await assertMissing(manifestPath);
    await assertMissing(launcherPath);
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

test("transfer no-paste launch wording does not claim a paste request", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-cli-transfer-no-paste-"));
  try {
    const bin = path.join(root, "bin");
    await mkdir(bin);
    await writeFile(path.join(bin, "osascript"), "#!/bin/sh\nexit 0\n", "utf8");
    await chmod(path.join(bin, "osascript"), 0o755);

    const sample = await runCli(["sample", "--out", root]);
    assert.equal(sample.status, 0, sample.stderr);
    const bundlePath = sample.stdout.trim();
    const result = await runCli(["transfer", bundlePath, "--to", "codex", "--no-paste"], {
      PATH: `${bin}:${process.env.PATH ?? ""}`
    });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /without requesting paste/u);
    assert.doesNotMatch(result.stdout, /requested paste into Terminal/u);
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

    const search = await runCli(["library-search", "full conversation", "--db", db]);
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

async function assertMissing(file) {
  try {
    await access(file, constants.R_OK);
  } catch {
    return;
  }
  throw new Error(`Expected missing file: ${file}`);
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
}
