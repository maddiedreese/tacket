import { access, readFile } from "node:fs/promises";
import path from "node:path";

const requiredFiles = [
  "LICENSE",
  "CHANGELOG.md",
  "SECURITY.md",
  "CONTRIBUTING.md",
  ".editorconfig",
  ".gitattributes",
  ".gitignore",
  ".github/ISSUE_TEMPLATE/bug_report.yml",
  ".github/ISSUE_TEMPLATE/feature_request.yml",
  ".github/ISSUE_TEMPLATE/config.yml",
  ".github/dependabot.yml",
  ".github/pull_request_template.md",
  ".github/workflows/ci.yml",
  ".github/workflows/pages.yml",
  ".github/workflows/release.yml",
  "qa/live-capture/.gitkeep",
  "release.json",
  "README.md",
  "assets/icon.svg",
  "apps/chrome-extension/manifest.json",
  "apps/chrome-extension/manifest.dev.json",
  "apps/chrome-extension/icons/tacket-16.png",
  "apps/chrome-extension/icons/tacket-32.png",
  "apps/chrome-extension/icons/tacket-48.png",
  "apps/chrome-extension/icons/tacket-128.png",
  "apps/chrome-extension/src/adapters/capture.js",
  "examples/capture-demo/index.html",
  "website/index.html",
  "website/privacy.html",
  "website/styles.css",
  "website/assets/favicon.png",
  "website/assets/icon-180.png",
  "apps/native-host/bin/tacket-native-host.js",
  "apps/cli/bin/tacket.js",
  "apps/mac/TacketApp/Sources/TacketApp/TacketApp.swift",
  "apps/mac/TacketApp/Sources/TacketNativeHost/main.swift",
  "apps/mac/TacketApp/Tacket.entitlements",
  "packages/thread-format/src/index.js",
  "schemas/manifest.schema.json",
  "schemas/message.schema.json",
  "store-assets/chrome-web-store/small-promo-440x280.png",
  "store-assets/chrome-web-store/screenshots/01-capture-popup-1280x800.png",
  "store-assets/chrome-web-store/screenshots/02-local-bundle-1280x800.png",
  "store-assets/chrome-web-store/screenshots/03-transfer-targets-1280x800.png",
  "docs/PRIVACY.md",
  "docs/CHROME_WEB_STORE.md",
  "docs/RELEASE.md",
  "docs/ROADMAP.md",
  "docs/STORE_ASSETS.md",
  "docs/TESTING.md",
  "docs/TROUBLESHOOTING.md",
  "scripts/package-mac-dev.sh",
  "scripts/package-dmg.sh",
  "scripts/sign-mac-app.sh",
  "scripts/notarize-dmg.sh",
  "scripts/package-extension.sh",
  "scripts/package-release.sh",
  "scripts/generate-icons.mjs",
  "scripts/generate-checksums.mjs",
  "scripts/check-versions.mjs",
  "scripts/validate-bundle.mjs",
  "scripts/verify-release.mjs",
  "scripts/smoke-swift-host.mjs",
  "scripts/new-live-qa.mjs",
  "scripts/check-release-readiness.mjs",
  "scripts/generate-store-screenshots.mjs"
];

for (const file of requiredFiles) {
  await access(path.resolve(file));
}

const manifest = JSON.parse(await readFile("apps/chrome-extension/manifest.json", "utf8"));
const hosts = new Set(manifest.host_permissions ?? []);
for (const host of ["https://chatgpt.com/*", "https://claude.ai/*", "https://gemini.google.com/*"]) {
  if (!hosts.has(host)) throw new Error(`Missing extension host permission: ${host}`);
}

const popup = await readFile("apps/chrome-extension/src/popup.js", "utf8");
for (const host of ["chatgpt.com", "chat.openai.com", "claude.ai", "gemini.google.com"]) {
  if (!popup.includes(host)) throw new Error(`Popup must block capture outside supported host: ${host}`);
}
if (!popup.includes("isSupportedChatUrl")) {
  throw new Error("Popup must validate the active tab URL before injecting capture code.");
}
if (!popup.includes("manifestAllowsFileUrls")) {
  throw new Error("Popup file URL support must be gated by manifest permissions.");
}

