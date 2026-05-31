import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import test from "node:test";

const root = path.resolve(new URL("../..", import.meta.url).pathname);

test("release download verifier checks local artifacts, checksums, extension listing, and DMG", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-release-download-pass-"));
  try {
    const artifactDir = await releaseArtifacts(temp);
    const { binDir, commandLogPath } = await fakeDownloadTools(temp);
    const result = await runVerifyDownload(["--dir", artifactDir], {
      PATH: `${binDir}:${process.env.PATH}`
    });

    assert.equal(result.code, 0, result.stderr);
    assert.match(result.stdout, new RegExp(`Release download verification passed for ${escapeRegex(path.resolve(artifactDir))}`, "u"));
    const commandLog = await readFile(commandLogPath, "utf8");
    assert.match(commandLog, /unzip -l .+tacket-chrome-extension\.zip/u);
    assert.match(commandLog, /hdiutil verify .+Tacket\.dmg/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("release download verifier rejects stale checksums before shelling out", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-release-download-stale-"));
  try {
    const artifactDir = await releaseArtifacts(temp);
    await writeFile(path.join(artifactDir, "SHA256SUMS"), `${"0".repeat(64)}  Tacket.dmg\n${"0".repeat(64)}  tacket-chrome-extension.zip\n`);
    const { binDir, commandLogPath } = await fakeDownloadTools(temp);
    const result = await runVerifyDownload(["--dir", artifactDir], {
      PATH: `${binDir}:${process.env.PATH}`
    });

    assert.equal(result.code, 1);
    assert.match(result.stderr, /SHA256SUMS hash for Tacket\.dmg is missing or stale/u);
    const commandLog = await readFile(commandLogPath, "utf8");
    assert.equal(commandLog, "");
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("release download verifier rejects unknown arguments", async () => {
  const result = await runVerifyDownload(["--keeep"]);

  assert.equal(result.code, 1);
  assert.match(result.stderr, /Unknown argument: --keeep/u);
});

async function releaseArtifacts(temp) {
  const artifactDir = path.join(temp, "dist");
  await mkdir(artifactDir, { recursive: true });
  const dmgBytes = "synthetic dmg\n";
  const zipBytes = "synthetic extension zip\n";
  await writeFile(path.join(artifactDir, "Tacket.dmg"), dmgBytes);
  await writeFile(path.join(artifactDir, "tacket-chrome-extension.zip"), zipBytes);
  await writeFile(
    path.join(artifactDir, "SHA256SUMS"),
    `${sha256(dmgBytes)}  Tacket.dmg\n${sha256(zipBytes)}  tacket-chrome-extension.zip\n`
  );
  return artifactDir;
}

async function fakeDownloadTools(temp) {
  const binDir = path.join(temp, "bin");
  const commandLogPath = path.join(temp, "commands.log");
  await mkdir(binDir, { recursive: true });
  await writeFile(commandLogPath, "");
  await fakeExecutable(binDir, "unzip", `#!/usr/bin/env bash
set -euo pipefail
printf 'unzip %s\\n' "$*" >> "${commandLogPath}"
if [[ "$1" == "-l" ]]; then
  cat <<'LISTING'
Archive: tacket-chrome-extension.zip
  Length      Date    Time    Name
        0  01-01-26 00:00   manifest.json
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
echo "unexpected unzip invocation: $*" >&2
exit 1
`);
  await fakeExecutable(binDir, "hdiutil", `#!/usr/bin/env bash
set -euo pipefail
printf 'hdiutil %s\\n' "$*" >> "${commandLogPath}"
if [[ "$1" == "verify" ]]; then
  exit 0
fi
echo "unexpected hdiutil invocation: $*" >&2
exit 1
`);
  return { binDir, commandLogPath };
}

async function fakeExecutable(binDir, name, source) {
  const file = path.join(binDir, name);
  await writeFile(file, source);
  await chmod(file, 0o755);
}

function runVerifyDownload(args, env = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["scripts/verify-release-download.mjs", ...args], {
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

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
}
