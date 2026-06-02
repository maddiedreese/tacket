import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const repo = "maddiedreese/tacket";
const args = process.argv.slice(2);
const sync = args.includes("--sync");
const dryRun = args.includes("--dry-run");

if (args.some((arg) => !["--sync", "--dry-run"].includes(arg))) {
  throw new Error("Usage: npm run release:issues -- [--sync] [--dry-run]");
}

const issues = releaseIssues();
const results = [];

for (const issue of issues) {
  const remote = await ghJson(["issue", "view", String(issue.number), "--repo", repo, "--json", "title,body,url"]);
  const titleMatches = remote.title === issue.title;
  const bodyMatches = normalize(remote.body) === normalize(issue.body);

  if (sync && (!titleMatches || !bodyMatches)) {
    if (dryRun) {
      results.push({ issue, status: "would-sync", url: remote.url });
    } else {
      await gh(["issue", "edit", String(issue.number), "--repo", repo, "--title", issue.title, "--body", issue.body]);
      results.push({ issue, status: "synced", url: remote.url });
    }
    continue;
  }

  if (titleMatches && bodyMatches) {
    results.push({ issue, status: "pass", url: remote.url });
  } else {
    const drift = [];
    if (!titleMatches) drift.push("title");
    if (!bodyMatches) drift.push("body");
    results.push({ issue, status: "fail", message: `drift: ${drift.join(", ")}`, url: remote.url });
  }
}

for (const result of results) {
  const mark = result.status.toUpperCase();
  console.log(`${mark} #${result.issue.number} ${result.issue.title}${result.message ? ` - ${result.message}` : ""}`);
  if (result.url) console.log(`  ${result.url}`);
}

if (results.some((result) => result.status === "fail")) {
  console.error("Run `npm run release:issues -- --sync` to update release issue bodies.");
  process.exit(1);
}

function releaseIssues() {
  return [
    {
      number: 1,
      title: "Live-test browser capture and desktop app imports",
      body: `Before v0.1.0, validate the extension against the current live provider UIs, validate Mac app local imports and desktop capture, and record local QA evidence.

Checklist:

- [ ] Run \`npm run qa:live\` and fill the generated local report without private transcript text.
- [ ] Fill required tester/build/environment fields, including commit, macOS, Chrome, extension ID, native host, and save folder.
- [ ] Test browser ChatGPT text, code, image/image-like attachment, and long-scroll capture.
- [ ] Test browser Claude text, code, attached/linked file, and long-scroll capture.
- [ ] Test browser Gemini text, code, and long-scroll capture.
- [ ] Confirm \`.tacket\` bundles validate with \`npm run qa:live:verify -- qa/live-capture/<report>.md\`.
- [ ] Test exact local import for Codex App, Claude App, and Claude Code from the Mac app.
- [ ] Test desktop capture for ChatGPT, Claude, and Codex desktop apps from the Mac app.
- [ ] Confirm desktop capture clearly prompts when Accessibility or Screen Recording permission is missing.
- [ ] Confirm Mac app bundle review can open/copy transcript and display warnings.
- [ ] Confirm transfer to Clipboard, Codex, and Claude Code.
- [ ] Generate a public-safe issue summary with \`npm run qa:live:summary -- qa/live-capture/<report>.md\`.
- [ ] Open follow-up issues for any provider DOM, local import, or desktop capture regressions.

Do not attach private chat text, saved chat paths, extension IDs, screenshots with private content, local save folders, API keys, tokens, or private file names. Use the sanitized summary output for public issue comments.`
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

function normalize(value) {
  return String(value ?? "").replace(/\r\n/gu, "\n").trim();
}

async function ghJson(args) {
  return JSON.parse(await gh(args));
}

async function gh(args) {
  const { stdout } = await execFileAsync("gh", args, {
    maxBuffer: 1024 * 1024 * 10
  });
  return stdout.trim();
}
