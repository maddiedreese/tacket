import { createHash } from "node:crypto";
import { access, lstat, mkdir, mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import { spawn } from "node:child_process";
import os from "node:os";
import path from "node:path";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const release = JSON.parse(await readFile(path.join(root, "release.json"), "utf8"));
const dist = path.join(root, "dist");
const app = path.join(dist, "Tacket.app");
const dmg = path.join(dist, "Tacket.dmg");
const extensionZip = path.join(dist, "tacket-chrome-extension.zip");
const checksums = path.join(dist, "SHA256SUMS");

await assertFile(path.join(app, "Contents/Info.plist"));
await assertExecutable(path.join(app, "Contents/MacOS/Tacket"));
await assertExecutable(path.join(app, "Contents/MacOS/TacketNativeHost"));
await assertFile(path.join(app, "Contents/Resources/Tacket.icns"));
await assertFile(path.join(app, "Contents/Resources/chrome-extension/manifest.json"));
await assertFile(dmg);
await assertFile(extensionZip);
await assertFile(checksums);
await assertFile(path.join(root, "apps/mac/TacketApp/Tacket.entitlements"));
await assertPngDimensions(path.join(root, "store-assets/chrome-web-store/small-promo-440x280.png"), 440, 280);
await assertPngDimensions(path.join(root, "store-assets/chrome-web-store/marquee-promo-1400x560.png"), 1400, 560);
for (const screenshot of [
  "01-capture-popup-1280x800.png",
  "02-local-bundle-1280x800.png",
  "03-local-library-1280x800.png"
]) {
  await assertPngDimensions(path.join(root, "store-assets/chrome-web-store/screenshots", screenshot), 1280, 800);
}

await verifyInfoPlist(path.join(app, "Contents/Info.plist"));
await verifyMacSigningInputs();
await verifyMacConnectorSource();
await verifyExtensionManifest(path.join(root, "apps/chrome-extension/manifest.json"));
await verifyExtensionBackground(path.join(root, "apps/chrome-extension/src/background.js"));
await verifyBundledExtension();
await verifyPackagedNativeMessagingManifest();
await verifyWebsite();
await verifyExtensionZip();
await run("hdiutil", ["verify", dmg]);
await verifyDmgContents();
await verifyChecksums();
await run("node", ["scripts/smoke-swift-host.mjs", "dist/Tacket.app/Contents/MacOS/TacketNativeHost"], { cwd: root });

console.log("Release artifact checks passed.");

async function verifyInfoPlist(plistPath) {
  const text = await readFile(plistPath, "utf8");
  for (const value of [
    "<key>CFBundleExecutable</key>",
    "<string>Tacket</string>",
    "<key>CFBundleIdentifier</key>",
    `<string>${release.bundleIdentifier}</string>`,
    "<key>CFBundleIconFile</key>"
  ]) {
    if (!text.includes(value)) throw new Error(`Info.plist missing ${value}`);
  }
  if (!text.includes("<key>NSAppleEventsUsageDescription</key>")) {
    throw new Error("Info.plist missing NSAppleEventsUsageDescription.");
  }
  if (!text.includes("open Terminal and paste the saved conversation")) {
    throw new Error("Info.plist Apple Events purpose string is missing or too vague.");
  }
  if (!text.includes("<key>NSAccessibilityUsageDescription</key>")) {
    throw new Error("Info.plist missing NSAccessibilityUsageDescription.");
  }
  if (!text.includes("scroll and read the desktop app chat")) {
    throw new Error("Info.plist Accessibility purpose string is missing or too vague.");
  }
  if (!text.includes("<key>NSScreenCaptureUsageDescription</key>")) {
    throw new Error("Info.plist missing NSScreenCaptureUsageDescription.");
  }
  if (!text.includes("on-device OCR")) {
    throw new Error("Info.plist Screen Capture purpose string is missing or too vague.");
  }
}

async function verifyMacSigningInputs() {
  const entitlements = await readFile(path.join(root, "apps/mac/TacketApp/Tacket.entitlements"), "utf8");
  if (!entitlements.includes("com.apple.security.automation.apple-events")) {
    throw new Error("Tacket.entitlements must include Apple Events automation for signed transfer builds.");
  }

  const signScript = await readFile(path.join(root, "scripts/sign-mac-app.sh"), "utf8");
  for (const phrase of ["--options runtime", "--entitlements", "Tacket.entitlements"]) {
    if (!signScript.includes(phrase)) throw new Error(`Signing script missing ${phrase}`);
  }
}

async function verifyMacConnectorSource() {
  const text = await readFile(path.join(root, "apps/mac/TacketApp/Sources/TacketApp/TacketApp.swift"), "utf8");
  for (const phrase of [
    `"name": "${release.nativeHostName}"`,
    `"path": nativeHostURL.path`,
    `"type": "stdio"`,
    `"allowed_origins": ["chrome-extension://\\(extensionId)/"]`,
    `appendingPathComponent("${release.nativeHostName}.json")`
  ]) {
    if (!text.includes(phrase)) throw new Error(`Mac connector source missing native messaging manifest contract: ${phrase}`);
  }
}

async function verifyExtensionManifest(manifestPath) {
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  if (manifest.name !== "Tacket") throw new Error("Extension manifest name must be Tacket.");
  if (manifest.version !== release.version) throw new Error("Extension manifest version does not match release.json.");
  if (!manifest.action?.default_popup) throw new Error("Extension popup missing.");
  if (!manifest.action?.default_icon?.["128"]) throw new Error("Extension action icons missing.");
  if (!manifest.icons?.["128"]) throw new Error("Extension icons missing.");

  const hosts = new Set(manifest.host_permissions ?? []);
  for (const host of ["https://chatgpt.com/*", "https://chat.openai.com/*", "https://claude.ai/*", "https://gemini.google.com/*"]) {
    if (!hosts.has(host)) throw new Error(`Extension missing host permission ${host}`);
  }
  if ([...hosts].some((host) => host.startsWith("file://"))) {
    throw new Error("Production extension manifest must not include file:// permissions.");
  }
}

async function verifyExtensionBackground(backgroundPath) {
  const text = await readFile(backgroundPath, "utf8");
  if (!text.includes(`HOST_NAME = "${release.nativeHostName}"`)) {
    throw new Error("Extension background native host name does not match release.json.");
  }
}

async function verifyExtensionPopup(popupPath) {
  const text = await readFile(popupPath, "utf8");
  if (!text.includes("manifestAllowsFileUrls")) {
    throw new Error("Extension popup must gate file URL capture by manifest permissions.");
  }
}

async function verifyBundledExtension() {
  const bundled = path.join(app, "Contents/Resources/chrome-extension");
  for (const entry of [
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
    await assertFile(path.join(bundled, entry));
  }

  for (const forbidden of [
    "manifest.dev.json",
    "test/capture-fixtures.test.js"
  ]) {
    try {
      await access(path.join(bundled, forbidden), constants.R_OK);
      throw new Error(`Bundled extension includes development-only file: ${forbidden}`);
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
  }

  await verifyExtensionManifest(path.join(bundled, "manifest.json"));
  await verifyExtensionBackground(path.join(bundled, "src/background.js"));
  await verifyExtensionPopup(path.join(bundled, "src/popup.js"));
}

async function verifyPackagedNativeMessagingManifest() {
  const extensionId = "abcdefghijklmnopabcdefghijklmnop";
  const hostPath = path.join(app, "Contents/MacOS/TacketNativeHost");
  await assertExecutable(hostPath);

  const tmpHome = await mkdtemp(path.join(os.tmpdir(), "tacket-native-manifest-"));
  try {
    const manifestDir = path.join(tmpHome, "Library/Application Support/Google/Chrome/NativeMessagingHosts");
    const manifestPath = path.join(manifestDir, `${release.nativeHostName}.json`);
    await mkdir(manifestDir, { recursive: true });
    const manifest = {
      name: release.nativeHostName,
      description: "Tacket local capture host",
      path: hostPath,
      type: "stdio",
      allowed_origins: [`chrome-extension://${extensionId}/`]
    };
    await writeFile(manifestPath, JSON.stringify(manifest, null, 2) + "\n");

    const actual = JSON.parse(await readFile(manifestPath, "utf8"));
    if (actual.name !== release.nativeHostName) throw new Error("Packaged native messaging manifest name mismatch.");
    if (actual.path !== hostPath) throw new Error("Packaged native messaging manifest host path mismatch.");
    if (actual.type !== "stdio") throw new Error("Packaged native messaging manifest type must be stdio.");
    if (!actual.allowed_origins?.includes(`chrome-extension://${extensionId}/`)) {
      throw new Error("Packaged native messaging manifest missing Chrome extension origin.");
    }
    await assertExecutable(actual.path);
  } finally {
    await rm(tmpHome, { recursive: true, force: true });
  }
}

async function verifyWebsite() {
  const index = await readFile(path.join(root, "website/index.html"), "utf8");
  const privacy = await readFile(path.join(root, "website/privacy.html"), "utf8");
  for (const html of [index, privacy]) {
    if (!html.includes("./assets/favicon.png")) throw new Error("Website page missing favicon.");
    if (!html.includes("github.com/maddiedreese/tacket")) throw new Error("Website page missing GitHub link.");
  }
  if (!privacy.includes("private vulnerability reporting")) {
    throw new Error("Privacy page must direct security vulnerabilities to private reporting.");
  }
  await assertFile(path.join(root, "website/assets/favicon.png"));
  await assertFile(path.join(root, "website/assets/icon-180.png"));
}

async function verifyExtensionZip() {
  const listing = await run("unzip", ["-l", extensionZip]);
  for (const entry of [
    "manifest.json",
    "src/popup.js",
    "src/background.js",
    "src/adapters/capture.js",
    "icons/tacket-16.png",
    "icons/tacket-32.png",
    "icons/tacket-48.png",
    "icons/tacket-128.png"
  ]) {
    if (!listing.includes(entry)) throw new Error(`Extension zip missing ${entry}`);
  }

  const tmp = await mkdtemp(path.join(os.tmpdir(), "tacket-extension-"));
  try {
    await run("unzip", ["-q", extensionZip, "-d", tmp]);
    await verifyExtensionManifest(path.join(tmp, "manifest.json"));
    await verifyExtensionBackground(path.join(tmp, "src/background.js"));
    await verifyExtensionPopup(path.join(tmp, "src/popup.js"));
  } finally {
    await rm(tmp, { recursive: true, force: true });
  }
}

async function verifyDmgContents() {
  const mountPoint = await mkdtemp(path.join(os.tmpdir(), "tacket-dmg-"));
  try {
    await run("hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mountPoint, dmg]);
    const mountedApp = path.join(mountPoint, "Tacket.app");
    const applicationsLink = path.join(mountPoint, "Applications");
    const appInfo = await stat(mountedApp);
    if (!appInfo.isDirectory()) throw new Error("DMG missing Tacket.app.");
    const linkInfo = await lstat(applicationsLink);
    if (!linkInfo.isSymbolicLink()) throw new Error("DMG missing Applications symlink.");
  } finally {
    await run("hdiutil", ["detach", mountPoint]).catch(() => {});
    await rm(mountPoint, { recursive: true, force: true });
  }
}

async function verifyChecksums() {
  const expected = new Map();
  const text = await readFile(checksums, "utf8");
  for (const line of text.split("\n").filter(Boolean)) {
    const match = line.match(/^([a-f0-9]{64})  (.+)$/u);
    if (!match) throw new Error(`Invalid SHA256SUMS line: ${line}`);
    expected.set(match[2], match[1]);
  }

  for (const artifact of ["Tacket.dmg", "tacket-chrome-extension.zip"]) {
    const bytes = await readFile(path.join(dist, artifact));
    const actual = createHash("sha256").update(bytes).digest("hex");
    if (expected.get(artifact) !== actual) {
      throw new Error(`SHA256SUMS hash for ${artifact} is missing or stale.`);
    }
  }
}

async function assertFile(file) {
  await access(file, constants.R_OK);
  const info = await stat(file);
  if (!info.isFile()) throw new Error(`Expected file: ${file}`);
  if (info.size <= 0) throw new Error(`File is empty: ${file}`);
}

async function assertExecutable(file) {
  await access(file, constants.R_OK | constants.X_OK);
  const info = await stat(file);
  if (!info.isFile()) throw new Error(`Expected executable file: ${file}`);
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

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: options.cwd ?? root,
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
