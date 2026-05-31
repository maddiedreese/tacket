import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const release = JSON.parse(await readFile(path.join(root, "release.json"), "utf8"));
const changelogPath = path.join(root, "CHANGELOG.md");
const args = parseArgs(process.argv.slice(2));
const date = args.date ?? today();
const checkOnly = args.check === true;

if (!/^\d{4}-\d{2}-\d{2}$/u.test(date)) {
  throw new Error(`Expected --date YYYY-MM-DD, found: ${date}`);
}

const changelog = await readFile(changelogPath, "utf8");
const unreleasedHeading = `## ${release.version} - Unreleased`;
const datedHeading = `## ${release.version} - ${date}`;
const datedPattern = new RegExp(`^## ${escapeRegex(release.version)} - \\d{4}-\\d{2}-\\d{2}$`, "mu");

if (datedPattern.test(changelog)) {
  console.log(`CHANGELOG.md already has a dated ${release.version} entry.`);
  process.exit(0);
}

if (!changelog.includes(unreleasedHeading)) {
  throw new Error(`CHANGELOG.md must contain "${unreleasedHeading}" before dating the release.`);
}

if (checkOnly) {
  console.log(`CHANGELOG.md can be dated for ${release.version} as ${date}.`);
  process.exit(0);
}

await writeFile(changelogPath, changelog.replace(unreleasedHeading, datedHeading), "utf8");
console.log(`Dated CHANGELOG.md ${release.version} entry as ${date}.`);

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--check") {
      parsed.check = true;
      continue;
    }
    if (value === "--date") {
      parsed.date = values[index + 1];
      index += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${value}`);
  }
  return parsed;
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
}