const cli = await readFile("apps/cli/bin/tacket.js", "utf8");
for (const command of ["install-native-host", "status-native-host", "uninstall-native-host"]) {
  if (!cli.includes(command)) throw new Error(`CLI missing ${command}`);
}
if (!cli.includes("validateChromeExtensionId")) {
  throw new Error("CLI must validate Chrome extension IDs before writing native host manifests.");
}

const macApp = await readFile("apps/mac/TacketApp/Sources/TacketApp/TacketApp.swift", "utf8");
if (!macApp.includes("isValidChromeExtensionId")) {
  throw new Error("Mac app must validate Chrome extension IDs before writing native host manifests.");
}

const entitlements = await readFile("apps/mac/TacketApp/Tacket.entitlements", "utf8");
if (!entitlements.includes("com.apple.security.automation.apple-events")) {
  throw new Error("Mac app entitlements must include Apple Events for Terminal transfer automation.");
}

const signScript = await readFile("scripts/sign-mac-app.sh", "utf8");
for (const phrase of ["--options runtime", "--entitlements", "Tacket.entitlements"]) {
  if (!signScript.includes(phrase)) throw new Error(`Signing script missing: ${phrase}`);
}

const issueConfig = await readFile(".github/ISSUE_TEMPLATE/config.yml", "utf8");
if (!issueConfig.includes("/security/advisories/new")) {
  throw new Error("Issue template config must direct vulnerabilities to private security advisories.");
}

const dependabot = await readFile(".github/dependabot.yml", "utf8");
for (const phrase of ["package-ecosystem: npm", "package-ecosystem: github-actions", "interval: weekly"]) {
  if (!dependabot.includes(phrase)) throw new Error(`Dependabot config missing: ${phrase}`);
}

const security = await readFile("SECURITY.md", "utf8");
for (const phrase of ["Dependabot alerts", "automated security fixes", ".github/dependabot.yml"]) {
  if (!security.includes(phrase)) throw new Error(`Security policy missing dependency alert note: ${phrase}`);
}
if (!security.includes("GitHub private vulnerability reporting is enabled")) {
  throw new Error("Security policy must state that private vulnerability reporting is enabled.");
}

const troubleshooting = await readFile("docs/TROUBLESHOOTING.md", "utf8");
for (const phrase of [
  "Native Host Not Found",
  "Captures Go to the Wrong Folder",
  "Terminal Paste Does Not Happen",
  "Uninstall Tacket",
  "dev.tacket.host.json",
  "Tacket Captures"
]) {
  if (!troubleshooting.includes(phrase)) throw new Error(`Troubleshooting guide missing: ${phrase}`);
}

const changelog = await readFile("CHANGELOG.md", "utf8");
for (const phrase of ["0.1.0", "Chrome extension capture", "Raw transcript transfer"]) {
  if (!changelog.includes(phrase)) throw new Error(`Changelog missing: ${phrase}`);
}

const readme = await readFile("README.md", "utf8");
if (!readme.includes("docs/ROADMAP.md")) {
  throw new Error("README.md must link to docs/ROADMAP.md.");
}

const roadmap = await readFile("docs/ROADMAP.md", "utf8");
for (const phrase of ["milestone/1", "live capture validation", "Developer ID signing", "Chrome Web Store"]) {
  if (!roadmap.includes(phrase)) throw new Error(`Roadmap missing: ${phrase}`);
}

const rootPackage = JSON.parse(await readFile("package.json", "utf8"));
if (rootPackage.scripts?.["qa:live"] !== "node scripts/new-live-qa.mjs") {
  throw new Error("package.json must expose npm run qa:live for live provider QA reports.");
}
if (rootPackage.scripts?.["release:readiness"] !== "node scripts/check-release-readiness.mjs") {
  throw new Error("package.json must expose npm run release:readiness.");
}
if (rootPackage.scripts?.["store:screenshots"] !== "node scripts/generate-store-screenshots.mjs") {
  throw new Error("package.json must expose npm run store:screenshots.");
}

