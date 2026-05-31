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
  "scripts/prepare-signing-secrets.sh",
  "scripts/package-extension.sh",
  "scripts/package-release.sh",
  "scripts/generate-icons.mjs",
  "scripts/verify-website.mjs",
  "scripts/generate-checksums.mjs",
  "scripts/check-versions.mjs",
  "scripts/validate-bundle.mjs",
  "scripts/verify-release.mjs",
  "scripts/smoke-swift-host.mjs",
  "scripts/smoke-first-run.mjs",
  "scripts/smoke-dmg-install.mjs",
  "scripts/new-live-qa.mjs",
  "scripts/verify-live-qa.mjs",
  "scripts/summarize-live-qa.mjs",
  "scripts/test/verify-live-qa.test.js",
  "scripts/test/date-changelog-release.test.js",
  "scripts/test/create-release-tag.test.js",
  "scripts/release-status.mjs",
  "scripts/date-changelog-release.mjs",
  "scripts/create-release-tag.mjs",
  "scripts/check-release-issues.mjs",
  "scripts/check-release-readiness.mjs",
  "scripts/check-pretag-release.mjs",
  "scripts/check-post-release.mjs",
  "scripts/verify-release-download.mjs",
  "scripts/assess-release-gatekeeper.mjs",
  "scripts/generate-store-screenshots.mjs",
  "scripts/prepare-chrome-web-store.mjs",
  "scripts/verify-chrome-web-store-package.mjs",
  "scripts/verify-web-store-extension-id.mjs"
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

