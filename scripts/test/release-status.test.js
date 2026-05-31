import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import test from "node:test";

const root = path.resolve(new URL("../..", import.meta.url).pathname);
const head = "1234567890abcdef1234567890abcdef12345678";

test("release status summarizes current green automation and external blockers", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-release-status-"));
  try {
    const { binDir, nodeLogPath } = await fakeReleaseStatusTools(temp);
    const result = await runReleaseStatus({ PATH: `${binDir}:${process.env.PATH}` });

    assert.equal(result.code, 0, result.stderr);
    assert.match(result.stdout, /Tacket v0\.1\.0 release status/u);
    assert.match(result.stdout, /Repository settings: configured/u);
    assert.match(result.stdout, /Website build config: configured/u);
    assert.match(result.stdout, /Security reporting\/dependency alerts: configured/u);
    assert.match(result.stdout, /Local HEAD: 1234567890ab/u);
    assert.match(result.stdout, /Latest CI on main: completed\/success @ 1234567890ab \(matches HEAD\)/u);
    assert.match(result.stdout, /Latest manual Release workflow: completed\/success @ 1234567890ab \(matches HEAD\)/u);
    assert.match(result.stdout, /Latest Release artifact: available/u);
    assert.match(result.stdout, /Latest Release artifact contents: verified/u);
    assert.match(result.stdout, /Release issue checklists: synced/u);
    assert.match(result.stdout, /Open v0\.1\.0 milestone issues: 1 open/u);
    assert.match(result.stdout, /Signing\/notarization secrets: 7 missing/u);
    assert.match(result.stdout, /v0\.1\.0 GitHub Release: not published/u);
    assert.match(result.stdout, /#1 Live-test capture/u);
    assert.match(result.stdout, /Missing signing\/notarization secrets: DEVELOPER_ID_APPLICATION/u);
    assert.match(result.stdout, /Next commands:/u);
    assert.match(result.stdout, /npm run release:pretag/u);

    const nodeLog = await readFile(nodeLogPath, "utf8");
    assert.match(nodeLog, /scripts\/verify-release-artifact\.mjs/u);
    assert.match(nodeLog, /scripts\/check-release-issues\.mjs/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

async function fakeReleaseStatusTools(temp) {
  const binDir = path.join(temp, "bin");
  const nodeLogPath = path.join(temp, "node.log");
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
  await fakeExecutable(binDir, "node", `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "${nodeLogPath}"
case "$*" in
  scripts/verify-release-artifact.mjs|scripts/check-release-issues.mjs)
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
  "repo view maddiedreese/tacket --json nameWithOwner,visibility,deleteBranchOnMerge,hasProjectsEnabled,hasWikiEnabled,isSecurityPolicyEnabled")
    cat <<'JSON'
{"nameWithOwner":"maddiedreese/tacket","visibility":"PUBLIC","deleteBranchOnMerge":true,"hasProjectsEnabled":false,"hasWikiEnabled":false,"isSecurityPolicyEnabled":true}
JSON
    ;;
  "api repos/maddiedreese/tacket/private-vulnerability-reporting")
    cat <<'JSON'
{"enabled":true}
JSON
    ;;
  "api repos/maddiedreese/tacket/vulnerability-alerts -i"|"api repos/maddiedreese/tacket/automated-security-fixes -i")
    echo "HTTP/2 204"
    ;;
  "issue list --repo maddiedreese/tacket --milestone v0.1.0 --state open --json number,title,url")
    cat <<'JSON'
[{"number":1,"title":"Live-test capture","url":"https://github.com/maddiedreese/tacket/issues/1"}]
JSON
    ;;
  "secret list --repo maddiedreese/tacket")
    true
    ;;
  "run list --repo maddiedreese/tacket --workflow CI --limit 1 --json databaseId,status,conclusion,headSha,url --branch main")
    cat <<JSON
[{"databaseId":101,"status":"completed","conclusion":"success","headSha":"${head}","url":"https://github.com/maddiedreese/tacket/actions/runs/101"}]
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
  "release list --repo maddiedreese/tacket --limit 100")
    true
    ;;
  *)
    echo "unexpected gh invocation: $args" >&2
    exit 1
    ;;
esac
`);
  return { binDir, nodeLogPath };
}

async function fakeExecutable(binDir, name, source) {
  const file = path.join(binDir, name);
  await writeFile(file, source);
  await chmod(file, 0o755);
}

function runReleaseStatus(env = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["scripts/release-status.mjs"], {
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
