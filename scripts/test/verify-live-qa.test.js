import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { writeBundle } from "../../packages/thread-format/src/index.js";

const currentHead = (await runScript("git", ["rev-parse", "--short=12", "HEAD"])).stdout.trim();

test("verifies live QA report evidence against provider manifests", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-live-qa-pass-"));
  const bundles = {
    ChatGPT: await providerBundle(root, "chatgpt", "https://chatgpt.com/c/live"),
    Claude: await providerBundle(root, "claude", "https://claude.ai/chat/live"),
    Gemini: await providerBundle(root, "gemini", "https://gemini.google.com/app/live")
  };
  const reportPath = path.join(root, "report.md");
  await writeFile(reportPath, liveQaReport(bundles), "utf8");

  const result = await runVerify(reportPath);
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /Live QA verification passed/u);
});

test("summarizes live QA reports without leaking local bundle paths", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-live-qa-summary-"));
  const bundles = {
    ChatGPT: await providerBundle(root, "chatgpt", "https://chatgpt.com/c/live"),
    Claude: await providerBundle(root, "claude", "https://claude.ai/chat/live"),
    Gemini: await providerBundle(root, "gemini", "https://gemini.google.com/app/live")
  };
  const reportPath = path.join(root, "report.md");
  await writeFile(reportPath, liveQaReport(bundles), "utf8");

  const result = await runScript("scripts/summarize-live-qa.mjs", [reportPath]);
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /## Live QA Summary/u);
  assert.match(result.stdout, /\| ChatGPT \| 2 \| 0 \/ 0 \/ 0 \| none/u);
  assert.match(result.stdout, /Release decision: Pass/u);
  assert.doesNotMatch(result.stdout, /Bundle path/u);
  assert.doesNotMatch(result.stdout, /automated/u);
  assert.doesNotMatch(result.stdout, /abcdefghijklmnopabcdefghijklmnop/u);
  assert.doesNotMatch(result.stdout, /\/tmp\/tacket-live-capture/u);
  assert.doesNotMatch(result.stdout, new RegExp(escapeRegex(root), "u"));
});

test("refuses to print live QA summaries that would leak private report values", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-live-qa-summary-leak-"));
  const bundles = {
    ChatGPT: await providerBundle(root, "chatgpt", "https://chatgpt.com/c/live"),
    Claude: await providerBundle(root, "claude", "https://claude.ai/chat/live"),
    Gemini: await providerBundle(root, "gemini", "https://gemini.google.com/app/live")
  };
  const reportPath = path.join(root, "report.md");
  await writeFile(
    reportPath,
    liveQaReport(bundles).replace("Native host: installed", "Native host: abcdefghijklmnopabcdefghijklmnop"),
    "utf8"
  );

  const result = await runScript("scripts/summarize-live-qa.mjs", [reportPath, "--no-verify"]);
  assert.notEqual(result.code, 0);
  assert.match(result.stderr, /would leak private extension ID/u);
});

test("rejects live QA reports with mismatched evidence or secret-like text", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-live-qa-fail-"));
  const bundles = {
    ChatGPT: await providerBundle(root, "chatgpt", "https://chatgpt.com/c/live"),
    Claude: await providerBundle(root, "claude", "https://claude.ai/chat/live"),
    Gemini: await providerBundle(root, "gemini", "https://gemini.google.com/app/live")
  };
  const reportPath = path.join(root, "report.md");
  await writeFile(
    reportPath,
    liveQaReport(bundles)
      .replace("Message count: 2", "Message count: 999")
      .replace("Notes:", "Notes: sk-testtokenabcdefghijklmnopqrstuvwxyz"),
    "utf8"
  );

  const result = await runVerify(reportPath);
  assert.notEqual(result.code, 0);
  assert.match(result.stderr, /Message count 999 does not match manifest\.json 2/u);
  assert.match(result.stderr, /secret-like text/u);
});

test("rejects live QA reports with placeholder environment evidence", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-live-qa-env-fail-"));
  const bundles = {
    ChatGPT: await providerBundle(root, "chatgpt", "https://chatgpt.com/c/live"),
    Claude: await providerBundle(root, "claude", "https://claude.ai/chat/live"),
    Gemini: await providerBundle(root, "gemini", "https://gemini.google.com/app/live")
  };
  const reportPath = path.join(root, "report.md");
  await writeFile(
    reportPath,
    liveQaReport(bundles)
      .replace(`Tacket commit: ${currentHead}`, "Tacket commit: test")
      .replace("Extension ID: abcdefghijklmnopabcdefghijklmnop", "Extension ID: not-a-real-id"),
    "utf8"
  );

  const result = await runVerify(reportPath);
  assert.notEqual(result.code, 0);
  assert.match(result.stderr, /Tacket commit must identify the live QA environment/u);
  assert.match(result.stderr, /Extension ID must be the 32-letter Chrome extension ID tested/u);
});

