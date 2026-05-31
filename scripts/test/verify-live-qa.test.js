import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { writeBundle } from "../../packages/thread-format/src/index.js";

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
  assert.doesNotMatch(result.stdout, new RegExp(escapeRegex(root), "u"));
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
Tacket commit: test
Tacket version: 0.1.0
macOS: test
Chrome: test
Extension ID: abcdefghijklmnopqrstuvwxyzabcdef
Native host: installed
Capture folder: test
Release decision: Pass

## Preflight

- [x] Repo is clean or all local changes are intentional.

${providerSection("ChatGPT", bundles.ChatGPT)}

${providerSection("Claude", bundles.Claude)}

${providerSection("Gemini", bundles.Gemini)}
`;
}

function providerSection(name, bundle) {
  const { manifest } = bundle;
  return `## ${name}

Thread shape:
- [x] Text user turn
- [x] Text assistant turn
- [x] Code block
- [x] Long enough to require scrolling

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
    const child = spawn("node", [script, ...args], {
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
