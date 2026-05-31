import assert from "node:assert/strict";
import { cp, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import test from "node:test";
import { writeBundle } from "../../packages/thread-format/src/index.js";

const root = path.resolve(new URL("../..", import.meta.url).pathname);

test("validate-bundle rejects drifted transfer targets", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-validate-targets-"));
  try {
    const { bundlePath } = await sampleBundle(temp);
    await writeFile(path.join(bundlePath, "targets", "codex.md"), "not the transcript\n");

    const result = await run("node", ["scripts/validate-bundle.mjs", bundlePath]);
    assert.equal(result.code, 1);
    assert.match(result.stderr, /targets\/codex\.md must match transcript\.md exactly/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("validate-bundle rejects stale attachment counts", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-validate-counts-"));
  try {
    const { bundlePath } = await sampleBundle(temp);
    const manifestPath = path.join(bundlePath, "manifest.json");
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    manifest.attachments.captured = 0;
    await writeFile(manifestPath, JSON.stringify(manifest, null, 2) + "\n");

    const result = await run("node", ["scripts/validate-bundle.mjs", bundlePath]);
    assert.equal(result.code, 1);
    assert.match(result.stderr, /attachments\.captured 0 does not match messages\.jsonl 1/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("validate-bundle rejects missing captured attachment files", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-validate-attachments-"));
  try {
    const { bundlePath } = await sampleBundle(temp);
    await rm(path.join(bundlePath, "attachments"), { recursive: true, force: true });

    const result = await run("node", ["scripts/validate-bundle.mjs", bundlePath]);
    assert.equal(result.code, 1);
    assert.match(result.stderr, /Expected file: .*attachments/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

async function sampleBundle(dir) {
  const fixture = path.join(dir, "tiny.png");
  await cp(path.join(root, "apps/chrome-extension/icons/tacket-16.png"), fixture);
  return writeBundle(
    {
      title: "Validate bundle fixture",
      source: { url: "https://chatgpt.com/c/validate" },
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: "Please validate this bundle." },
            { type: "attachment", status: "captured", name: "tiny.png", mimeType: "image/png", path: fixture }
          ]
        }
      ]
    },
    dir
  );
}

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
