import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import test from "node:test";

const validExtensionId = "abcdefghijklmnopabcdefghijklmnop";
const publishedExtensionId = "cbpgfpcajomllnfoigagibafblmnbbdh";

test("verifies native messaging install contract for a Web Store extension ID", async () => {
  const result = await runVerify(["--extension-id", validExtensionId]);
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, new RegExp(`Chrome Web Store extension ID verification passed for ${validExtensionId}`, "u"));
});

test("rejects malformed Web Store extension IDs", async () => {
  const result = await runVerify(["--extension-id", "not-a-real-id"]);
  assert.equal(result.code, 1);
  assert.match(result.stderr, /Invalid Chrome extension ID/u);
});

test("uses the published release extension ID when no argument is supplied", async () => {
  const result = await runVerify([]);
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, new RegExp(`Chrome Web Store extension ID verification passed for ${publishedExtensionId}`, "u"));
});

function runVerify(args) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["scripts/verify-web-store-extension-id.mjs", ...args], {
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
