import Ajv2020 from "ajv/dist/2020.js";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";

const bundlePath = process.argv[2];
if (!bundlePath) {
  console.error("Usage: node scripts/validate-bundle.mjs <bundle.tacket>");
  process.exit(1);
}

const manifestSchema = JSON.parse(await readFile("schemas/manifest.schema.json", "utf8"));
const messageSchema = JSON.parse(await readFile("schemas/message.schema.json", "utf8"));

const ajv = new Ajv2020({ allErrors: true });
const validateManifest = ajv.compile(manifestSchema);
const validateMessage = ajv.compile(messageSchema);

const manifest = JSON.parse(await readFile(path.join(bundlePath, "manifest.json"), "utf8"));
const messagesJsonl = await readFile(path.join(bundlePath, "messages.jsonl"), "utf8");
const messages = messagesJsonl
  .split("\n")
  .filter(Boolean)
  .map((line) => JSON.parse(line));

assertValid("manifest.json", validateManifest, manifest);
if (manifest.messageCount !== messages.length) {
  throw new Error(`manifest.json messageCount ${manifest.messageCount} does not match messages.jsonl length ${messages.length}.`);
}

for (const [index, message] of messages.entries()) {
  assertValid(`messages.jsonl line ${index + 1}`, validateMessage, message);
}

await assertAttachmentCounts(manifest, messages);
await assertCapturedAttachments(messages);
await assertTransferTargets();

console.log(`Validated ${bundlePath}`);

function assertValid(label, validate, value) {
  if (validate(value)) return;
  const detail = ajv.errorsText(validate.errors, { separator: "\n" });
  throw new Error(`${label} failed schema validation:\n${detail}`);
}

async function assertFile(file) {
  let info;
  try {
    info = await stat(file);
  } catch {
    throw new Error(`Expected file: ${file}`);
  }
  if (!info.isFile()) throw new Error(`Expected file: ${file}`);
  if (info.size === 0) throw new Error(`File is empty: ${file}`);
}

async function assertTransferTargets() {
  const transcriptPath = path.join(bundlePath, "transcript.md");
  const transcript = await assertTextFile(transcriptPath);
  for (const target of ["codex.md", "claude-code.md"]) {
    const targetPath = path.join(bundlePath, "targets", target);
    const text = await assertTextFile(targetPath);
    if (text !== transcript) throw new Error(`targets/${target} must match transcript.md exactly.`);
  }
}

async function assertTextFile(file) {
  await assertFile(file);
  return readFile(file, "utf8");
}

async function assertAttachmentCounts(manifestValue, messagesValue) {
  const expected = { captured: 0, referenced: 0, unavailable: 0 };
  for (const message of messagesValue) {
    for (const part of message.content ?? []) {
      if (part.type === "attachment") expected[part.status] += 1;
    }
  }
  for (const [key, value] of Object.entries(expected)) {
    if ((manifestValue.attachments?.[key] ?? 0) !== value) {
      throw new Error(`manifest.json attachments.${key} ${manifestValue.attachments?.[key] ?? "missing"} does not match messages.jsonl ${value}.`);
    }
  }
}

async function assertCapturedAttachments(messagesValue) {
  for (const message of messagesValue) {
    for (const part of message.content ?? []) {
      if (part.type !== "attachment" || part.status !== "captured") continue;
      if (!part.path) throw new Error(`Captured attachment in message ${message.id} is missing path.`);
      if (path.isAbsolute(part.path) || part.path.split(/[\\/]/u).includes("..")) {
        throw new Error(`Captured attachment in message ${message.id} has unsafe path: ${part.path}`);
      }
      await assertFile(path.join(bundlePath, part.path));
    }
  }
}