const signingSecrets = await readFile("scripts/prepare-signing-secrets.sh", "utf8");
for (const phrase of [
  "DEVELOPER_ID_CERTIFICATE_BASE64",
  "gh secret set",
  "--dry-run",
  "does not write the",
  "openssl pkcs12"
]) {
  if (!signingSecrets.includes(phrase)) throw new Error(`Signing secret helper missing: ${phrase}`);
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
for (const phrase of ["milestone/1", "live capture validation", "Developer ID signing", "scripts/prepare-signing-secrets.sh", "Chrome Web Store"]) {
  if (!roadmap.includes(phrase)) throw new Error(`Roadmap missing: ${phrase}`);
}

const rootPackage = JSON.parse(await readFile("package.json", "utf8"));
if (rootPackage.scripts?.["qa:live"] !== "node scripts/new-live-qa.mjs") {
  throw new Error("package.json must expose npm run qa:live for live provider QA reports.");
}
if (rootPackage.scripts?.["website:verify"] !== "node scripts/verify-website.mjs") {
  throw new Error("package.json must expose npm run website:verify.");
}
if (!rootPackage.scripts?.verify?.includes("npm run website:verify")) {
  throw new Error("npm run verify must include website verification.");
}
if (rootPackage.scripts?.["smoke:first-run"] !== "node scripts/smoke-first-run.mjs") {
  throw new Error("package.json must expose npm run smoke:first-run.");
}
if (rootPackage.scripts?.["smoke:dmg-install"] !== "node scripts/smoke-dmg-install.mjs") {
  throw new Error("package.json must expose npm run smoke:dmg-install.");
}
if (!rootPackage.scripts?.verify?.includes("npm run smoke:first-run")) {
  throw new Error("npm run verify must include the first-run smoke test.");
}
if (rootPackage.scripts?.["qa:live:verify"] !== "node scripts/verify-live-qa.mjs") {
  throw new Error("package.json must expose npm run qa:live:verify.");
}
if (rootPackage.scripts?.["qa:live:summary"] !== "node scripts/summarize-live-qa.mjs") {
  throw new Error("package.json must expose npm run qa:live:summary.");
}
if (!rootPackage.scripts?.test?.includes("scripts/test/*.test.js")) {
  throw new Error("npm test must include script tests.");
}
if (rootPackage.scripts?.["release:status"] !== "node scripts/release-status.mjs") {
  throw new Error("package.json must expose npm run release:status.");
}
if (rootPackage.scripts?.["release:readiness"] !== "node scripts/check-release-readiness.mjs") {
  throw new Error("package.json must expose npm run release:readiness.");
}
if (rootPackage.scripts?.["release:issues"] !== "node scripts/check-release-issues.mjs") {
  throw new Error("package.json must expose npm run release:issues.");
}
if (rootPackage.scripts?.["release:date-changelog"] !== "node scripts/date-changelog-release.mjs") {
  throw new Error("package.json must expose npm run release:date-changelog.");
}
if (rootPackage.scripts?.["release:pretag"] !== "node scripts/check-pretag-release.mjs") {
  throw new Error("package.json must expose npm run release:pretag.");
}
if (rootPackage.scripts?.["release:tag"] !== "node scripts/create-release-tag.mjs") {
  throw new Error("package.json must expose npm run release:tag.");
}
if (rootPackage.scripts?.["release:verify-download"] !== "node scripts/verify-release-download.mjs") {
  throw new Error("package.json must expose npm run release:verify-download.");
}
if (rootPackage.scripts?.["release:verify-artifact"] !== "node scripts/verify-release-artifact.mjs") {
  throw new Error("package.json must expose npm run release:verify-artifact.");
}
if (rootPackage.scripts?.["release:assess"] !== "node scripts/assess-release-gatekeeper.mjs") {
  throw new Error("package.json must expose npm run release:assess.");
}
if (rootPackage.scripts?.["release:postflight"] !== "node scripts/check-post-release.mjs") {
  throw new Error("package.json must expose npm run release:postflight.");
}
if (rootPackage.scripts?.["store:screenshots"] !== "node scripts/generate-store-screenshots.mjs") {
  throw new Error("package.json must expose npm run store:screenshots.");
}
if (rootPackage.scripts?.["store:prepare"] !== "node scripts/prepare-chrome-web-store.mjs") {
  throw new Error("package.json must expose npm run store:prepare.");
}
if (rootPackage.scripts?.["store:verify"] !== "node scripts/verify-chrome-web-store-package.mjs") {
  throw new Error("package.json must expose npm run store:verify.");
}
if (rootPackage.scripts?.["store:verify-id"] !== "node scripts/verify-web-store-extension-id.mjs") {
  throw new Error("package.json must expose npm run store:verify-id.");
}

const liveQa = await readFile("scripts/new-live-qa.mjs", "utf8");
for (const phrase of ["Do not paste private transcript text", "npm run qa:live:verify", "ChatGPT", "Claude", "Gemini", "Release Decision"]) {
  if (!liveQa.includes(phrase)) throw new Error(`Live QA report template missing: ${phrase}`);
}

const verifyLiveQa = await readFile("scripts/verify-live-qa.mjs", "utf8");
for (const phrase of ["ChatGPT", "Claude", "Gemini", "validate-bundle.mjs", "Release decision", "Attachment counts", "Extension ID must be the 32-letter", "secret-like text"]) {
  if (!verifyLiveQa.includes(phrase)) throw new Error(`Live QA verifier missing: ${phrase}`);
}

const summarizeLiveQa = await readFile("scripts/summarize-live-qa.mjs", "utf8");
for (const phrase of ["Live QA Summary", "verify-live-qa.mjs", "Follow-up issue links", "Attachments captured", "assertPublicSummarySafe", "would leak a Chrome extension ID"]) {
  if (!summarizeLiveQa.includes(phrase)) throw new Error(`Live QA summary script missing: ${phrase}`);
}

const testing = await readFile("docs/TESTING.md", "utf8");
for (const phrase of ["npm run qa:live", "npm run qa:live:verify", "npm run qa:live:summary", "npm run smoke:first-run", "npm run smoke:dmg-install", "npm run website:verify", "qa/live-capture/", "git-ignored", "message/attachment/warning evidence"]) {
  if (!testing.includes(phrase)) throw new Error(`Testing guide missing live QA guidance: ${phrase}`);
}

const websiteVerifier = await readFile("scripts/verify-website.mjs", "utf8");
for (const phrase of ["releasesUrl", "SHA256SUMS", "Website checks passed"]) {
  if (!websiteVerifier.includes(phrase)) throw new Error(`Website verifier missing: ${phrase}`);
}

const firstRunSmoke = await readFile("scripts/smoke-first-run.mjs", "utf8");
for (const phrase of ["install-native-host", "saveCapture", "validate-bundle.mjs", "claude-code", "First-run smoke passed"]) {
  if (!firstRunSmoke.includes(phrase)) throw new Error(`First-run smoke script missing: ${phrase}`);
}

const dmgInstallSmoke = await readFile("scripts/smoke-dmg-install.mjs", "utf8");
for (const phrase of ["Tacket.dmg", "Tacket.app", "TacketNativeHost", "validate-bundle.mjs", "DMG install smoke passed"]) {
  if (!dmgInstallSmoke.includes(phrase)) throw new Error(`DMG install smoke script missing: ${phrase}`);
}

const readiness = await readFile("scripts/check-release-readiness.mjs", "utf8");
for (const phrase of [
  "GitHub CLI authenticated",
  "Working tree is clean",
  "Security reporting and dependency alerts are enabled",
  "does not match local HEAD",
  "latest Release head",
  "Latest Release workflow artifact is available",
  "Latest Release workflow artifact contents verify",
  "Latest Release workflow signed and notarized when secrets are configured",
  "Release issue checklists are synced",
  "v0.1.0 milestone has no open issues",
  "Signing and notarization secrets are configured",
  "Latest manual Release run passed"
]) {
  if (!readiness.includes(phrase)) throw new Error(`Release readiness checker missing: ${phrase}`);
}

const releaseStatus = await readFile("scripts/release-status.mjs", "utf8");
for (const phrase of ["Open blockers", "Next commands", "Local HEAD", "matches HEAD", "Latest Release artifact", "Latest Release artifact contents", "Release issue checklists", "npm run qa:live:verify", "npm run release:issues", "npm run release:verify-artifact", "npm run store:verify-id", "npm run release:date-changelog", "npm run release:pretag", "npm run release:tag"]) {
  if (!releaseStatus.includes(phrase)) throw new Error(`Release status script missing: ${phrase}`);
}

const releaseIssues = await readFile("scripts/check-release-issues.mjs", "utf8");
for (const phrase of ["qa:live:summary", "store:verify-id", "dist/chrome-web-store/", "release:verify-artifact", "latest Release artifact contents are verified", "release:postflight", "--sync", "--dry-run"]) {
  if (!releaseIssues.includes(phrase)) throw new Error(`Release issue checker missing: ${phrase}`);
}

const dateChangelog = await readFile("scripts/date-changelog-release.mjs", "utf8");
for (const phrase of ["--date YYYY-MM-DD", "Unreleased", "--check", "Dated CHANGELOG.md"]) {
  if (!dateChangelog.includes(phrase)) throw new Error(`Changelog dating script missing: ${phrase}`);
}

const pretag = await readFile("scripts/check-pretag-release.mjs", "utf8");
for (const phrase of [
  "Chrome Web Store submission folder is ready",
  "Working tree is clean",
  "does not match local HEAD",
  "latest Release head",
  "Latest Release workflow artifact is available",
  "Latest Release workflow artifact contents verify",
  "Latest Release workflow signed and notarized when secrets are configured",
  "CHANGELOG.md has a final dated",
  "Release issue checklists are synced",
  "v0.1.0 milestone has no open issues",
  "Signing and notarization secrets are configured",
  "Latest Release workflow run passed"
]) {
  if (!pretag.includes(phrase)) throw new Error(`Pre-tag release checker missing: ${phrase}`);
}

const releaseTag = await readFile("scripts/create-release-tag.mjs", "utf8");
for (const phrase of ["release:pretag", "git\", [\"tag\", \"-a\"", "--push", "--dry-run", "Working tree must be clean"]) {
  if (!releaseTag.includes(phrase)) throw new Error(`Release tag script missing: ${phrase}`);
}

const verifyDownload = await readFile("scripts/verify-release-download.mjs", "utf8");
for (const phrase of ["gh", "release", "download", "SHA256SUMS", "hdiutil", "manifest.dev.json"]) {
  if (!verifyDownload.includes(phrase)) throw new Error(`Release download verifier missing: ${phrase}`);
}

const verifyArtifact = await readFile("scripts/verify-release-artifact.mjs", "utf8");
for (const phrase of ["gh", "run", "download", "tacket-release", "chrome-web-store", "release:verify-download"]) {
  if (!verifyArtifact.includes(phrase)) throw new Error(`Release artifact verifier missing: ${phrase}`);
}

const gatekeeperAssess = await readFile("scripts/assess-release-gatekeeper.mjs", "utf8");
for (const phrase of ["spctl", "stapler", "Developer ID Application", "Gatekeeper assessment passed", "--dry-run"]) {
  if (!gatekeeperAssess.includes(phrase)) throw new Error(`Gatekeeper assessment script missing: ${phrase}`);
}

const postRelease = await readFile("scripts/check-post-release.mjs", "utf8");
for (const phrase of ["Release downloads verify", "GitHub Release is published with required assets", "Gatekeeper assessment", "--dry-run-gatekeeper", "release:verify-download"]) {
  if (!postRelease.includes(phrase)) throw new Error(`Post-release checker missing: ${phrase}`);
}

const releaseDocs = await readFile("docs/RELEASE.md", "utf8");
if (!releaseDocs.includes("npm run release:status")) {
  throw new Error("Release docs must mention npm run release:status.");
}
if (!releaseDocs.includes("npm run store:verify")) {
  throw new Error("Release docs must mention npm run store:verify.");
}
if (!releaseDocs.includes("npm run release:readiness")) {
  throw new Error("Release docs must mention npm run release:readiness.");
}
if (!releaseDocs.includes("npm run release:issues")) {
  throw new Error("Release docs must mention npm run release:issues.");
}
if (!releaseDocs.includes("npm run release:date-changelog")) {
  throw new Error("Release docs must mention npm run release:date-changelog.");
}
if (!releaseDocs.includes("npm run release:pretag")) {
  throw new Error("Release docs must mention npm run release:pretag.");
}
if (!releaseDocs.includes("npm run release:tag")) {
  throw new Error("Release docs must mention npm run release:tag.");
}
if (!releaseDocs.includes("npm run release:verify-download")) {
  throw new Error("Release docs must mention npm run release:verify-download.");
}
if (!releaseDocs.includes("npm run release:verify-artifact")) {
  throw new Error("Release docs must mention npm run release:verify-artifact.");
}
if (!releaseDocs.includes("npm run release:postflight")) {
  throw new Error("Release docs must mention npm run release:postflight.");
}
if (!releaseDocs.includes("npm run release:assess")) {
  throw new Error("Release docs must mention npm run release:assess.");
}
if (!releaseDocs.includes("docs/STORE_ASSETS.md")) {
  throw new Error("Release docs must mention docs/STORE_ASSETS.md.");
}
if (!releaseDocs.includes("scripts/prepare-signing-secrets.sh")) {
  throw new Error("Release docs must mention scripts/prepare-signing-secrets.sh.");
}

const chromeStore = await readFile("docs/CHROME_WEB_STORE.md", "utf8");
if (!chromeStore.includes("docs/STORE_ASSETS.md")) {
  throw new Error("Chrome Web Store docs must link to docs/STORE_ASSETS.md.");
}
for (const command of ["npm run store:prepare", "npm run store:verify"]) {
  if (!chromeStore.includes(command)) throw new Error(`Chrome Web Store docs must mention ${command}.`);
}
for (const phrase of ["listing.md", "privacy.md"]) {
  if (!chromeStore.includes(phrase)) throw new Error(`Chrome Web Store docs must mention generated ${phrase}.`);
}

const storeAssets = await readFile("docs/STORE_ASSETS.md", "utf8");
for (const phrase of [
  "1280 by 800",
  "640 by 400",
  "440 by 280",
  "store-assets/chrome-web-store/small-promo-440x280.png",
  "npm run store:screenshots",
  "npm run store:prepare",
  "listing.md",
  "privacy.md",
  "store-assets/chrome-web-store/screenshots/",
  "Do not use private AI chat transcripts",
  "https://developer.chrome.com/docs/webstore/images"
]) {
  if (!storeAssets.includes(phrase)) throw new Error(`Store asset guide missing: ${phrase}`);
}

const storePrepare = await readFile("scripts/prepare-chrome-web-store.mjs", "utf8");
for (const phrase of ["assertExtensionZip", "listing.md", "privacy.md", "manifest.dev.json", "store:verify", "generate:checksums"]) {
  if (!storePrepare.includes(phrase)) throw new Error(`Chrome Web Store prep script missing: ${phrase}`);
}

const storeVerify = await readFile("scripts/verify-chrome-web-store-package.mjs", "utf8");
for (const phrase of ["Extension permissions", "Extension host permissions", "secret-like text", "does not match dist/tacket-chrome-extension.zip", "Chrome Web Store package checks passed"]) {
  if (!storeVerify.includes(phrase)) throw new Error(`Chrome Web Store package verifier missing: ${phrase}`);
}

const storeVerifyId = await readFile("scripts/verify-web-store-extension-id.mjs", "utf8");
for (const phrase of ["--extension-id", "allowed_origins", "uninstall-native-host", "Chrome Web Store extension ID verification passed"]) {
  if (!storeVerifyId.includes(phrase)) throw new Error(`Chrome Web Store extension ID verifier missing: ${phrase}`);
}

const packageRelease = await readFile("scripts/package-release.sh", "utf8");
if (!packageRelease.includes("smoke:dmg-install")) {
  throw new Error("Release package script must run npm run smoke:dmg-install.");
}
if (!packageRelease.includes("store:prepare")) {
  throw new Error("Release package script must prepare the Chrome Web Store upload folder.");
}
if (!packageRelease.includes("Release and Chrome Web Store artifacts ready")) {
  throw new Error("Release package script must report both release and Chrome Web Store artifacts.");
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
  "Gatekeeper assessment",
  "npm run release:assess",
  "npm run store:prepare",
  "dist/Tacket.dmg",
  "dist/tacket-chrome-extension.zip",
  "dist/SHA256SUMS",
  "dist/chrome-web-store",
  "gh release create"
]) {
  if (!releaseWorkflow.includes(phrase)) throw new Error(`Release workflow missing: ${phrase}`);
}

const verifyRelease = await readFile("scripts/verify-release.mjs", "utf8");
for (const phrase of ["verifyPackagedNativeMessagingManifest", "verifyMacConnectorSource"]) {
  if (!verifyRelease.includes(phrase)) throw new Error(`Release verifier missing: ${phrase}`);
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
