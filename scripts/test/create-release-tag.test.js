import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import test from "node:test";
import path from "node:path";

const root = path.resolve(new URL("../..", import.meta.url).pathname);

test("release tag dry run prints guarded tag commands", async () => {
  const result = await run("node", ["scripts/create-release-tag.mjs", "--dry-run", "--push"], root);

  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /Would run: npm run release:pretag/u);
  assert.match(result.stdout, /Would run: git tag -a v0\.1\.0/u);
  assert.match(result.stdout, /Would run: git push origin v0\.1\.0/u);
});

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
