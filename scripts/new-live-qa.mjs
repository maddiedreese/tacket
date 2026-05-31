import { mkdir, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const outDir = path.join(root, "qa", "live-capture");
const now = new Date();
const stamp = now.toISOString().replace(/[:.]/g, "-");
const reportPath = path.join(outDir, `${stamp}.md`);

await mkdir(outDir, { recursive: true });
await writeFile(reportPath, report(now), "utf8");
console.log(reportPath);

function report(date) {
  return `# Tacket Live Capture QA

Date: ${date.toISOString()}
Tester:
Tacket commit:
Tacket version: 0.1.0
macOS:
Chrome:
Extension ID:
Native host:
Capture folder:
Release decision: Unset

Do not paste private transcript text, screenshots with private content, API keys, tokens, or private file names into this report. Record counts, paths, statuses, and synthetic/minimal notes only.

After completing the checklist, fill the three provider bundle paths plus evidence fields. Use numbers from each bundle's \`manifest.json\`: \`Message count\`, \`Attachment counts\` as \`captured / referenced / unavailable\`, and \`Warning kinds\` as \`none\` or comma-separated warning kinds. Use \`yes\`, \`pass\`, or \`ok\` for evidence checks that passed.

Then verify this report with:

\`\`\`bash
npm run qa:live:verify -- ${reportPath}
\`\`\`

## Preflight

- [ ] Repo is clean or all local changes are intentional.
- [ ] \`npm run package:release\` passed locally or in GitHub CI.
- [ ] Production extension manifest does not include \`file:///*\`.
- [ ] Native messaging connector is installed for the tested Chrome extension ID.
- [ ] Capture folder is known and writable.
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

- [ ] Choose Bundle shows title, platform, URL, captured date, and message count.
- [ ] Possible-secret warnings render without exposing secret values in app chrome.
- [ ] Reveal Bundle opens Finder at the selected bundle.
- [ ] Open Transcript opens \`transcript.md\`.
- [ ] Copy Transcript copies the raw transcript.
- [ ] Choose Capture Folder persists to \`~/Library/Application Support/Tacket/config.json\`.
- [ ] Reset Folder returns to \`~/Documents/Tacket Captures\`.

## Transfer

- [ ] Clipboard transfer copies raw transcript.
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
