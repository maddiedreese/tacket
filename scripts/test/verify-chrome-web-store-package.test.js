import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import test from "node:test";

const root = path.resolve(new URL("../..", import.meta.url).pathname);

test("Chrome Web Store verifier checks package assets, copy, manifest, and matching release zip", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-store-verify-pass-"));
  try {
    const projectRoot = await fixtureProject(temp);
    const { binDir } = await fakeUnzip(temp);
    const result = await runStoreVerify({
      PATH: `${binDir}:${process.env.PATH}`,
      TACKET_RELEASE_ROOT: projectRoot
    });

    assert.equal(result.code, 0, result.stderr);
    assert.match(result.stdout, new RegExp(`Chrome Web Store package checks passed for ${escapeRegex(path.join(projectRoot, "dist/chrome-web-store"))}`, "u"));
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("Chrome Web Store verifier rejects secret-like listing copy before zip inspection", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-store-verify-secret-"));
  try {
    const projectRoot = await fixtureProject(temp);
    await writeFile(
      path.join(projectRoot, "dist/chrome-web-store/listing.md"),
      listingCopy() + "\nDo not publish: sk-testtokenabcdefghijklmnopqrstuvwxyz\n"
    );
    const { binDir } = await fakeUnzip(temp);
    const result = await runStoreVerify({
      PATH: `${binDir}:${process.env.PATH}`,
      TACKET_RELEASE_ROOT: projectRoot
    });

    assert.equal(result.code, 1);
    assert.match(result.stderr, /listing\.md appears to contain private secret-like text: OpenAI API key/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

async function fixtureProject(temp) {
  const projectRoot = path.join(temp, "project");
  const storeDir = path.join(projectRoot, "dist", "chrome-web-store");
  await mkdir(path.join(storeDir, "screenshots"), { recursive: true });
  await writeFile(path.join(projectRoot, "release.json"), JSON.stringify({ version: "0.1.0" }) + "\n");
  await writeFile(path.join(projectRoot, "dist", "tacket-chrome-extension.zip"), "extension zip bytes\n");
  await writeFile(path.join(storeDir, "tacket-chrome-extension.zip"), "extension zip bytes\n");
  await writePng(path.join(storeDir, "icon-128.png"), 128, 128);
  await writePng(path.join(storeDir, "small-promo-440x280.png"), 440, 280);
  await writePng(path.join(storeDir, "screenshots/01-capture-popup-1280x800.png"), 1280, 800);
  await writePng(path.join(storeDir, "screenshots/02-local-bundle-1280x800.png"), 1280, 800);
  await writePng(path.join(storeDir, "screenshots/03-transfer-targets-1280x800.png"), 1280, 800);
  await writeFile(path.join(storeDir, "listing.md"), listingCopy());
  await writeFile(path.join(storeDir, "privacy.md"), privacyCopy());
  await writeFile(path.join(storeDir, "README.md"), readmeCopy());
  return projectRoot;
}

async function fakeUnzip(temp) {
  const binDir = path.join(temp, "bin");
  await mkdir(binDir, { recursive: true });
  await fakeExecutable(binDir, "unzip", `#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "-l" ]]; then
  cat <<'LISTING'
Archive: tacket-chrome-extension.zip
        0  01-01-26 00:00   manifest.json
        0  01-01-26 00:00   src/popup.html
        0  01-01-26 00:00   src/popup.css
        0  01-01-26 00:00   src/popup.js
        0  01-01-26 00:00   src/background.js
        0  01-01-26 00:00   src/adapters/capture.js
        0  01-01-26 00:00   icons/tacket-16.png
        0  01-01-26 00:00   icons/tacket-32.png
        0  01-01-26 00:00   icons/tacket-48.png
        0  01-01-26 00:00   icons/tacket-128.png
LISTING
  exit 0
fi
if [[ "$1" == "-q" && "$3" == "-d" ]]; then
  mkdir -p "$4"
  cat > "$4/manifest.json" <<'JSON'
{"name":"Tacket","version":"0.1.0","manifest_version":3,"permissions":["activeTab","scripting","nativeMessaging"],"host_permissions":["https://chatgpt.com/*","https://chat.openai.com/*","https://claude.ai/*","https://gemini.google.com/*"]}
JSON
  exit 0
fi
echo "unexpected unzip invocation: $*" >&2
exit 1
`);
  return { binDir };
}

async function writePng(file, width, height) {
  const bytes = Buffer.alloc(24);
  Buffer.from("89504e470d0a1a0a", "hex").copy(bytes, 0);
  bytes.writeUInt32BE(width, 16);
  bytes.writeUInt32BE(height, 20);
  await writeFile(file, bytes);
}

async function fakeExecutable(binDir, name, source) {
  const file = path.join(binDir, name);
  await writeFile(file, source);
  await chmod(file, 0o755);
}

function listingCopy() {
  return `Tacket
Capture AI chat threads locally
Single Purpose
Permission Justification
\`activeTab\`
\`scripting\`
\`nativeMessaging\`
Host permissions
https://chatgpt.com/*
https://chat.openai.com/*
https://claude.ai/*
https://gemini.google.com/*
does not collect, sell, transmit, or remotely process user data
npm run store:verify-id
`;
}

function privacyCopy() {
  return `local-first
No backend
No analytics
No model calls
Captured thread content is stored locally
Chrome Native Messaging
`;
}

function readmeCopy() {
  return `Upload \`tacket-chrome-extension.zip\`
Use these generated assets
Review every image before upload
should not contain private transcripts
`;
}

function runStoreVerify(env = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["scripts/verify-chrome-web-store-package.mjs"], {
      cwd: root,
      env: { ...process.env, ...env },
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
