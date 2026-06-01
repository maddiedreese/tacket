import { mkdir, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import os from "node:os";
import path from "node:path";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const outDir = path.join(root, "qa", "live-capture");
const now = new Date();
const stamp = now.toISOString().replace(/[:.]/g, "-");
const reportPath = path.join(outDir, `${stamp}.md`);
const commit = await commandOutput("git", ["rev-parse", "--short=12", "HEAD"]).catch(() => "");

await mkdir(outDir, { recursive: true });
await writeFile(reportPath, report(now, commit), "utf8");
console.log(reportPath);

function report(date, commit) {
  return `# Tacket Live Capture QA

Date: ${date.toISOString()}
Tester:
Tacket commit: ${commit}
Tacket version: 0.1.0
macOS:
Chrome:
Extension ID:
Native host:
Save folder:
Release decision: Unset

Do not paste private transcript text, screenshots with private content, API keys, tokens, or private file names into this report. Record counts, paths, statuses, and synthetic/minimal notes only.

After completing the checklist, fill the top-level environment fields, the three provider saved chat paths, and the evidence fields. Use numbers from each saved chat's \`manifest.json\`: \`Message count\`, \`Attachment counts\` as \`saved / referenced / unavailable\`, and \`Warning kinds\` as \`none\` or comma-separated warning kinds. Use \`yes\`, \`pass\`, or \`ok\` for evidence checks that passed. The verifier requires a real 32-letter Chrome extension ID and non-placeholder tester/build/environment fields.

Then verify this report with:

\`\`\`bash
npm run qa:live:verify -- ${reportPath}
\`\`\`

## Preflight

- [ ] Repo is clean or all local changes are intentional.
- [ ] \`npm run package:release\` passed locally or in GitHub CI.
- [ ] Production extension manifest does not include \`file:///*\`.
- [ ] Native messaging connector is installed for the tested Chrome extension ID.
- [ ] Save folder is known and writable.
- [ ] Existing test bundles are moved aside or clearly separated.

## ChatGPT

Thread shape:
- [ ] Text user turn
- [ ] Text assistant turn
- [ ] Code block
- [ ] Image or image-like attachment
- [ ] Long enough to require scrolling

Capture evidence:
- Bundle path:
- Message count:
- Attachment counts: captured / referenced / unavailable
- Warning kinds:
- Transcript opens:
- Message order preserved:
- Roles correct:
- Code indentation preserved:
- Images captured or referenced clearly:
- Notes:

## Claude

Thread shape:
- [ ] Text user turn
- [ ] Text assistant turn
- [ ] Code block
- [ ] Attached or linked file
- [ ] Long enough to require scrolling

Capture evidence:
- Bundle path:
- Message count:
- Attachment counts: captured / referenced / unavailable
- Warning kinds:
- Transcript opens:
- Message order preserved:
- Roles correct:
- Code indentation preserved:
- Attachments captured or referenced clearly:
- Notes:

## Gemini

Thread shape:
- [ ] Text user turn
- [ ] Text model turn
- [ ] Code block
- [ ] Long enough to require scrolling

Capture evidence:
- Bundle path:
- Message count:
- Attachment counts: captured / referenced / unavailable
- Warning kinds:
- Transcript opens:
- Message order preserved:
- Roles correct:
- Code indentation preserved:
- Notes:

## Mac App Review

- [ ] Choose Saved Chat shows title, platform, URL, saved date, and message count.
- [ ] Possible-secret warnings render without exposing secret values in app chrome.
- [ ] Reveal in Finder opens Finder at the selected saved chat.
- [ ] Open Conversation File opens \`transcript.md\`.
- [ ] Copy Conversation copies the full saved conversation.
- [ ] Choose Save Folder persists to \`~/Library/Application Support/Tacket/config.json\`.
- [ ] Reset Folder returns to \`~/Documents/Tacket Captures\`.

## Transfer

- [ ] Clipboard transfer copies the full saved conversation.
- [ ] Codex transfer launches Terminal and requests paste.
- [ ] Claude Code transfer launches Terminal and requests paste.
- [ ] \`--dry-run\` CLI transfer works for Codex.
- [ ] \`--dry-run\` CLI transfer works for Claude Code.
- [ ] Small chunk size produces ordered raw chunks.

## Release Decision

Set \`Release decision:\` at the top of this report to one of:

- Pass
- Fail
- Needs follow-up issue(s)

Follow-up issue links:

`;
}

function commandOutput(command, args) {
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
      if (code === 0) resolve(Buffer.concat(stdout).toString("utf8").trim());
      else reject(new Error(Buffer.concat(stderr).toString("utf8").trim() || `${command} ${args.join(" ")} failed with ${code}`));
    });
  });
}
