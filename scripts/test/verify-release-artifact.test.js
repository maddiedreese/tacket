import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import test from "node:test";

const root = path.resolve(new URL("../..", import.meta.url).pathname);
const head = "facefeed12345678facefeed12345678facefeed";

test("release artifact verifier downloads and checks release plus store artifacts", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-release-artifact-pass-"));
  try {
    const { binDir, npmLogPath } = await fakeArtifactTools(temp);
    const result = await runVerifyArtifact({ PATH: `${binDir}:${process.env.PATH}` });

    assert.equal(result.code, 0, result.stderr);
    assert.match(result.stdout, /Release workflow artifact verification passed for run 202/u);
    const npmLog = await readFile(npmLogPath, "utf8");
    assert.match(npmLog, /run release:verify-download -- --dir /u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("release artifact verifier rejects mismatched store extension zip", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-release-artifact-mismatch-"));
  try {
    const { binDir } = await fakeArtifactTools(temp, { mismatchedStoreZip: true });
    const result = await runVerifyArtifact({ PATH: `${binDir}:${process.env.PATH}` });

    assert.equal(result.code, 1);
    assert.match(result.stderr, /Chrome Web Store artifact zip does not match the release extension zip/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("release artifact verifier rejects a selected run from a different commit", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-release-artifact-head-fail-"));
  try {
    const { binDir } = await fakeArtifactTools(temp, { releaseHead: "0000000000000000000000000000000000000000" });
    const result = await runVerifyArtifact({ PATH: `${binDir}:${process.env.PATH}` }, ["--run-id", "202"]);

    assert.equal(result.code, 1);
    assert.match(result.stderr, /Release workflow run 202 head 0000000000000000000000000000000000000000 does not match local HEAD/u);
    assert.doesNotMatch(result.stdout, /Release workflow artifact verification passed/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("release artifact verifier rejects unknown arguments", async () => {
  const result = await runVerifyArtifact({}, ["--keeep"]);

  assert.equal(result.code, 1);
  assert.match(result.stderr, /Unknown argument: --keeep/u);
});

async function fakeArtifactTools(temp, options = {}) {
  const binDir = path.join(temp, "bin");
  const npmLogPath = path.join(temp, "npm.log");
  const releaseHead = options.releaseHead ?? head;
  await mkdir(binDir, { recursive: true });
  await fakeExecutable(binDir, "git", `#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "rev-parse" && "$2" == "HEAD" ]]; then
  echo "${head}"
  exit 0
fi
echo "unexpected git invocation: $*" >&2
exit 1
`);
  await fakeExecutable(binDir, "npm", `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "${npmLogPath}"
case "$*" in
  run\\ release:verify-download\\ --\\ --dir\\ *)
    exit 0
    ;;
  *)
    echo "unexpected npm invocation: $*" >&2
    exit 1
    ;;
esac
`);
  await fakeExecutable(binDir, "gh", `#!/usr/bin/env bash
set -euo pipefail
args="$*"
case "$args" in
  "run list --repo maddiedreese/tacket --workflow Release --limit 1 --json databaseId,status,conclusion,headSha,url")
    cat <<JSON
[{"databaseId":202,"status":"completed","conclusion":"success","headSha":"${releaseHead}","url":"https://github.com/maddiedreese/tacket/actions/runs/202"}]
JSON
    ;;
  "run view 202 --repo maddiedreese/tacket --json databaseId,status,conclusion,headSha,url")
    cat <<JSON
{"databaseId":202,"status":"completed","conclusion":"success","headSha":"${releaseHead}","url":"https://github.com/maddiedreese/tacket/actions/runs/202"}
JSON
    ;;
  run\\ download\\ 202\\ --repo\\ maddiedreese/tacket\\ --name\\ tacket-release\\ --dir\\ *)
    dir="$9"
    mkdir -p "$dir/chrome-web-store/screenshots"
    printf 'synthetic dmg\\n' > "$dir/Tacket.dmg"
    printf 'release zip bytes\\n' > "$dir/tacket-chrome-extension.zip"
    if [[ "${options.mismatchedStoreZip ? "true" : "false"}" == "true" ]]; then
      printf 'different store zip bytes\\n' > "$dir/chrome-web-store/tacket-chrome-extension.zip"
    else
      cp "$dir/tacket-chrome-extension.zip" "$dir/chrome-web-store/tacket-chrome-extension.zip"
    fi
    printf 'synthetic sums\\n' > "$dir/SHA256SUMS"
    printf 'icon\\n' > "$dir/chrome-web-store/icon-128.png"
    printf 'promo\\n' > "$dir/chrome-web-store/small-promo-440x280.png"
    printf 'Single Purpose\\nPermission Justification\\nhttps://gemini.google.com/*\\n' > "$dir/chrome-web-store/listing.md"
    printf 'No backend\\nNo analytics\\nsaved conversation is sent to the local Tacket app\\n' > "$dir/chrome-web-store/privacy.md"
    printf 'Upload \`tacket-chrome-extension.zip\`\\nReview every image before upload\\n' > "$dir/chrome-web-store/README.md"
    printf 'screenshot\\n' > "$dir/chrome-web-store/screenshots/01-capture-popup-1280x800.png"
    printf 'screenshot\\n' > "$dir/chrome-web-store/screenshots/02-local-bundle-1280x800.png"
    printf 'screenshot\\n' > "$dir/chrome-web-store/screenshots/03-local-library-1280x800.png"
    ;;
  *)
    echo "unexpected gh invocation: $args" >&2
    exit 1
    ;;
esac
`);
  return { binDir, npmLogPath };
}

async function fakeExecutable(binDir, name, source) {
  const file = path.join(binDir, name);
  await writeFile(file, source);
  await chmod(file, 0o755);
}

function runVerifyArtifact(env = {}, args = []) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["scripts/verify-release-artifact.mjs", ...args], {
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
