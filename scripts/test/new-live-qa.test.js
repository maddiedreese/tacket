import assert from "node:assert/strict";
import { readFile, rm } from "node:fs/promises";
import path from "node:path";
import { spawn } from "node:child_process";
import test from "node:test";

const root = path.resolve(new URL("../..", import.meta.url).pathname);

test("creates a live QA report for the current commit", async () => {
  const currentHead = (await run("git", ["rev-parse", "--short=12", "HEAD"])).stdout.trim();
  const result = await run(process.execPath, ["scripts/new-live-qa.mjs"]);
  assert.equal(result.code, 0, result.stderr);

  const reportPath = result.stdout.trim();
  try {
    assert.equal(path.dirname(reportPath), path.join(root, "qa/live-capture"));
    assert.match(path.basename(reportPath), /^\d{4}-\d{2}-\d{2}T.+\.md$/u);

    const report = await readFile(reportPath, "utf8");
    assert.match(report, /^# Tacket Live Capture QA$/mu);
    assert.match(report, /^Release decision: Unset$/mu);
    assert.match(report, new RegExp(`^Tacket commit: ${currentHead}$`, "mu"));
    assert.match(report, /^- \[ \] Text assistant turn$/mu);
    assert.match(report, /^- \[ \] Text model turn$/mu);
    assert.match(report, /^- \[ \] Codex transfer launches Terminal and requests paste\.$/mu);
    assert.match(report, new RegExp(`npm run qa:live:verify -- ${escapeRegex(reportPath)}`, "u"));
  } finally {
    await rm(reportPath, { force: true });
  }
});

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
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
