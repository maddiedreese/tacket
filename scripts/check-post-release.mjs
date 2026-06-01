import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const root = path.resolve(new URL("..", import.meta.url).pathname);
const repo = "maddiedreese/tacket";
const release = JSON.parse(await readFile(path.join(root, "release.json"), "utf8"));
const options = parseArgs(process.argv.slice(2));
const tag = options.tag ?? `v${release.version}`;
const checks = [];
const artifactDir = options.dir
  ? path.resolve(options.dir)
  : await mkdtemp(path.join(os.tmpdir(), "tacket-post-release-"));

try {
  await check("Website verifies", async () => {
    await run("npm", ["run", "website:verify"]);
  });

  await check("Release downloads verify", async () => {
    if (!options.dir) await downloadReleaseArtifacts(artifactDir);
    await run("npm", ["run", "release:verify-download", "--", "--dir", artifactDir]);
  });

  await check("GitHub Release is published with required assets", async () => {
    if (options.dir) {
      return skip("GitHub Release is published with required assets", "local --dir mode");
    }
    const releaseInfo = await ghJson([
      "release",
      "view",
      tag,
      "--repo",
      repo,
      "--json",
      "tagName,isDraft,isPrerelease,url,assets"
    ]);
    assert(releaseInfo.tagName === tag, `expected tag ${tag}, found ${releaseInfo.tagName}`);
    assert(releaseInfo.isDraft === false, "release must not be a draft");
    assert(releaseInfo.isPrerelease === false, "release must not be marked prerelease");
    const assets = new Set((releaseInfo.assets ?? []).map((asset) => asset.name));
    for (const asset of ["Tacket.dmg", "tacket-chrome-extension.zip", "SHA256SUMS"]) {
      assert(assets.has(asset), `GitHub Release missing asset ${asset}`);
    }
  });

  await check("Gatekeeper assessment", async () => {
    if (options["skip-gatekeeper"]) return;
    if (options.dir) {
      await assertDirectory(path.join(artifactDir, "Tacket.app"));
      await assertFile(path.join(artifactDir, "Tacket.dmg"));
      const args = [
        "run",
        "release:assess",
        "--",
        "--app",
        path.join(artifactDir, "Tacket.app"),
        "--dmg",
        path.join(artifactDir, "Tacket.dmg")
      ];
      if (options["dry-run-gatekeeper"]) args.push("--dry-run");
      await run("npm", args);
      return;
    }
    await assessDownloadedDmg(artifactDir);
  });

  printSummary();
  if (checks.some((item) => item.status === "fail")) process.exitCode = 1;
} finally {
  if (!options.dir) await rm(artifactDir, { recursive: true, force: true });
}

async function check(label, fn) {
  try {
    const result = await fn();
    if (result === "skip") return;
    checks.push({ label, status: "pass" });
  } catch (error) {
    checks.push({ label, status: "fail", message: error?.message ?? String(error) });
  }
}

function printSummary() {
  for (const item of checks) {
    const mark = item.status === "pass" ? "PASS" : item.status === "skip" ? "SKIP" : "FAIL";
    console.log(`${mark} ${item.label}${item.message ? ` - ${item.message}` : ""}`);
  }
}

function skip(label, message) {
  checks.push({ label, status: "skip", message });
  return "skip";
}

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--skip-gatekeeper" || value === "--dry-run-gatekeeper") {
      parsed[value.slice(2)] = true;
      continue;
    }
    if (value === "--tag" || value === "--dir") {
      const next = values[index + 1];
      if (!next || next.startsWith("--")) throw new Error(`${value} requires a value.`);
      parsed[value.slice(2)] = next;
      index += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${value}`);
  }
  return parsed;
}

async function ghJson(args) {
  return JSON.parse(await run("gh", args));
}

async function downloadReleaseArtifacts(dir) {
  await run("gh", [
    "release",
    "download",
    tag,
    "--repo",
    repo,
    "--dir",
    dir,
    "--pattern",
    "Tacket.dmg",
    "--pattern",
    "tacket-chrome-extension.zip",
    "--pattern",
    "SHA256SUMS",
    "--clobber"
  ]);
}

async function assessDownloadedDmg(dir) {
  const dmgPath = path.join(dir, "Tacket.dmg");
  await assertFile(dmgPath);
  const mountRoot = await mkdtemp(path.join(os.tmpdir(), "tacket-post-release-mount-"));
  const mountPoint = path.join(mountRoot, "Tacket");
  await mkdir(mountPoint);
  let mounted = false;
  try {
    await run("hdiutil", ["attach", dmgPath, "-nobrowse", "-readonly", "-mountpoint", mountPoint]);
    mounted = true;
    const appPath = path.join(mountPoint, "Tacket.app");
    await assertDirectory(appPath);
    const args = ["run", "release:assess", "--", "--app", appPath, "--dmg", dmgPath];
    if (options["dry-run-gatekeeper"]) args.push("--dry-run");
    await run("npm", args);
  } finally {
    if (mounted) {
      try {
        await run("hdiutil", ["detach", mountPoint]);
      } catch {
        await run("hdiutil", ["detach", mountPoint, "-force"]);
      }
    }
    await rm(mountRoot, { recursive: true, force: true });
  }
}

async function assertFile(file) {
  const info = await stat(file);
  if (!info.isFile()) throw new Error(`Expected file: ${file}`);
  if (info.size <= 0) throw new Error(`File is empty: ${file}`);
}

async function assertDirectory(dir) {
  const info = await stat(dir);
  if (!info.isDirectory()) throw new Error(`Expected directory: ${dir}`);
}

async function run(command, args) {
  const { stdout } = await execFileAsync(command, args, {
    cwd: root,
    maxBuffer: 1024 * 1024 * 10
  });
  return stdout.trim();
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
