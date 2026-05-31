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

await assertFile(path.join(bundlePath, "transcript.md"));
await assertFile(path.join(bundlePath, "targets/codex.md"));
await assertFile(path.join(bundlePath, "targets/claude-code.md"));

console.log(`Validated ${bundlePath}`);

function assertValid(label, validate, value) {
  if (validate(value)) return;
  const detail = ajv.errorsText(validate.errors, { separator: "\n" });
  throw new Error(`${label} failed schema validation:\n${detail}`);
}

async function assertFile(file) {
  const info = await stat(file);
  if (!info.isFile()) throw new Error(`Expected file: ${file}`);
  if (info.size === 0) throw new Error(`File is empty: ${file}`);
}
