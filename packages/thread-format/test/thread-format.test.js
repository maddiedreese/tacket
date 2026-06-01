import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import {
  detectPlatform,
  normalizeCapture,
  renderTranscript,
  splitTranscript,
  writeBundle,
  readBundle,
  validateCapture,
  warningsFromMessages
} from "../src/index.js";

test("detects supported source platforms", () => {
  assert.equal(detectPlatform("https://chatgpt.com/c/123"), "chatgpt");
  assert.equal(detectPlatform("https://claude.ai/chat/123"), "claude");
  assert.equal(detectPlatform("https://gemini.google.com/app/123"), "gemini");
});

test("rejects malformed capture payloads before writing bundles", () => {
  assert.throws(() => validateCapture(null), /JSON object/);
  assert.throws(() => validateCapture({ title: "No messages" }), /messages array/);
  assert.throws(() => validateCapture({ messages: [] }), /at least one message/);
});

test("renders raw transcript without summarizing", () => {
  const capture = normalizeCapture({
    title: "Implement auth",
    source: { url: "https://chatgpt.com/c/123" },
    messages: [
      {
        role: "user",
        content: [{ type: "text", text: "Use local storage only." }]
      },
      {
        role: "assistant",
        content: [{ type: "code", language: "js", text: "console.log('ok');" }]
      }
    ]
  });
  const transcript = renderTranscript(capture);
  assert.match(transcript, /full raw transcript/);
  assert.match(transcript, /Use local storage only\./);
  assert.match(transcript, /```js\nconsole\.log/);
});

test("writes and reads a .tacket bundle", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-test-"));
  try {
    const result = await writeBundle(
      {
        title: "Gemini planning",
        source: { url: "https://gemini.google.com/app/abc" },
        messages: [
          {
            role: "user",
            content: [{ type: "text", text: "Build the raw transfer." }]
          }
        ]
      },
      root
    );
    const manifest = await readBundle(result.bundlePath);
    const transcript = await readFile(result.transcriptPath, "utf8");
    const readme = await readFile(path.join(result.bundlePath, "README.md"), "utf8");
    assert.match(path.basename(result.bundlePath), /^\d{4}-\d{2}-\d{2} \d{2}\.\d{2} - Gemini - Gemini planning\.tacket$/u);
    assert.equal(manifest.source.platform, "gemini");
    assert.equal(manifest.messageCount, 1);
    assert.match(transcript, /Build the raw transfer/);
    assert.match(readme, /Open `transcript\.md`/u);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("uses Finder-style suffixes for duplicate readable bundle names", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-name-test-"));
  try {
    const capture = {
      title: "Same planning thread",
      capturedAt: "2026-06-01T10:05:00",
      source: { url: "https://chatgpt.com/c/same" },
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "Keep these easy to find." }]
        }
      ]
    };
    const first = await writeBundle(capture, root);
    const second = await writeBundle(capture, root);
    const names = (await readdir(root)).sort();

    assert.equal(path.basename(first.bundlePath), "2026-06-01 10.05 - ChatGPT - Same planning thread.tacket");
    assert.equal(path.basename(second.bundlePath), "2026-06-01 10.05 - ChatGPT - Same planning thread (2).tacket");
    assert.deepEqual(names, [
      "2026-06-01 10.05 - ChatGPT - Same planning thread (2).tacket",
      "2026-06-01 10.05 - ChatGPT - Same planning thread.tacket"
    ]);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("uses the first user message when provider titles are generic", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-generic-title-test-"));
  try {
    const result = await writeBundle(
      {
        title: "ChatGPT",
        capturedAt: "2026-06-01T11:00:00",
        source: { url: "https://chatgpt.com/?temporary-chat=true" },
        messages: [
          {
            role: "user",
            content: [{ type: "text", text: "Synthetic Tacket filesystem QA for ChatGPT. Reply with one sentence." }]
          },
          {
            role: "assistant",
            content: [{ type: "text", text: "Done." }]
          }
        ]
      },
      root
    );

    assert.equal(
      path.basename(result.bundlePath),
      "2026-06-01 11.00 - ChatGPT - Synthetic Tacket filesystem QA for ChatGPT.tacket"
    );
    const manifest = await readBundle(result.bundlePath);
    assert.equal(manifest.title, "Synthetic Tacket filesystem QA for ChatGPT");
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("stores captured data URL attachments as local files", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-attachment-test-"));
  try {
    const result = await writeBundle(
      {
        title: "Image capture",
        source: { url: "https://chatgpt.com/c/image" },
        messages: [
          {
            role: "user",
            content: [
              {
                type: "attachment",
                status: "captured",
                name: "tiny.png",
                mimeType: "image/png",
                dataUrl: "data:image/png;base64,aGVsbG8="
              }
            ]
          }
        ]
      },
      root
    );
    const bundle = await readBundle(result.bundlePath);
    const attachment = bundle.messages[0].content[0];
    assert.equal(attachment.status, "captured");
    assert.equal(attachment.dataUrl, undefined);
    assert.match(attachment.path, /attachments\/001-tiny-png\.png/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("downgrades invalid captured data URL attachments to references", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-invalid-attachment-test-"));
  try {
    const result = await writeBundle(
      {
        title: "Invalid image capture",
        source: { url: "https://chatgpt.com/c/image-invalid" },
        messages: [
          {
            role: "user",
            content: [
              {
                type: "attachment",
                status: "captured",
                name: "broken.png",
                mimeType: "image/png",
                dataUrl: "not-a-data-url"
              }
            ]
          }
        ]
      },
      root
    );
    const bundle = await readBundle(result.bundlePath);
    const attachment = bundle.messages[0].content[0];
    assert.equal(attachment.status, "referenced");
    assert.equal(attachment.dataUrl, undefined);
    assert.equal(bundle.attachments.referenced, 1);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("splits large transcript into ordered raw chunks", () => {
  const chunks = splitTranscript("a".repeat(2500), 1000);
  assert.ok(chunks.length > 1);
  assert.match(chunks[0], /chunk 1 of/);
  assert.match(chunks.at(-1), /raw transcript complete/);
});

test("rejects invalid raw transcript chunk sizes", () => {
  for (const value of [0, 999, 12.5, Number.NaN, Number.POSITIVE_INFINITY]) {
    assert.throws(() => splitTranscript("a".repeat(1200), value), /Chunk size must be an integer/u);
  }
});

test("adds local possible-secret warnings without redacting raw content", async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), "tacket-warning-test-"));
  const apiKey = "sk-1234567890abcdefghijklmnopqrstuvwxyz";
  try {
    const result = await writeBundle(
      {
        title: "Secret warning",
        source: { url: "https://chatgpt.com/c/secret" },
        messages: [
          {
            role: "user",
            content: [{ type: "text", text: `Here is a test key: ${apiKey}` }]
          }
        ]
      },
      root
    );
    const manifest = await readBundle(result.bundlePath);
    const transcript = await readFile(result.transcriptPath, "utf8");
    assert.equal(manifest.warnings[0].type, "possible_secret");
    assert.equal(manifest.warnings[0].kind, "openai_api_key");
    assert.match(transcript, new RegExp(apiKey));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("detects possible secret warning kinds", () => {
  const warnings = warningsFromMessages([
    {
      id: "m1",
      content: [{ type: "code", text: "const key = 'ghp_abcdefghijklmnopqrstuvwxyz123456';" }]
    }
  ]);
  assert.equal(warnings[0].kind, "github_token");
});

test("does not classify Anthropic keys as OpenAI keys", () => {
  const warnings = warningsFromMessages([
    {
      id: "m1",
      content: [{ type: "text", text: "sk-ant-1234567890abcdefghijklmnopqrstuvwxyz" }]
    }
  ]);
  assert.deepEqual(warnings.map((warning) => warning.kind), ["anthropic_api_key"]);
});
