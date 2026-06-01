import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import test from "node:test";

const root = path.resolve(new URL("../..", import.meta.url).pathname);

test("release issue checker passes when GitHub issue bodies are synced", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-release-issues-pass-"));
  try {
    const { binDir } = await fakeGh(temp);
    const result = await runIssues([], { PATH: `${binDir}:${process.env.PATH}` });

    assert.equal(result.code, 0, result.stderr);
    assert.match(result.stdout, /PASS #1 Live-test capture on ChatGPT, Claude, and Gemini/u);
    assert.match(result.stdout, /PASS #4 Cut v0\.1\.0 signed release/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("release issue checker reports drift and suggests sync", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-release-issues-drift-"));
  try {
    const { binDir } = await fakeGh(temp, { driftIssue: 3 });
    const result = await runIssues([], { PATH: `${binDir}:${process.env.PATH}` });

    assert.equal(result.code, 1);
    assert.match(result.stdout, /FAIL #3 Prepare Chrome Web Store draft listing - drift: body/u);
    assert.match(result.stderr, /Run `npm run release:issues -- --sync` to update release issue bodies\./u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("release issue checker dry-run sync reports drift without editing", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-release-issues-dry-run-"));
  try {
    const { binDir, logPath } = await fakeGh(temp, { driftIssue: 2 });
    const result = await runIssues(["--sync", "--dry-run"], { PATH: `${binDir}:${process.env.PATH}` });

    assert.equal(result.code, 0, result.stderr);
    assert.match(result.stdout, /WOULD-SYNC #2 Configure Developer ID signing and notarization/u);
    const log = await readFile(logPath, "utf8");
    assert.doesNotMatch(log, /issue edit/u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

test("release issue checker sync edits drifted issues", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "tacket-release-issues-sync-"));
  try {
    const { binDir, logPath } = await fakeGh(temp, { driftIssue: 4 });
    const result = await runIssues(["--sync"], { PATH: `${binDir}:${process.env.PATH}` });

    assert.equal(result.code, 0, result.stderr);
    assert.match(result.stdout, /SYNCED #4 Cut v0\.1\.0 signed release/u);
    const log = await readFile(logPath, "utf8");
    assert.match(log, /issue edit 4 --repo maddiedreese\/tacket --title Cut v0\.1\.0 signed release --body /u);
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
});

async function fakeGh(temp, options = {}) {
  const binDir = path.join(temp, "bin");
  const logPath = path.join(temp, "gh.log");
  await mkdir(binDir, { recursive: true });
  await fakeExecutable(binDir, "gh", `#!/usr/bin/env node
const fs = require("node:fs");
const args = process.argv.slice(2);
fs.appendFileSync(${JSON.stringify(logPath)}, args.join(" ") + "\\n");

const issueData = ${JSON.stringify(expectedIssues())};
const driftIssue = ${JSON.stringify(options.driftIssue ?? null)};

if (args[0] === "issue" && args[1] === "view") {
  const issue = issueData.find((item) => String(item.number) === args[2]);
  if (!issue) process.exit(1);
  const body = issue.number === driftIssue ? issue.body + "\\n\\nDrifted remote body." : issue.body;
  process.stdout.write(JSON.stringify({
    title: issue.title,
    body,
    url: \`https://github.com/maddiedreese/tacket/issues/\${issue.number}\`
  }));
  process.exit(0);
}

if (args[0] === "issue" && args[1] === "edit") {
  process.exit(0);
}

console.error("unexpected gh invocation: " + args.join(" "));
process.exit(1);
`);
  return { binDir, logPath };
}

function expectedIssues() {
  return [
    {
      number: 1,
      title: "Live-test capture on ChatGPT, Claude, and Gemini",
      body: `Before v0.1.0, validate the extension against the current live provider UIs and record a local QA report.

Checklist:

- [ ] Run \`npm run qa:live\` and fill the generated local report without private transcript text.
- [ ] Fill required tester/build/environment fields, including commit, macOS, Chrome, extension ID, native host, and capture folder.
- [ ] Test ChatGPT text, code, image/image-like attachment, and long-scroll capture.
- [ ] Test Claude text, code, attached/linked file, and long-scroll capture.
- [ ] Test Gemini text, code, and long-scroll capture.
- [ ] Confirm \`.tacket\` bundles validate with \`npm run qa:live:verify -- qa/live-capture/<report>.md\`.
- [ ] Confirm Mac app bundle review can open/copy transcript and display warnings.
- [ ] Confirm transfer to Clipboard, Codex, and Claude Code.
- [ ] Generate a public-safe issue summary with \`npm run qa:live:summary -- qa/live-capture/<report>.md\`.
- [ ] Open follow-up issues for any provider DOM regressions.

Do not attach private transcripts, bundle paths, extension IDs, screenshots with private content, local capture folders, API keys, tokens, or private file names. Use the sanitized summary output for public issue comments.`
    },
    {
      number: 2,
      title: "Configure Developer ID signing and notarization",
      body: `Public direct-download releases should be signed and notarized before a \`v*\` tag is pushed.

Checklist:

- [ ] Enroll or confirm Apple Developer Program access.
- [ ] Create/export a Developer ID Application certificate as a password-protected \`.p12\`.
- [ ] Run \`scripts/prepare-signing-secrets.sh --dry-run ...\` locally.
- [ ] Add \`DEVELOPER_ID_APPLICATION\` repository secret.
- [ ] Add \`DEVELOPER_ID_CERTIFICATE_BASE64\` repository secret.
- [ ] Add \`DEVELOPER_ID_CERTIFICATE_PASSWORD\` repository secret.
- [ ] Add \`KEYCHAIN_PASSWORD\` repository secret.
- [ ] Add \`APPLE_ID\` repository secret.
- [ ] Add \`APPLE_TEAM_ID\` repository secret.
- [ ] Add \`APPLE_APP_SPECIFIC_PASSWORD\` repository secret.
- [ ] Run \`npm run release:readiness\` and confirm signing/notarization secrets pass.
- [ ] Run the Release workflow manually and confirm signing/notarization succeeds.
- [ ] Confirm Gatekeeper accepts the signed/notarized artifacts with \`npm run release:assess\`.

The Release workflow intentionally fails tag releases when these secrets are missing.`
    },
    {
      number: 3,
      title: "Prepare Chrome Web Store draft listing",
      body: `Prepare the Chrome Web Store listing for v0.1.0 without submitting it for review.

Checklist:

- [ ] Create or confirm Chrome Web Store developer account.
- [ ] Review \`docs/CHROME_WEB_STORE.md\` listing copy.
- [ ] Review \`docs/STORE_ASSETS.md\` screenshot/privacy rules.
- [ ] Prepare the upload folder with \`npm run store:prepare\`.
- [ ] Confirm \`npm run store:verify\` passes.
- [ ] Upload \`dist/chrome-web-store/tacket-chrome-extension.zip\`.
- [ ] Use the permission justifications from \`docs/CHROME_WEB_STORE.md\`.
- [ ] Add privacy practices: no collection, no sale, no remote processing, local native messaging only.
- [ ] Review generated screenshots from non-private demo data.
- [ ] Save the item as a Chrome Web Store draft.
- [ ] Confirm the item remains in draft status and has not been submitted for review.

After the extension is approved later, install the Web Store extension and test native messaging with its real extension ID using \`npm run store:verify-id -- --extension-id <chrome-extension-id>\`.`
    },
    {
      number: 4,
      title: "Cut v0.1.0 signed release",
      body: `Create the first public Tacket release after live QA, signing/notarization, and Chrome Web Store prep are complete.

Checklist:

- [ ] Confirm all v0.1.0 milestone issues are closed or explicitly deferred.
- [ ] Confirm \`npm run release:status\` shows the latest CI and manual Release workflow runs match local \`HEAD\`.
- [ ] Confirm \`npm run release:status\` shows latest Release artifact contents are verified.
- [ ] Confirm \`npm run release:verify-artifact\` passes for the latest manual Release workflow run.
- [ ] Confirm \`npm run release:readiness\` passes.
- [ ] Date the changelog with \`npm run release:date-changelog -- --date YYYY-MM-DD\`.
- [ ] Confirm \`CHANGELOG.md\` no longer says \`Unreleased\` for 0.1.0.
- [ ] Confirm \`release.json\`, \`package.json\`, and extension manifest versions are aligned.
- [ ] Run \`npm run package:release\`.
- [ ] Confirm \`dist/chrome-web-store/\` was refreshed by \`npm run package:release\`.
- [ ] Confirm \`npm run release:pretag\` passes.
- [ ] Create and push tag \`v0.1.0\` with \`npm run release:tag -- --push\`.
- [ ] Confirm GitHub Release is created with \`Tacket.dmg\`, \`tacket-chrome-extension.zip\`, and \`SHA256SUMS\`.
- [ ] Confirm \`npm run release:postflight\` passes.
- [ ] Update website download link/copy if needed.`
    }
  ];
}

async function fakeExecutable(binDir, name, source) {
  const file = path.join(binDir, name);
  await writeFile(file, source);
  await chmod(file, 0o755);
}

function runIssues(args = [], env = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["scripts/check-release-issues.mjs", ...args], {
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
