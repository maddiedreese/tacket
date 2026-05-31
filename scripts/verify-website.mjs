import { access, readFile, stat } from "node:fs/promises";
import { constants } from "node:fs";
import path from "node:path";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const website = path.join(root, "website");
const repoUrl = "https://github.com/maddiedreese/tacket";
const releasesUrl = `${repoUrl}/releases`;

await assertFile(path.join(website, "index.html"));
await assertFile(path.join(website, "privacy.html"));
await assertFile(path.join(website, "styles.css"));
await assertFile(path.join(website, "assets/favicon.png"));
await assertFile(path.join(website, "assets/icon-180.png"));

const index = await readFile(path.join(website, "index.html"), "utf8");
const privacy = await readFile(path.join(website, "privacy.html"), "utf8");
const css = await readFile(path.join(website, "styles.css"), "utf8");

for (const phrase of [
  releasesUrl,
  repoUrl,
  "https://github.com/sponsors/maddiedreese",
  "https://twitter.com/maddiedreese",
  "./privacy.html",
  "transfer the full conversation",
  "It will always be free",
  "always be open source",
  "see any of your chats",
  "no accounts, no analytics",
  "Made by"
]) {
  if (!index.includes(phrase)) throw new Error(`website/index.html missing: ${phrase}`);
}

for (const phrase of [
  "No analytics",
  "No telemetry",
  "No model/API calls",
  "Chrome Native Messaging",
  "private vulnerability reporting"
]) {
  if (!privacy.includes(phrase)) throw new Error(`website/privacy.html missing: ${phrase}`);
}

for (const selector of [".hero-mark", ".statement", ".button.primary", ".maker", ".sponsor"]) {
  if (!css.includes(selector)) throw new Error(`website/styles.css missing: ${selector}`);
}

if (css.includes("Inter")) {
  throw new Error("Website CSS must not use Inter.");
}

if (/font-size:\s*clamp\([^;]*vw/iu.test(css)) {
  throw new Error("Website CSS must not scale font size with viewport width.");
}

console.log("Website checks passed.");

async function assertFile(file) {
  await access(file, constants.R_OK);
  const info = await stat(file);
  if (!info.isFile()) throw new Error(`Expected file: ${file}`);
  if (info.size <= 0) throw new Error(`File is empty: ${file}`);
}