test("rejects live QA reports for a different commit", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-live-qa-commit-fail-"));
  const bundles = {
    ChatGPT: await providerBundle(root, "chatgpt", "https://chatgpt.com/c/live"),
    Claude: await providerBundle(root, "claude", "https://claude.ai/chat/live"),
    Gemini: await providerBundle(root, "gemini", "https://gemini.google.com/app/live")
  };
  const reportPath = path.join(root, "report.md");
  await writeFile(
    reportPath,
    liveQaReport(bundles).replace(`Tacket commit: ${currentHead}`, "Tacket commit: 000000000000"),
    "utf8"
  );

  const result = await runVerify(reportPath);
  assert.notEqual(result.code, 0);
  assert.match(result.stderr, /Tacket commit 000000000000 must match current HEAD/u);
});

test("rejects live QA reports missing required checklist items", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-live-qa-checklist-fail-"));
  const bundles = {
    ChatGPT: await providerBundle(root, "chatgpt", "https://chatgpt.com/c/live"),
    Claude: await providerBundle(root, "claude", "https://claude.ai/chat/live"),
    Gemini: await providerBundle(root, "gemini", "https://gemini.google.com/app/live")
  };
  const reportPath = path.join(root, "report.md");
  await writeFile(
    reportPath,
    liveQaReport(bundles).replace("- [x] Clipboard transfer copies raw transcript.\n", ""),
    "utf8"
  );

  const result = await runVerify(reportPath);
  assert.notEqual(result.code, 0);
  assert.match(result.stderr, /Required checked item missing: Clipboard transfer copies raw transcript/u);
});

async function providerBundle(root, platform, url) {
  const { bundlePath, manifest } = await writeBundle({
    title: `${platform} live QA`,
    source: { platform, url },
    messages: [
      {
        role: "user",
        content: [{ type: "text", text: "Please preserve this raw test thread." }]
      },
      {
        role: "assistant",
        content: [
          { type: "text", text: "This is synthetic live QA evidence." },
          { type: "code", language: "js", text: "console.log('tacket');" }
        ]
      }
    ]
  }, root);
  return { bundlePath, manifest };
}

function liveQaReport(bundles) {
  return `# Tacket Live Capture QA

Date: 2026-05-31T00:00:00.000Z
Tester: automated
Tacket commit: ${currentHead}
Tacket version: 0.1.0
macOS: 15.5
Chrome: 125.0.0.0
Extension ID: abcdefghijklmnopabcdefghijklmnop
Native host: installed
Capture folder: /tmp/tacket-live-capture
Release decision: Pass

## Preflight

- [x] Repo is clean or all local changes are intentional.
- [x] \`npm run package:release\` passed locally or in GitHub CI.
- [x] Production extension manifest does not include \`file:///*\`.
- [x] Native messaging connector is installed for the tested Chrome extension ID.
- [x] Capture folder is known and writable.
- [x] Existing test bundles are moved aside or clearly separated.

${providerSection("ChatGPT", bundles.ChatGPT)}

${providerSection("Claude", bundles.Claude)}

${providerSection("Gemini", bundles.Gemini)}

## Mac App Review

- [x] Choose Bundle shows title, platform, URL, captured date, and message count.
- [x] Possible-secret warnings render without exposing secret values in app chrome.
- [x] Reveal Bundle opens Finder at the selected bundle.
- [x] Open Transcript opens \`transcript.md\`.
- [x] Copy Transcript copies the raw transcript.
- [x] Choose Capture Folder persists to \`~/Library/Application Support/Tacket/config.json\`.
- [x] Reset Folder returns to \`~/Documents/Tacket Captures\`.

## Transfer

- [x] Clipboard transfer copies raw transcript.
- [x] Codex transfer launches Terminal and requests paste.
- [x] Claude Code transfer launches Terminal and requests paste.
- [x] \`--dry-run\` CLI transfer works for Codex.
- [x] \`--dry-run\` CLI transfer works for Claude Code.
- [x] Small chunk size produces ordered raw chunks.
`;
}

function providerSection(name, bundle) {
  const { manifest } = bundle;
  const assistantTurn = name === "Gemini" ? "Text model turn" : "Text assistant turn";
  const providerOnlyRows = {
    ChatGPT: "- [x] Image or image-like attachment\n",
    Claude: "- [x] Attached or linked file\n",
    Gemini: ""
  };
  return `## ${name}

Thread shape:
- [x] Text user turn
- [x] ${assistantTurn}
- [x] Code block
${providerOnlyRows[name]}- [x] Long enough to require scrolling

Capture evidence:
- Bundle path: ${bundle.bundlePath}
- Message count: ${manifest.messageCount}
- Attachment counts: ${manifest.attachments.captured} / ${manifest.attachments.referenced} / ${manifest.attachments.unavailable}
- Warning kinds: none
- Transcript opens: yes
- Message order preserved: yes
- Roles correct: yes
- Code indentation preserved: yes
- Notes:
`;
}

function runVerify(reportPath) {
  return runScript("scripts/verify-live-qa.mjs", [reportPath]);
}

function runScript(script, args) {
  return new Promise((resolve, reject) => {
    const isNodeScript = script.endsWith(".mjs");
    const child = spawn(isNodeScript ? "node" : script, isNodeScript ? [script, ...args] : args, {
      cwd: path.resolve(new URL("../..", import.meta.url).pathname),
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
