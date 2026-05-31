import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import test from "node:test";

const root = path.resolve(new URL("../..", import.meta.url).pathname);

test("Gatekeeper assessment dry run prints every release assessment command", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-gatekeeper-pass-"));
  try {
    const { appPath, dmgPath } = await fakeReleaseArtifacts(temp);
    const result = await runAssess(["--app", appPath, "--dmg", dmgPath, "--dry-run"]);

    assert.equal(result.code, 0, result.stderr);
    assert.match(result.stdout, new RegExp(`codesign --verify --deep --strict --verbose=2 ${escapeRegex(appPath)}`, "u"));
    assert.match(result.stdout, new RegExp(`codesign --display --verbose=2 ${escapeRegex(appPath)}`, "u"));
    assert.match(result.stdout, new RegExp(`spctl --assess --type execute --verbose ${escapeRegex(appPath)}`, "u"));
    assert.match(result.stdout, new RegExp(`hdiutil verify ${escapeRegex(dmgPath)}`, "u"));
    assert.match(result.stdout, new RegExp(`spctl --assess --type open --verbose ${escapeRegex(dmgPath)}`, "u"));
    assert.match(result.stdout, new RegExp(`xcrun stapler validate ${escapeRegex(dmgPath)}`, "u"));
    assert.match(result.stdout, /Gatekeeper assessment dry run passed\./u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("Gatekeeper assessment rejects missing release artifacts before dry run", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-gatekeeper-missing-"));
  try {
    const appPath = path.join(temp, "Missing.app");
    const dmgPath = path.join(temp, "Missing.dmg");
    const result = await runAssess(["--app", appPath, "--dmg", dmgPath, "--dry-run"]);

    assert.equal(result.code, 1);
    assert.match(result.stderr, /ENOENT/u);
    assert.doesNotMatch(result.stdout, /Gatekeeper assessment dry run passed/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("Gatekeeper assessment requires option values", async () => {
  const result = await runAssess(["--app"]);
  assert.equal(result.code, 1);
  assert.match(result.stderr, /--app requires a value/u);
});

async function fakeReleaseArtifacts(temp) {
  const appPath = path.join(temp, "Tacket.app");
  const dmgPath = path.join(temp, "Tacket.dmg");
  await mkdir(appPath, { recursive: true });
  await writeFile(dmgPath, "synthetic dmg placeholder\n");
  return { appPath, dmgPath };
}

function runAssess(args) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["scripts/assess-release-gatekeeper.mjs", ...args], {
      cwd: root,
      stdio: ["ignore", "pipe", "pipe"]
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", reject);
    child.on("exit", (code) => {
      resolve({
        code,
        stdout: Buffer.concat(stdout).toString("utf8"),
        stderr: Buffer.concat(stderr).toString("utf8")
      });
    });
  });
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
}
