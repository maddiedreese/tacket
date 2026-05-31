import { mkdir, writeFile, copyFile, readFile } from "node:fs/promises";
import { createHash, randomUUID } from "node:crypto";
import path from "node:path";

export const SCHEMA_VERSION = "0.1.0";

export function detectPlatform(url = "") {
  const host = safeUrl(url)?.hostname ?? "";
  if (host === "chatgpt.com" || host === "chat.openai.com") return "chatgpt";
  if (host === "claude.ai") return "claude";
  if (host === "gemini.google.com") return "gemini";
  return "unknown";
}

export function normalizeCapture(input) {
  validateCapture(input);
  const now = new Date().toISOString();
  const sourceUrl = String(input?.source?.url ?? "");
  const platform = input?.source?.platform ?? detectPlatform(sourceUrl);
  const messages = Array.isArray(input?.messages) ? input.messages : [];
  const normalizedMessages = messages.map((message, index) =>
    normalizeMessage(message, index, platform, sourceUrl)
  );
  const id = input?.id ?? stableId(`${sourceUrl}:${now}:${normalizedMessages.length}`);
  const title = sanitizeTitle(input?.title ?? titleFromUrl(sourceUrl) ?? "Untitled Thread");

  return {
    schemaVersion: SCHEMA_VERSION,
    id,
    title,
    source: {
      platform,
      url: sourceUrl
    },
    capturedAt: input?.capturedAt ?? now,
    messages: normalizedMessages
  };
}

export function validateCapture(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new Error("Capture payload must be a JSON object.");
  }
  if (!Array.isArray(input.messages)) {
    throw new Error("Capture payload must include a messages array.");
  }
  if (input.messages.length === 0) {
    throw new Error("Capture payload must include at least one message.");
  }
}

export function renderTranscript(capture, options = {}) {
  const includeEnvelope = options.includeEnvelope !== false;
  const lines = [];

  if (includeEnvelope) {
    lines.push("The following is the full raw transcript of an AI chat thread being transferred into this coding session.");
    lines.push("Continue from it. Do not treat this as a summary.");
    lines.push("");
    lines.push("[raw transcript begins]");
    lines.push("");
  }

  lines.push(`# ${capture.title}`);
  lines.push("");
  lines.push(`Source: ${capture.source.platform}`);
  if (capture.source.url) lines.push(`URL: ${capture.source.url}`);
  lines.push(`Captured: ${capture.capturedAt}`);
  lines.push("");

  for (const message of capture.messages) {
    lines.push(`## ${formatRole(message.role, message.author)}`);
    lines.push("");
    for (const part of message.content) {
      if (part.type === "text") {
        lines.push(part.text.trimEnd());
        lines.push("");
      } else if (part.type === "code") {
        lines.push(`\`\`\`${part.language ?? ""}`.trimEnd());
        lines.push(part.text.replace(/\s+$/u, ""));
        lines.push("```");
        lines.push("");
      } else if (part.type === "attachment") {
        lines.push(renderAttachment(part));
        lines.push("");
      }
    }
  }

  if (includeEnvelope) {
    lines.push("[raw transcript ends]");
    lines.push("");
  }

  return lines.join("\n").replace(/\n{4,}/gu, "\n\n\n");
}

export function splitTranscript(transcript, maxChars = 24000) {
  if (!Number.isSafeInteger(maxChars) || maxChars < 1000) {
    throw new Error("Chunk size must be an integer of at least 1000 characters.");
  }
  if (transcript.length <= maxChars) return [transcript];
  const chunks = [];
  let cursor = 0;

  while (cursor < transcript.length) {
    let end = Math.min(cursor + maxChars, transcript.length);
    const boundary = transcript.lastIndexOf("\n## ", end);
    if (boundary > cursor + maxChars * 0.35) end = boundary;
    chunks.push(transcript.slice(cursor, end).trim());
    cursor = end;
  }

  return chunks.map((chunk, index) => {
    const n = index + 1;
    return `[raw transcript chunk ${n} of ${chunks.length}]\n\n${chunk}\n\n${
      n === chunks.length ? "[raw transcript complete]" : "Please acknowledge receipt only."
    }`;
  });
}

