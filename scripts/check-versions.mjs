import { readFile } from "node:fs/promises";

const release = JSON.parse(await readFile("release.json", "utf8"));
const rootPackage = JSON.parse(await readFile("package.json", "utf8"));
const cliPackage = JSON.parse(await readFile("apps/cli/package.json", "utf8"));
const hostPackage = JSON.parse(await readFile("apps/native-host/package.json", "utf8"));
const formatPackage = JSON.parse(await readFile("packages/thread-format/package.json", "utf8"));
const chromeManifest = JSON.parse(await readFile("apps/chrome-extension/manifest.json", "utf8"));
const chromeDevManifest = JSON.parse(await readFile("apps/chrome-extension/manifest.dev.json", "utf8"));
const extensionBackground = await readFile("apps/chrome-extension/src/background.js", "utf8");
const cli = await readFile("apps/cli/bin/tacket.js", "utf8");
const macApp = await readFile("apps/mac/TacketApp/Sources/TacketApp/TacketApp.swift", "utf8");
const jsFormat = await readFile("packages/thread-format/src/index.js", "utf8");
const swiftHost = await readFile("apps/mac/TacketApp/Sources/TacketNativeHost/main.swift", "utf8");
const changelog = await readFile("CHANGELOG.md", "utf8");

const packageFiles = [
  ["package.json", rootPackage],
  ["apps/cli/package.json", cliPackage],
  ["apps/native-host/package.json", hostPackage],
  ["packages/thread-format/package.json", formatPackage]
];

for (const [file, json] of packageFiles) {
  assertEqual(`${file} version`, json.version, release.version);
}

assertEqual("Chrome manifest version", chromeManifest.version, release.version);
assertEqual("Chrome dev manifest version", chromeDevManifest.version, release.version);

for (const [file, json] of [
  ["apps/cli/package.json", cliPackage],
  ["apps/native-host/package.json", hostPackage]
]) {
  assertEqual(`${file} @tacket/thread-format`, json.dependencies["@tacket/thread-format"], release.version);
}

if (!jsFormat.includes(`SCHEMA_VERSION = "${release.schemaVersion}"`)) {
  throw new Error("JS thread format schema version does not match release.json");
}
if (!swiftHost.includes(`let schemaVersion = "${release.schemaVersion}"`)) {
  throw new Error("Swift host schema version does not match release.json");
}
if (!changelog.includes(`## ${release.version} `)) {
  throw new Error("CHANGELOG.md does not include the current release.json version");
}

for (const [file, text] of [
  ["apps/chrome-extension/src/background.js", extensionBackground],
  ["apps/cli/bin/tacket.js", cli],
  ["apps/mac/TacketApp/Sources/TacketApp/TacketApp.swift", macApp]
]) {
  if (!text.includes(release.nativeHostName)) {
    throw new Error(`${file} native host name does not match release.json`);
  }
}

for (const [file, text] of [
  ["apps/cli/bin/tacket.js", cli],
  ["apps/mac/TacketApp/Sources/TacketApp/TacketApp.swift", macApp]
]) {
  if (!text.includes(`${release.nativeHostName}.json`)) {
    throw new Error(`${file} native host manifest filename does not match release.json`);
  }
}

console.log("Version checks passed.");

function assertEqual(label, actual, expected) {
  if (actual !== expected) {
    throw new Error(`${label} expected ${expected}, found ${actual}`);
  }
}
