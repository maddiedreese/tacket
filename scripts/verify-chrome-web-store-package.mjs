import { createHash } from "node:crypto";
import { access, mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { constants } from "node:fs";
import { spawn } from "node:child_process";
import os from "node:os";
import path from "node:path";

const root = path.resolve(process.env.TACKET_RELEASE_ROOT ?? new URL("..", import.meta.url).pathname);
const release = JSON.parse(await readFile(path.join(root, "release.json"), "utf8"));
const storeDir = path.join(root, "dist", "chrome-web-store");
const extensionZip = path.join(storeDir, "tacket-chrome-extension.zip");
const releaseExtensionZip = path.join(root, "dist", "tacket-chrome-extension.zip");

for (const file of [
  "tacket-chrome-extension.zip",
  "icon-128.png",
  "small-promo-440x280.png",
  "listing.md",
  "privacy.md",
  "README.md",
  "screenshots/01-capture-popup-1280x800.png",
  "screenshots/02-local-bundle-1280x800.png",
  "screenshots/03-transfer-targets-1280x800.png"
]) {
  await assertFile(path.join(storeDir, file));
}

await assertPngDimensions(path.join(storeDir, "icon-128.png"), 128, 128);
await assertPngDimensions(path.join(storeDir, "small-promo-440x280.png"), 440, 280);
for (const screenshot of [
  "01-capture-popup-1280x800.png",
  "02-local-bundle-1280x800.png",
  "03-transfer-targets-1280x800.png"
]) {
  await assertPngDimensions(path.join(storeDir, "screenshots", screenshot), 1280, 800);
}

await verifyListingCopy();
await verifyPrivacyCopy();
await verifyReadme();
await verifyExtensionZip();
await verifyMatchesReleaseZip();

console.log(`Chrome Web Store package checks passed for ${storeDir}`);

async function verifyListingCopy() {
  const listing = await readFile(path.join(storeDir, "listing.md"), "utf8");
  for (const phrase of [
    "Tacket",
    "Save AI chats locally and search them later.",
    "Single Purpose",
    "Permission Justification",
    "`activeTab`",
    "`scripting`",
    "`nativeMessaging`",
    "Host permissions",
    "https://chatgpt.com/*",
    "https://chat.openai.com/*",
    "https://claude.ai/*",
    "https://gemini.google.com/*",
    "does not collect, sell, transmit, or remotely process user data",
    "npm run store:verify-id"
  ]) {
    if (!listing.includes(phrase)) throw new Error(`Chrome Web Store listing missing: ${phrase}`);
  }
  assertNoPrivateExampleText("listing.md", listing);
}

async function verifyPrivacyCopy() {
  const privacy = await readFile(path.join(storeDir, "privacy.md"), "utf8");
  for (const phrase of [
    "local-first",
    "No backend",
    "No analytics",
    "No model calls",
    "Saved chat content is stored locally",
    "saved conversation is sent to the local Tacket app"
  ]) {
    if (!privacy.includes(phrase)) throw new Error(`Chrome Web Store privacy copy missing: ${phrase}`);
  }
  assertNoPrivateExampleText("privacy.md", privacy);
}

async function verifyReadme() {
  const readme = await readFile(path.join(storeDir, "README.md"), "utf8");
  for (const phrase of [
    "Upload `tacket-chrome-extension.zip`",
    "Use these generated assets",
    "Review every image before upload",
    "should not contain private chat text"
  ]) {
    if (!readme.includes(phrase)) throw new Error(`Chrome Web Store upload README missing: ${phrase}`);
  }
}

async function verifyMatchesReleaseZip() {
  await assertFile(releaseExtensionZip);
  const storeHash = await sha256(extensionZip);
  const releaseHash = await sha256(releaseExtensionZip);
  if (storeHash !== releaseHash) {
    throw new Error("Chrome Web Store extension zip does not match dist/tacket-chrome-extension.zip. Run `npm run store:prepare` again.");
  }
}

async function verifyExtensionZip() {
  const listing = await run("unzip", ["-l", extensionZip]);
  for (const required of [
    "manifest.json",
    "src/popup.html",
    "src/popup.css",
    "src/popup.js",
    "src/background.js",
    "src/adapters/capture.js",
    "icons/tacket-16.png",
    "icons/tacket-32.png",
    "icons/tacket-48.png",
    "icons/tacket-128.png"
  ]) {
    if (!listing.includes(required)) throw new Error(`Extension zip missing ${required}`);
  }
  for (const forbidden of ["manifest.dev.json", "test/", ".DS_Store", "__MACOSX"]) {
    if (listing.includes(forbidden)) throw new Error(`Extension zip includes forbidden entry ${forbidden}`);
  }

  const tmp = await mkdtemp(path.join(os.tmpdir(), "tacket-store-extension-"));
  try {
    await run("unzip", ["-q", extensionZip, "-d", tmp]);
    const manifest = JSON.parse(await readFile(path.join(tmp, "manifest.json"), "utf8"));
    if (manifest.name !== "Tacket") throw new Error("Extension manifest name must be Tacket.");
    if (manifest.version !== release.version) throw new Error("Extension manifest version must match release.json.");
    if (manifest.manifest_version !== 3) throw new Error("Extension must use Manifest V3.");
    assertExactSet("Extension permissions", manifest.permissions ?? [], ["activeTab", "scripting", "nativeMessaging"]);
    assertExactSet("Extension host permissions", manifest.host_permissions ?? [], [
      "https://chatgpt.com/*",
      "https://chat.openai.com/*",
      "https://claude.ai/*",
      "https://gemini.google.com/*"
    ]);
    if ([...(manifest.host_permissions ?? [])].some((host) => host.startsWith("file://"))) {
      throw new Error("Production extension manifest must not include file:// host permissions.");
    }
  } finally {
    await rm(tmp, { recursive: true, force: true });
  }
}

async function sha256(file) {
  return createHash("sha256").update(await readFile(file)).digest("hex");
}

function assertExactSet(label, actual, expected) {
  const actualSet = new Set(actual);
  const expectedSet = new Set(expected);
  for (const item of expectedSet) {
    if (!actualSet.has(item)) throw new Error(`${label} missing ${item}`);
  }
  for (const item of actualSet) {
    if (!expectedSet.has(item)) throw new Error(`${label} includes unexpected ${item}`);
  }
}

function assertNoPrivateExampleText(label, text) {
  const patterns = [
    ["OpenAI API key", /sk-(?!ant-)[A-Za-z0-9_-]{20,}/u],
    ["Anthropic API key", /sk-ant-[A-Za-z0-9_-]{20,}/u],
    ["AWS access key id", /AKIA[0-9A-Z]{16}/u],
    ["GitHub token", /gh[pousr]_[A-Za-z0-9_]{20,}/u],
    ["Slack token", /xox[baprs]-[A-Za-z0-9-]{20,}/u],
    ["private key block", /-----BEGIN [A-Z ]*PRIVATE KEY-----/u]
  ];
  for (const [name, pattern] of patterns) {
    if (pattern.test(text)) throw new Error(`${label} appears to contain private secret-like text: ${name}`);
  }
}

async function assertFile(file) {
  await access(file, constants.R_OK);
  const info = await stat(file);
  if (!info.isFile()) throw new Error(`Expected file: ${file}`);
  if (info.size <= 0) throw new Error(`File is empty: ${file}`);
}

async function assertPngDimensions(file, width, height) {
  const bytes = await readFile(file);
  const signature = bytes.subarray(0, 8).toString("hex");
  if (signature !== "89504e470d0a1a0a") throw new Error(`Expected PNG file: ${file}`);
  const actualWidth = bytes.readUInt32BE(16);
  const actualHeight = bytes.readUInt32BE(20);
  if (actualWidth !== width || actualHeight !== height) {
    throw new Error(`Expected ${file} to be ${width}x${height}, found ${actualWidth}x${actualHeight}.`);
  }
}

function run(command, args) {
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
      const out = Buffer.concat(stdout).toString("utf8");
      const err = Buffer.concat(stderr).toString("utf8");
      if (code === 0) resolve(out);
      else reject(new Error(`${command} ${args.join(" ")} failed with ${code}\n${out}\n${err}`));
    });
  });
}