export async function writeBundle(input, outputRoot) {
  const capture = normalizeCapture(input);
  const bundleName = `${slugify(capture.title)}-${capture.id.slice(0, 8)}.tacket`;
  const bundlePath = path.join(outputRoot, bundleName);
  const attachmentsPath = path.join(bundlePath, "attachments");
  const targetsPath = path.join(bundlePath, "targets");
  await mkdir(attachmentsPath, { recursive: true });
  await mkdir(targetsPath, { recursive: true });

  const copiedMessages = await copyLocalAttachments(capture.messages, attachmentsPath);
  const bundle = { ...capture, messages: copiedMessages };
  const manifest = manifestFromCapture(bundle);
  const transcript = renderTranscript(bundle);
  const jsonl = copiedMessages.map((message) => JSON.stringify(message)).join("\n") + "\n";

  await writeFile(path.join(bundlePath, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  await writeFile(path.join(bundlePath, "messages.jsonl"), jsonl);
  await writeFile(path.join(bundlePath, "transcript.md"), transcript);
  await writeFile(path.join(targetsPath, "codex.md"), transcript);
  await writeFile(path.join(targetsPath, "claude-code.md"), transcript);

  return {
    bundlePath,
    manifest,
    transcriptPath: path.join(bundlePath, "transcript.md")
  };
}

export async function readBundle(bundlePath) {
  const manifest = JSON.parse(await readFile(path.join(bundlePath, "manifest.json"), "utf8"));
  const jsonl = await readFile(path.join(bundlePath, "messages.jsonl"), "utf8");
  const messages = jsonl
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line));
  return {
    ...manifest,
    messages
  };
}

export async function readTranscript(bundlePath) {
  return readFile(path.join(bundlePath, "transcript.md"), "utf8");
}

export function manifestFromCapture(capture) {
  const counts = { captured: 0, referenced: 0, unavailable: 0 };
  for (const message of capture.messages) {
    for (const part of message.content) {
      if (part.type === "attachment") counts[part.status] += 1;
    }
  }

  return {
    schemaVersion: capture.schemaVersion,
    id: capture.id,
    title: capture.title,
    source: capture.source,
    capturedAt: capture.capturedAt,
    messageCount: capture.messages.length,
    attachments: counts,
    warnings: warningsFromMessages(capture.messages)
  };
}

export function warningsFromMessages(messages) {
  const findings = new Map();
  const patterns = [
    ["openai_api_key", /sk-(?!ant-)[A-Za-z0-9_-]{20,}/gu],
    ["anthropic_api_key", /sk-ant-[A-Za-z0-9_-]{20,}/gu],
    ["aws_access_key_id", /AKIA[0-9A-Z]{16}/gu],
    ["github_token", /gh[pousr]_[A-Za-z0-9_]{20,}/gu],
    ["slack_token", /xox[baprs]-[A-Za-z0-9-]{20,}/gu],
    ["private_key", /-----BEGIN [A-Z ]*PRIVATE KEY-----/gu]
  ];

  for (const message of messages) {
    const text = message.content
      .filter((part) => part.type === "text" || part.type === "code")
      .map((part) => part.text)
      .join("\n");
    for (const [kind, pattern] of patterns) {
      pattern.lastIndex = 0;
      const matches = text.match(pattern);
      if (!matches) continue;
      const finding = findings.get(kind) ?? {
        type: "possible_secret",
        kind,
        count: 0,
        messageIds: []
      };
      finding.count += matches.length;
      if (!finding.messageIds.includes(message.id)) finding.messageIds.push(message.id);
      findings.set(kind, finding);
    }
  }

  return [...findings.values()];
}

function normalizeMessage(message, index, platform, sourceUrl) {
  const role = normalizeRole(message?.role);
  const content = normalizeContent(message?.content);
  return {
    id: String(message?.id ?? `${index + 1}-${stableId(JSON.stringify({ role, content }))}`),
    role,
    author: message?.author ? String(message.author) : undefined,
    createdAt: message?.createdAt ? String(message.createdAt) : undefined,
    content,
    source: {
      platform: message?.source?.platform ?? platform,
      url: message?.source?.url ?? sourceUrl,
      selector: message?.source?.selector
    }
  };
}

