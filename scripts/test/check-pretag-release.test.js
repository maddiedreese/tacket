import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import test from "node:test";

const repoRoot = path.resolve(new URL("../..", import.meta.url).pathname);
const head = "abcdef1234567890abcdef1234567890abcdef12";
const requiredSecrets = [
  "DEVELOPER_ID_APPLICATION",
  "DEVELOPER_ID_CERTIFICATE_BASE64",
  "DEVELOPER_ID_CERTIFICATE_PASSWORD",
  "KEYCHAIN_PASSWORD",
  "APPLE_ID",
  "APPLE_TEAM_ID",
  "APPLE_APP_SPECIFIC_PASSWORD"
];

test("pretag release gate passes when every local and remote requirement is satisfied", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-pretag-pass-"));
  try {
    const projectRoot = await fixtureProject(temp);
    const { binDir } = await fakePretagTools(temp);
    const result = await runPretag({
      PATH: `${binDir}:${process.env.PATH}`,
      TACKET_RELEASE_ROOT: projectRoot
    });

    assert.equal(result.code, 0, result.stderr);
    for (const label of [
      "Working tree is clean",
      "Release artifacts verify",
      "Chrome Web Store submission folder is ready",
      "Versions are aligned",
      "CHANGELOG.md has a final dated 0.1.0 entry",
      "v0.1.0 does not exist locally or remotely",
      "Release issue checklists are synced",
      "v0.1.0 milestone has no open issues",
      "Signing and notarization secrets are configured",
      "Latest CI run passed on main",
      "Latest Release workflow run passed",
      "Latest Release workflow artifact is available",
      "Latest Release workflow artifact contents verify",
      "Latest Release workflow signed and notarized when secrets are configured"
    ]) {
      assert.match(result.stdout, new RegExp(`PASS ${escapeRegex(label)}`, "u"));
    }
    assert.doesNotMatch(result.stdout, /^FAIL /mu);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

async function fixtureProject(temp) {
  const projectRoot = path.join(temp, "project");
  await mkdir(path.join(projectRoot, "apps/chrome-extension"), { recursive: true });
  await writeFile(path.join(projectRoot, "release.json"), JSON.stringify({ version: "0.1.0" }) + "\n");
  await writeFile(path.join(projectRoot, "package.json"), JSON.stringify({ version: "0.1.0" }) + "\n");
  await writeFile(path.join(projectRoot, "apps/chrome-extension/manifest.json"), JSON.stringify({ version: "0.1.0" }) + "\n");
  await writeFile(path.join(projectRoot, "CHANGELOG.md"), "# Changelog\n\n## 0.1.0 - 2026-05-31\n\n- Release.\n");
  return projectRoot;
}

async function fakePretagTools(temp) {
  const binDir = path.join(temp, "bin");
  await mkdir(binDir, { recursive: true });
  await fakeExecutable(binDir, "git", `#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "rev-parse HEAD")
    echo "${head}"
    ;;
  "status --porcelain"|"tag --list v0.1.0"|"ls-remote --tags origin v0.1.0")
    true
    ;;
  *)
    echo "unexpected git invocation: $*" >&2
    exit 1
    ;;
esac
`);
  await fakeExecutable(binDir, "npm", `#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "run verify:release"|"run store:verify"|"run release:verify-artifact")
    exit 0
    ;;
  *)
    echo "unexpected npm invocation: $*" >&2
    exit 1
    ;;
esac
`);
  await fakeExecutable(binDir, "node", `#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "scripts/check-release-issues.mjs")
    exit 0
    ;;
  *)
    echo "unexpected node invocation: $*" >&2
    exit 1
    ;;
esac
`);
  await fakeExecutable(binDir, "gh", `#!/usr/bin/env bash
set -euo pipefail
args="$*"
case "$args" in
  "issue list --repo maddiedreese/tacket --milestone v0.1.0 --state open --json number,title,url")
    echo "[]"
    ;;
  "secret list --repo maddiedreese/tacket")
${requiredSecrets.map((secret) => `    echo "${secret}"`).join("\n")}
    ;;
  "run list --repo maddiedreese/tacket --workflow CI --branch main --limit 1 --json status,conclusion,headSha,url")
    cat <<JSON
[{"status":"completed","conclusion":"success","headSha":"${head}","url":"https://github.com/maddiedreese/tacket/actions/runs/101"}]
JSON
    ;;
  "run list --repo maddiedreese/tacket --workflow Release --limit 1 --json databaseId,status,conclusion,headSha,url")
    cat <<JSON
[{"databaseId":202,"status":"completed","conclusion":"success","headSha":"${head}","url":"https://github.com/maddiedreese/tacket/actions/runs/202"}]
JSON
    ;;
  "api repos/maddiedreese/tacket/actions/runs/202/artifacts")
    cat <<'JSON'
{"artifacts":[{"name":"tacket-release","expired":false,"size_in_bytes":12345}]}
JSON
    ;;
  "api repos/maddiedreese/tacket/actions/runs/202/jobs")
    cat <<'JSON'
{"jobs":[{"steps":[{"name":"Import Developer ID certificate","status":"completed","conclusion":"success"},{"name":"Sign app","status":"completed","conclusion":"success"},{"name":"Notarize DMG","status":"completed","conclusion":"success"},{"name":"Gatekeeper assessment","status":"completed","conclusion":"success"}]}]}
JSON
    ;;
  *)
    echo "unexpected gh invocation: $args" >&2
    exit 1
    ;;
esac
`);
  return { binDir };
}

async function fakeExecutable(binDir, name, source) {
  const file = path.join(binDir, name);
  await writeFile(file, source);
  await chmod(file, 0o755);
}

function runPretag(env = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["scripts/check-pretag-release.mjs"], {
      cwd: repoRoot,
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
