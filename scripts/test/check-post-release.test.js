import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import test from "node:test";

const root = path.resolve(new URL("../..", import.meta.url).pathname);

test("post-release local rehearsal verifies downloads and dry-run Gatekeeper assessment", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-postflight-pass-"));
  try {
    const artifactDir = await localArtifacts(temp);
    const { binDir, logPath } = await fakeNpm(temp);

    const result = await runPostflight(["--dir", artifactDir, "--dry-run-gatekeeper"], {
      PATH: `${binDir}:${process.env.PATH}`
    });

    assert.equal(result.code, 0, result.stderr);
    assert.match(result.stdout, /PASS Website verifies/u);
    assert.match(result.stdout, /PASS Release downloads verify/u);
    assert.match(result.stdout, /SKIP GitHub Release is published with required assets - local --dir mode/u);
    assert.match(result.stdout, /PASS Gatekeeper assessment/u);

    const log = await readFile(logPath, "utf8");
    assert.match(log, /run website:verify/u);
    assert.match(log, new RegExp(`run release:verify-download -- --dir ${escapeRegex(path.resolve(artifactDir))}`, "u"));
    assert.match(log, /run release:assess -- --app .+Tacket\.app --dmg .+Tacket\.dmg --dry-run/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("post-release local rehearsal rejects missing DMG before Gatekeeper assessment", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-postflight-fail-"));
  try {
    const artifactDir = await localArtifacts(temp);
    await rm(path.join(artifactDir, "Tacket.dmg"));
    const { binDir } = await fakeNpm(temp);

    const result = await runPostflight(["--dir", artifactDir, "--dry-run-gatekeeper"], {
      PATH: `${binDir}:${process.env.PATH}`
    });

    assert.equal(result.code, 1);
    assert.match(result.stdout, /FAIL Gatekeeper assessment - ENOENT/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("post-release check verifies published GitHub Release assets", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-postflight-release-pass-"));
  try {
    const { binDir, logPath } = await fakeReleaseTools(temp);

    const result = await runPostflight(["--tag", "v0.1.0", "--skip-gatekeeper"], {
      PATH: `${binDir}:${process.env.PATH}`
    });

    assert.equal(result.code, 0, result.stderr);
    assert.match(result.stdout, /PASS Website verifies/u);
    assert.match(result.stdout, /PASS Release downloads verify/u);
    assert.match(result.stdout, /PASS GitHub Release is published with required assets/u);

    const log = await readFile(logPath, "utf8");
    assert.match(log, /npm run website:verify/u);
    assert.match(log, /npm run release:verify-download -- --tag v0\.1\.0/u);
    assert.match(log, /gh release view v0\.1\.0 --repo maddiedreese\/tacket --json tagName,isDraft,isPrerelease,url,assets/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("post-release check rejects draft releases", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-postflight-release-fail-"));
  try {
    const { binDir } = await fakeReleaseTools(temp, { draft: true });

    const result = await runPostflight(["--tag", "v0.1.0", "--skip-gatekeeper"], {
      PATH: `${binDir}:${process.env.PATH}`
    });

    assert.equal(result.code, 1);
    assert.match(result.stdout, /FAIL GitHub Release is published with required assets - release must not be a draft/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("post-release check rejects missing required release assets", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-postflight-release-asset-fail-"));
  try {
    const { binDir } = await fakeReleaseTools(temp, { omitAsset: "SHA256SUMS" });

    const result = await runPostflight(["--tag", "v0.1.0", "--skip-gatekeeper"], {
      PATH: `${binDir}:${process.env.PATH}`
    });

    assert.equal(result.code, 1);
    assert.match(result.stdout, /FAIL GitHub Release is published with required assets - GitHub Release missing asset SHA256SUMS/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

async function localArtifacts(temp) {
  const artifactDir = path.join(temp, "dist");
  await mkdir(path.join(artifactDir, "Tacket.app"), { recursive: true });
  await writeFile(path.join(artifactDir, "Tacket.dmg"), "synthetic dmg placeholder\n");
  return artifactDir;
}

async function fakeReleaseTools(temp, options = {}) {
  const binDir = path.join(temp, "bin");
  const logPath = path.join(temp, "commands.log");
  await mkdir(binDir, { recursive: true });
  await fakeExecutable(binDir, "npm", `#!/usr/bin/env bash
set -euo pipefail
printf 'npm %s\\n' "$*" >> "${logPath}"
exit 0
`);
  const assetNames = ["Tacket.dmg", "tacket-chrome-extension.zip", "SHA256SUMS"]
    .filter((name) => name !== options.omitAsset);
  await fakeExecutable(binDir, "gh", `#!/usr/bin/env bash
set -euo pipefail
printf 'gh %s\\n' "$*" >> "${logPath}"
case "$*" in
  "release view v0.1.0 --repo maddiedreese/tacket --json tagName,isDraft,isPrerelease,url,assets")
    cat <<'JSON'
{"tagName":"v0.1.0","isDraft":${options.draft ? "true" : "false"},"isPrerelease":${options.prerelease ? "true" : "false"},"url":"https://github.com/maddiedreese/tacket/releases/tag/v0.1.0","assets":[${assetNames.map((name) => `{"name":"${name}"}`).join(",")}]}
JSON
    ;;
  *)
    echo "unexpected gh invocation: $*" >&2
    exit 1
    ;;
esac
`);
  return { binDir, logPath };
}

async function fakeNpm(temp) {
  const binDir = path.join(temp, "bin");
  const logPath = path.join(temp, "npm.log");
  await mkdir(binDir, { recursive: true });
  const npmPath = path.join(binDir, "npm");
  await writeFile(
    npmPath,
    `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "${logPath}"
exit 0
`
  );
  await chmod(npmPath, 0o755);
  return { binDir, logPath };
}

async function fakeExecutable(binDir, name, source) {
  const file = path.join(binDir, name);
  await writeFile(file, source);
  await chmod(file, 0o755);
}

function runPostflight(args, env = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["scripts/check-post-release.mjs", ...args], {
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
