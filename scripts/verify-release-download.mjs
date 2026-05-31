import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const root = path.resolve(new URL("..", import.meta.url).pathname);
const repo = "maddiedreese/tacket";
const release = JSON.parse(await readFile(path.join(root, "release.json"), "utf8"));
const tag = option("--tag") ?? `v${release.version}`;
const providedDir = option("--dir");
const keep = process.argv.includes("--keep");
const artifacts = ["Tacket.dmg", "tacket-chrome-extension.zip", "SHA256SUMS"];

const workDir = providedDir
  ? path.resolve(providedDir)
  : await mkdtemp(path.join(os.tmpdir(), "tacket-release-download-"));

try {
  if (!providedDir) {
    await run("gh", [
      "release",
      "download",
      tag,
      "--repo",
      repo,
      "--dir",
      workDir,
      "--pattern",
      "Tacket.dmg",
      "--pattern",
      "tacket-chrome-extension.zip",
      "--pattern",
      "SHA256SUMS",
      "--clobber"
    ]);
  }

  for (const artifact of artifacts) await assertFile(path.join(workDir, artifact));
  await verifyChecksums(workDir);
  await verifyExtensionZip(path.join(workDir, "tacket-chrome-extension.zip"));
  await run("hdiutil", ["verify", path.join(workDir, "Tacket.dmg")]);
  console.log(`Release download verification passed for ${providedDir ? workDir : `${repo} ${tag}`}.`);
} finally {
  if (!providedDir && !keep) await rm(workDir, { recursive: true, force: true });
}

async function verifyChecksums(dir) {
  const expected = new Map();
  const text = await readFile(path.join(dir, "SHA256SUMS"), "utf8");
  for (const line of text.split("\n").filter(Boolean)) {
    const match = line.match(/^([a-f0-9]{64})  (.+)$/u);
    if (!match) throw new Error(`Invalid SHA256SUMS line: ${line}`);
    expected.set(match[2], match[1]);
  }

  for (const artifact of ["Tacket.dmg", "tacket-chrome-extension.zip"]) {
    const bytes = await readFile(path.join(dir, artifact));
    const actual = createHash("sha256").update(bytes).digest("hex");
    if (expected.get(artifact) !== actual) {
      throw new Error(`SHA256SUMS hash for ${artifact} is missing or stale.`);
    }
  }
}

async function verifyExtensionZip(zipPath) {
  const listing = await run("unzip", ["-l", zipPath]);
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
    if (!listing.includes(entry)) throw new Error(`Downloaded extension zip missing ${entry}`);
  }
  for (const forbidden of ["manifest.dev.json", "test/", ".DS_Store"]) {
    if (listing.includes(forbidden)) throw new Error(`Downloaded extension zip includes forbidden entry ${forbidden}`);
  }
}

async function assertFile(file) {
  const info = await stat(file);
  if (!info.isFile()) throw new Error(`Expected file: ${file}`);
  if (info.size <= 0) throw new Error(`File is empty: ${file}`);
}

function option(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) return undefined;
  const value = process.argv[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`${name} requires a value.`);
  return value;
}

async function run(command, args) {
  const { stdout } = await execFileAsync(command, args, {
    cwd: root,
    maxBuffer: 1024 * 1024 * 10
  });
  return stdout.trim();
}
