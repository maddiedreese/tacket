import { access, copyFile, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import path from "node:path";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const outputDir = path.join(root, "dist", "chrome-web-store");
const extensionZip = path.join(root, "dist", "tacket-chrome-extension.zip");
const storeAssetDir = path.join(root, "store-assets", "chrome-web-store");
const screenshotDir = path.join(storeAssetDir, "screenshots");

const assets = [
  {
    source: path.join(root, "apps/chrome-extension/icons/tacket-128.png"),
    target: "icon-128.png",
    width: 128,
    height: 128
  },
  {
    source: path.join(storeAssetDir, "small-promo-440x280.png"),
    target: "small-promo-440x280.png",
    width: 440,
    height: 280
  },
  {
    source: path.join(screenshotDir, "01-capture-popup-1280x800.png"),
    target: "screenshots/01-capture-popup-1280x800.png",
    width: 1280,
    height: 800
  },
  {
    source: path.join(screenshotDir, "02-local-bundle-1280x800.png"),
    target: "screenshots/02-local-bundle-1280x800.png",
    width: 1280,
    height: 800
  },
  {
    source: path.join(screenshotDir, "03-local-library-1280x800.png"),
    target: "screenshots/03-local-library-1280x800.png",
    width: 1280,
    height: 800
  }
];

await run("npm", ["run", "generate:icons"]);
await run("npm", ["run", "store:screenshots"]);
await run("bash", ["scripts/package-extension.sh"]);
await refreshReleaseChecksumsIfPresent();
await assertExtensionZip(extensionZip);

await rm(outputDir, { recursive: true, force: true });
await mkdir(path.join(outputDir, "screenshots"), { recursive: true });
await copyFile(extensionZip, path.join(outputDir, "tacket-chrome-extension.zip"));
await copyFile(path.join(root, "docs", "CHROME_WEB_STORE.md"), path.join(outputDir, "listing.md"));
await copyFile(path.join(root, "docs", "PRIVACY.md"), path.join(outputDir, "privacy.md"));

for (const asset of assets) {
  await assertPngDimensions(asset.source, asset.width, asset.height);
  await copyFile(asset.source, path.join(outputDir, asset.target));
}

await writeFile(path.join(outputDir, "README.md"), readme(), "utf8");
await run("npm", ["run", "store:verify"]);
console.log(outputDir);

function readme() {
  return `# Tacket Chrome Web Store Submission

Upload \`tacket-chrome-extension.zip\` as the extension package.

Use these generated assets:

- \`icon-128.png\`
- \`small-promo-440x280.png\`
- \`screenshots/01-capture-popup-1280x800.png\`
- \`screenshots/02-local-bundle-1280x800.png\`
- \`screenshots/03-local-library-1280x800.png\`

Use the generated listing and privacy copy while filling out the store form:

- \`listing.md\`
- \`privacy.md\`

Reference docs:

- \`docs/CHROME_WEB_STORE.md\`
- \`docs/STORE_ASSETS.md\`

Review every image before upload. The generated screenshots are synthetic and should not contain private chat text, private code, tokens, local usernames, or personal file names.
`;
}

async function refreshReleaseChecksumsIfPresent() {
  try {
    await access(path.join(root, "dist", "Tacket.dmg"));
    await access(extensionZip);
  } catch {
    return;
  }
  await run("npm", ["run", "generate:checksums"]);
}

async function assertExtensionZip(file) {
  const listing = await run("unzip", ["-l", file]);
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
  for (const forbidden of ["manifest.dev.json", "test/", ".DS_Store"]) {
    if (listing.includes(forbidden)) throw new Error(`Extension zip includes forbidden entry ${forbidden}`);
  }
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
      if (code === 0) resolve(Buffer.concat(stdout).toString("utf8"));
      else reject(new Error(`${command} ${args.join(" ")} failed with ${code}\n${Buffer.concat(stderr).toString("utf8")}`));
    });
  });
}
