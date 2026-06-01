import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { access, mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { constants } from "node:fs";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const root = path.resolve(new URL("..", import.meta.url).pathname);
const repo = "maddiedreese/tacket";
const options = parseArgs(process.argv.slice(2));
const runId = options["run-id"];
const keep = options.keep ?? false;
const expectedReleaseFiles = ["Tacket.dmg", "tacket-chrome-extension.zip", "SHA256SUMS"];
const expectedStoreFiles = [
  "tacket-chrome-extension.zip",
  "icon-128.png",
  "small-promo-440x280.png",
  "marquee-promo-1400x560.png",
  "listing.md",
  "privacy.md",
  "README.md",
  "screenshots/01-capture-popup-1280x800.png",
  "screenshots/02-local-bundle-1280x800.png",
  "screenshots/03-local-library-1280x800.png"
];

const runInfo = runId ? await releaseRun(runId) : await latestReleaseRun();
const currentHead = await run("git", ["rev-parse", "HEAD"]);
assert(runInfo.status === "completed", `Release workflow run ${runInfo.databaseId} is ${runInfo.status}`);
assert(runInfo.conclusion === "success", `Release workflow run ${runInfo.databaseId} conclusion is ${runInfo.conclusion}`);
assert(runInfo.headSha === currentHead, `Release workflow run ${runInfo.databaseId} head ${runInfo.headSha} does not match local HEAD ${currentHead}`);

const workDir = await mkdtemp(path.join(os.tmpdir(), "tacket-release-artifact-"));
try {
  await run("gh", [
    "run",
    "download",
    String(runInfo.databaseId),
    "--repo",
    repo,
    "--name",
    "tacket-release",
    "--dir",
    workDir
  ]);

  for (const file of expectedReleaseFiles) await assertFile(path.join(workDir, file));
  for (const file of expectedStoreFiles) await assertFile(path.join(workDir, "chrome-web-store", file));
  await assertZipHashesMatch(
    path.join(workDir, "tacket-chrome-extension.zip"),
    path.join(workDir, "chrome-web-store", "tacket-chrome-extension.zip")
  );
  await run("npm", ["run", "release:verify-download", "--", "--dir", workDir]);
  await verifyStoreCopy(workDir);
  console.log(`Release workflow artifact verification passed for run ${runInfo.databaseId}.`);
} finally {
  if (!keep) await rm(workDir, { recursive: true, force: true });
  else console.log(`Kept downloaded artifact at ${workDir}`);
}

async function verifyStoreCopy(dir) {
  const listing = await readFile(path.join(dir, "chrome-web-store", "listing.md"), "utf8");
  const privacy = await readFile(path.join(dir, "chrome-web-store", "privacy.md"), "utf8");
  const readme = await readFile(path.join(dir, "chrome-web-store", "README.md"), "utf8");
  for (const phrase of ["Single Purpose", "Permission Justification", "https://gemini.google.com/*"]) {
    if (!listing.includes(phrase)) throw new Error(`Chrome Web Store artifact listing missing: ${phrase}`);
  }
  for (const phrase of ["No backend", "No analytics", "saved conversation is sent to the local Tacket app"]) {
    if (!privacy.includes(phrase)) throw new Error(`Chrome Web Store artifact privacy copy missing: ${phrase}`);
  }
  for (const phrase of ["Upload `tacket-chrome-extension.zip`", "Review every image before upload"]) {
    if (!readme.includes(phrase)) throw new Error(`Chrome Web Store artifact README missing: ${phrase}`);
  }
}

async function assertZipHashesMatch(releaseZip, storeZip) {
  const releaseHash = await sha256(releaseZip);
  const storeHash = await sha256(storeZip);
  if (releaseHash !== storeHash) {
    throw new Error("Chrome Web Store artifact zip does not match the release extension zip.");
  }
}

async function sha256(file) {
  return createHash("sha256").update(await readFile(file)).digest("hex");
}

async function assertFile(file) {
  await access(file, constants.R_OK);
  const info = await stat(file);
  if (!info.isFile()) throw new Error(`Expected file: ${file}`);
  if (info.size <= 0) throw new Error(`File is empty: ${file}`);
}

async function latestReleaseRun() {
  const runs = await ghJson([
    "run",
    "list",
    "--repo",
    repo,
    "--workflow",
    "Release",
    "--limit",
    "1",
    "--json",
    "databaseId,status,conclusion,headSha,url"
  ]);
  assert(runs[0], "no Release workflow runs found");
  return runs[0];
}

async function releaseRun(id) {
  return ghJson([
    "run",
    "view",
    id,
    "--repo",
    repo,
    "--json",
    "databaseId,status,conclusion,headSha,url"
  ]);
}

async function ghJson(args) {
  return JSON.parse(await run("gh", args));
}

async function run(command, args) {
  const { stdout } = await execFileAsync(command, args, {
    cwd: root,
    maxBuffer: 1024 * 1024 * 20
  });
  return stdout.trim();
}

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--keep") {
      parsed.keep = true;
      continue;
    }
    if (value === "--run-id") {
      const next = values[index + 1];
      if (!next || next.startsWith("--")) throw new Error(`${value} requires a value.`);
      parsed["run-id"] = next;
      index += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${value}`);
  }
  return parsed;
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