const liveQa = await readFile("scripts/new-live-qa.mjs", "utf8");
for (const phrase of ["Do not paste private transcript text", "ChatGPT", "Claude", "Gemini", "Release Decision"]) {
  if (!liveQa.includes(phrase)) throw new Error(`Live QA report template missing: ${phrase}`);
}

const testing = await readFile("docs/TESTING.md", "utf8");
for (const phrase of ["npm run qa:live", "qa/live-capture/", "git-ignored"]) {
  if (!testing.includes(phrase)) throw new Error(`Testing guide missing live QA guidance: ${phrase}`);
}

const readiness = await readFile("scripts/check-release-readiness.mjs", "utf8");
for (const phrase of [
  "GitHub CLI authenticated",
  "Security reporting and dependency alerts are enabled",
  "v0.1.0 milestone has no open issues",
  "Signing and notarization secrets are configured",
  "Latest manual Release run passed"
]) {
  if (!readiness.includes(phrase)) throw new Error(`Release readiness checker missing: ${phrase}`);
}

const releaseDocs = await readFile("docs/RELEASE.md", "utf8");
if (!releaseDocs.includes("npm run release:readiness")) {
  throw new Error("Release docs must mention npm run release:readiness.");
}
if (!releaseDocs.includes("docs/STORE_ASSETS.md")) {
  throw new Error("Release docs must mention docs/STORE_ASSETS.md.");
}

const chromeStore = await readFile("docs/CHROME_WEB_STORE.md", "utf8");
if (!chromeStore.includes("docs/STORE_ASSETS.md")) {
  throw new Error("Chrome Web Store docs must link to docs/STORE_ASSETS.md.");
}

const storeAssets = await readFile("docs/STORE_ASSETS.md", "utf8");
for (const phrase of [
  "1280 by 800",
  "640 by 400",
  "440 by 280",
  "store-assets/chrome-web-store/small-promo-440x280.png",
  "npm run store:screenshots",
  "store-assets/chrome-web-store/screenshots/",
  "Do not use private AI chat transcripts",
  "https://developer.chrome.com/docs/webstore/images"
]) {
  if (!storeAssets.includes(phrase)) throw new Error(`Store asset guide missing: ${phrase}`);
}

for (const file of ["CONTRIBUTING.md", ".github/pull_request_template.md"]) {
  const text = await readFile(file, "utf8");
  if (!text.includes("npm run package:release")) {
    throw new Error(`${file} must point release-affecting changes to npm run package:release`);
  }
}

const releaseWorkflow = await readFile(".github/workflows/release.yml", "utf8");
for (const phrase of [
  "Require signed tag release credentials",
  "DEVELOPER_ID_CERTIFICATE_BASE64",
  "APPLE_APP_SPECIFIC_PASSWORD",
  "scripts/sign-mac-app.sh",
  "scripts/notarize-dmg.sh",
  "dist/Tacket.dmg",
  "dist/tacket-chrome-extension.zip",
  "dist/SHA256SUMS",
  "gh release create"
]) {
  if (!releaseWorkflow.includes(phrase)) throw new Error(`Release workflow missing: ${phrase}`);
}

const pagesWorkflow = await readFile(".github/workflows/pages.yml", "utf8");
for (const phrase of [
  "actions/configure-pages",
  "actions/upload-pages-artifact",
  "actions/deploy-pages",
  "path: website"
]) {
  if (!pagesWorkflow.includes(phrase)) throw new Error(`Pages workflow missing: ${phrase}`);
}

for (const file of [
  ".github/workflows/ci.yml",
  ".github/workflows/pages.yml",
  ".github/workflows/release.yml"
]) {
  const workflow = await readFile(file, "utf8");
  if (!workflow.includes("FORCE_JAVASCRIPT_ACTIONS_TO_NODE24")) {
    throw new Error(`${file} must opt GitHub JavaScript actions into Node 24.`);
  }
}

console.log("Project checks passed.");
