import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

const root = path.resolve(new URL("../..", import.meta.url).pathname);
const changelogPath = path.join(root, "CHANGELOG.md");

test("checks changelog dating without editing", async () => {
  const original = await readFile(changelogPath, "utf8");
  const result = await runDateChangelog(["--date", "2026-05-31", "--check"]);
  const after = await readFile(changelogPath, "utf8");

  assert.equal(result.code, 0, result.stderr);
  assert.equal(after, original);
  assert.match(result.stdout, /can be dated/u);
});

test("dates changelog release heading", async () => {
  const tmp = await mkdtemp(path.join(os.tmpdir(), "tacket-date-changelog-"));
  const scriptsDir = path.join(tmp, "scripts");
  const script = path.join(scriptsDir, "date-changelog-release.mjs");
  const changelog = path.join(tmp, "CHANGELOG.md");
  const releaseJson = path.join(tmp, "release.json");
  const scriptText = await readFile(path.join(root, "scripts/date-changelog-release.mjs"), "utf8");

  await mkdir(scriptsDir, { recursive: true });
  await writeFile(script, scriptText, "utf8");
  await writeFile(releaseJson, JSON.stringify({ version: "0.1.0" }), "utf8");
  await writeFile(changelog, "# Changelog\n\n## 0.1.0 - Unreleased\n\nInitial.\n", "utf8");

  const result = await run("node", [script, "--date", "2026-05-31"], tmp);
  assert.equal(result.code, 0, result.stderr);
  assert.match(await readFile(changelog, "utf8"), /^## 0\.1\.0 - 2026-05-31$/mu);
});

function runDateChangelog(args) {
  return run("node", ["scripts/date-changelog-release.mjs", ...args], root);
}

function run(command, args, cwd) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
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
