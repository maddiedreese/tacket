import { readFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const runtimeFiles = [
  "apps/chrome-extension/manifest.json",
  "apps/chrome-extension/manifest.dev.json",
  "apps/chrome-extension/src/background.js",
  "apps/chrome-extension/src/popup.js",
  "apps/chrome-extension/src/adapters/capture.js",
  "apps/cli/bin/tacket.js",
  "apps/native-host/bin/tacket-native-host.js",
  "apps/mac/TacketApp/Sources/TacketApp/TacketApp.swift",
  "apps/mac/TacketApp/Sources/TacketNativeHost/main.swift",
  "packages/thread-format/src/index.js"
];
const allowedHosts = new Set([
  "chatgpt.com",
  "chat.openai.com",
  "claude.ai",
  "gemini.google.com"
]);
const forbiddenPatterns = [
  ["XMLHttpRequest", /\bXMLHttpRequest\b/u],
  ["sendBeacon", /\bsendBeacon\b/u],
  ["WebSocket", /\bWebSocket\b/u],
  ["EventSource", /\bEventSource\b/u],
  ["URLSession", /\bURLSession\b/u],
  ["NSURLConnection", /\bNSURLConnection\b/u],
  ["WKWebView", /\bWKWebView\b/u],
  ["analytics SDK", /\b(analytics|telemetry|posthog|segment|amplitude|mixpanel|sentry)\b/iu],
  ["Node networking import", /from\s+["']node:(?:http|https|net|dgram|dns|tls)["']/u],
  ["CommonJS networking require", /require\(["'](?:node:)?(?:http|https|net|dgram|dns|tls)["']\)/u]
];

const productionManifest = await readJson("apps/chrome-extension/manifest.json");
assertExactSet("production extension permissions", productionManifest.permissions ?? [], [
  "activeTab",
  "scripting",
  "nativeMessaging"
]);
assertExactSet("production extension host permissions", productionManifest.host_permissions ?? [], [
  "https://chatgpt.com/*",
  "https://chat.openai.com/*",
  "https://claude.ai/*",
  "https://gemini.google.com/*"
]);
assertNoManifestNetworkExpansion("production extension manifest", productionManifest);

const devManifest = await readJson("apps/chrome-extension/manifest.dev.json");
assertExactSet("development extension permissions", devManifest.permissions ?? [], [
  "activeTab",
  "scripting",
  "nativeMessaging"
]);
assertExactSet("development extension host permissions", devManifest.host_permissions ?? [], [
  "https://chatgpt.com/*",
  "https://chat.openai.com/*",
  "https://claude.ai/*",
  "https://gemini.google.com/*",
  "file:///*"
]);
assertNoManifestNetworkExpansion("development extension manifest", devManifest);

for (const file of runtimeFiles) {
  const text = await read(file);
  assertNoForbiddenPatterns(file, text);
  assertAllowedFetches(file, text);
  assertAllowedRemoteLiterals(file, text);
}

console.log("Local-first privacy checks passed.");

async function readJson(file) {
  return JSON.parse(await read(file));
}

async function read(file) {
  return readFile(path.join(root, file), "utf8");
}

function assertNoManifestNetworkExpansion(label, manifest) {
  for (const key of ["content_scripts", "externally_connectable", "optional_permissions", "optional_host_permissions"]) {
    if (Object.hasOwn(manifest, key)) throw new Error(`${label} must not define ${key}.`);
  }
}

function assertNoForbiddenPatterns(file, text) {
  for (const [label, pattern] of forbiddenPatterns) {
    if (pattern.test(text)) throw new Error(`${file} includes forbidden local-first runtime pattern: ${label}`);
  }
}

function assertAllowedFetches(file, text) {
  const calls = [...text.matchAll(/\bfetch\s*\(([^)\n]+)/gu)];
  for (const call of calls) {
    const argument = call[1].trim();
    const allowed = file === "apps/chrome-extension/src/adapters/capture.js" && argument === "src";
    if (!allowed) throw new Error(`${file} includes an unapproved fetch call: fetch(${argument})`);
  }
}

function assertAllowedRemoteLiterals(file, text) {
  for (const match of text.matchAll(/\bhttps?:\/\/[^"'`\s),]+/gu)) {
    const value = match[0];
    let host;
    try {
      host = new URL(value).hostname;
    } catch {
      throw new Error(`${file} includes an invalid remote URL literal: ${value}`);
    }
    if (!allowedHosts.has(host)) {
      throw new Error(`${file} includes an unapproved remote URL literal: ${value}`);
    }
  }
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