function normalizeRole(role) {
  if (["user", "assistant", "system", "tool"].includes(role)) return role;
  return "unknown";
}

function normalizeContent(content) {
  const parts = Array.isArray(content) ? content : [{ type: "text", text: String(content ?? "") }];
  return parts
    .map((part) => {
      if (part?.type === "code") {
        return {
          type: "code",
          text: String(part.text ?? ""),
          language: part.language ? String(part.language) : undefined
        };
      }
      if (part?.type === "attachment") {
        return {
          type: "attachment",
          status: ["captured", "referenced", "unavailable"].includes(part.status)
            ? part.status
            : "referenced",
          name: part.name ? String(part.name) : undefined,
          mimeType: part.mimeType ? String(part.mimeType) : undefined,
          url: part.url ? String(part.url) : undefined,
          path: part.path ? String(part.path) : undefined,
          dataUrl: part.dataUrl ? String(part.dataUrl) : undefined,
          alt: part.alt ? String(part.alt) : undefined
        };
      }
      return {
        type: "text",
        text: String(part?.text ?? "")
      };
    })
    .filter((part) => part.type === "attachment" || part.text.length > 0);
}

async function copyLocalAttachments(messages, attachmentsPath) {
  const result = [];
  let attachmentIndex = 0;

  for (const message of messages) {
    const content = [];
    for (const part of message.content) {
      if (part.type !== "attachment" || part.status !== "captured") {
        content.push(part);
        continue;
      }

      attachmentIndex += 1;
      const ext = extensionForAttachment(part);
      const name = `${String(attachmentIndex).padStart(3, "0")}-${slugify(part.name ?? "attachment")}${ext}`;
      const destination = path.join(attachmentsPath, name);
      if (part.dataUrl) {
        const data = bufferFromDataUrl(part.dataUrl);
        if (!data) {
          content.push(referencedAttachment(part));
          continue;
        }
        await writeFile(destination, data);
      } else if (part.path) {
        await copyFile(part.path, destination);
      } else {
        content.push(referencedAttachment(part));
        continue;
      }
      content.push({
        ...part,
        path: path.relative(path.dirname(attachmentsPath), destination),
        dataUrl: undefined
      });
    }
    result.push({ ...message, content });
  }

  return result;
}

function extensionForAttachment(part) {
  const fromName = path.extname(part.name ?? part.path ?? "");
  if (fromName) return fromName;
  if (part.mimeType === "image/png") return ".png";
  if (part.mimeType === "image/jpeg") return ".jpg";
  if (part.mimeType === "image/gif") return ".gif";
  if (part.mimeType === "image/webp") return ".webp";
  if (part.mimeType === "application/pdf") return ".pdf";
  return ".bin";
}

function bufferFromDataUrl(dataUrl) {
  const match = String(dataUrl).match(/^data:([^;,]+)?(;base64)?,(.*)$/u);
  if (!match) return null;
  const [, , base64, data] = match;
  try {
    return Buffer.from(decodeURIComponent(data), base64 ? "base64" : "utf8");
  } catch {
    return null;
  }
}

function referencedAttachment(part) {
  return {
    ...part,
    status: "referenced",
    dataUrl: undefined
  };
}

function renderAttachment(part) {
  const label = part.name ?? part.alt ?? "attachment";
  const target = part.path ?? part.url ?? "unavailable";
  return `[attachment:${part.status}] ${label} -> ${target}`;
}

function formatRole(role, author) {
  const name = role === "user" ? "User" : role === "assistant" ? "Assistant" : role;
  return author ? `${name} (${author})` : name;
}

function slugify(value) {
  const slug = String(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/gu, "-")
    .replace(/^-|-$/gu, "")
    .slice(0, 72);
  return slug || "thread";
}

function sanitizeTitle(value) {
  return String(value).replace(/\s+/gu, " ").trim().slice(0, 160) || "Untitled Thread";
}

function stableId(value) {
  return createHash("sha256").update(value).digest("hex");
}

function safeUrl(value) {
  try {
    return new URL(value);
  } catch {
    return null;
  }
}

function titleFromUrl(value) {
  const url = safeUrl(value);
  if (!url) return null;
  return url.hostname.replace(/^www\./u, "");
}

export function newCaptureId() {
  return randomUUID();
}
