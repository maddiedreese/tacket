import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import test from "node:test";

const root = path.resolve(new URL("../..", import.meta.url).pathname);
const secretEnv = {
  DEVELOPER_ID_CERTIFICATE_PASSWORD: "certificate-password-secret",
  KEYCHAIN_PASSWORD: "keychain-password-secret",
  APPLE_APP_SPECIFIC_PASSWORD: "apple-app-specific-password-secret"
};

test("signing secret helper dry run validates inputs without printing secret values", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-signing-secrets-pass-"));
  try {
    const certificate = path.join(temp, "developer-id.p12");
    await writeFile(certificate, "synthetic p12 fixture\n");
    const { binDir } = await fakeSigningTools(temp);

    const result = await runSigningSecrets([
      "--dry-run",
      "--repo",
      "maddiedreese/tacket",
      "--certificate",
      certificate,
      "--developer-id-application",
      "Developer ID Application: Tacket Test (TEAMID)",
      "--apple-id",
      "release@example.com",
      "--apple-team-id",
      "TEAMID"
    ], {
      ...secretEnv,
      PATH: `${binDir}:${process.env.PATH}`
    });

    assert.equal(result.code, 0, result.stderr);
    for (const name of [
      "DEVELOPER_ID_APPLICATION",
      "DEVELOPER_ID_CERTIFICATE_BASE64",
      "DEVELOPER_ID_CERTIFICATE_PASSWORD",
      "KEYCHAIN_PASSWORD",
      "APPLE_ID",
      "APPLE_TEAM_ID",
      "APPLE_APP_SPECIFIC_PASSWORD"
    ]) {
      assert.match(result.stdout, new RegExp(`Would set ${name} on maddiedreese/tacket`, "u"));
    }
    assert.match(result.stdout, /Dry run complete\. No GitHub secrets were changed\./u);
    assert.doesNotMatch(result.stdout, /certificate-password-secret/u);
    assert.doesNotMatch(result.stdout, /keychain-password-secret/u);
    assert.doesNotMatch(result.stdout, /apple-app-specific-password-secret/u);
    assert.doesNotMatch(result.stdout, /release@example\.com/u);
    assert.doesNotMatch(result.stdout, /Developer ID Application: Tacket Test/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("signing secret helper refuses to run when required secret env is missing", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-signing-secrets-env-fail-"));
  try {
    const certificate = path.join(temp, "developer-id.p12");
    await writeFile(certificate, "synthetic p12 fixture\n");

    const result = await runSigningSecrets([
      "--dry-run",
      "--certificate",
      certificate,
      "--developer-id-application",
      "Developer ID Application: Tacket Test (TEAMID)",
      "--apple-id",
      "release@example.com",
      "--apple-team-id",
      "TEAMID"
    ], {
      DEVELOPER_ID_CERTIFICATE_PASSWORD: null,
      KEYCHAIN_PASSWORD: "keychain-password-secret",
      APPLE_APP_SPECIFIC_PASSWORD: "apple-app-specific-password-secret"
    });

    assert.equal(result.code, 2);
    assert.match(result.stderr, /Set DEVELOPER_ID_CERTIFICATE_PASSWORD before running this script\./u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

async function fakeSigningTools(temp) {
  const binDir = path.join(temp, "bin");
  await mkdir(binDir, { recursive: true });
  await fakeExecutable(binDir, "gh", `#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "auth" && "$2" == "status" ]]; then
  exit 0
fi
echo "unexpected gh invocation: $*" >&2
exit 1
`);
  await fakeExecutable(binDir, "openssl", `#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "pkcs12" ]]; then
  exit 0
fi
echo "unexpected openssl invocation: $*" >&2
exit 1
`);
  await fakeExecutable(binDir, "security", `#!/usr/bin/env bash
exit 1
`);
  return { binDir };
}

async function fakeExecutable(binDir, name, source) {
  const file = path.join(binDir, name);
  await writeFile(file, source);
  await chmod(file, 0o755);
}

function runSigningSecrets(args, env = {}) {
  return new Promise((resolve, reject) => {
    const childEnv = { ...process.env };
    for (const [name, value] of Object.entries(env)) {
      if (value === null) delete childEnv[name];
      else childEnv[name] = value;
    }
    const child = spawn("bash", ["scripts/prepare-signing-secrets.sh", ...args], {
      cwd: root,
      env: childEnv,
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
