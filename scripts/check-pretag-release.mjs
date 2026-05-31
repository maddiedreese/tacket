import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { promisify } from "node:util";
import path from "node:path";

const execFileAsync = promisify(execFile);
const root = path.resolve(new URL("..", import.meta.url).pathname);
const repo = "maddiedreese/tacket";
const release = JSON.parse(await readFile(path.join(root, "release.json"), "utf8"));
const tag = `v${release.version}`;
const requiredSecrets = [
  "DEVELOPER_ID_APPLICATION",
  "DEVELOPER_ID_CERTIFICATE_BASE64",
  "DEVELOPER_ID_CERTIFICATE_PASSWORD",
  "KEYCHAIN_PASSWORD",
  "APPLE_ID",
  "APPLE_TEAM_ID",
  "APPLE_APP_SPECIFIC_PASSWORD"
];
const checks = [];
const currentHead = await run("git", ["rev-parse", "HEAD"]);

await check("Working tree is clean", async () => {
  const status = await run("git", ["status", "--porcelain"]);
  assert(status.trim() === "", "working tree has uncommitted changes");
});

await check("Release artifacts verify", async () => {
  await run("npm", ["run", "verify:release"]);
});

await check("Chrome Web Store submission folder is ready", async () => {
  await run("npm", ["run", "store:verify"]);
});

await check("Versions are aligned", async () => {
  const pkg = JSON.parse(await readFile(path.join(root, "package.json"), "utf8"));
  const manifest = JSON.parse(await readFile(path.join(root, "apps/chrome-extension/manifest.json"), "utf8"));
  assert(pkg.version === release.version, `package.json version ${pkg.version} does not match ${release.version}`);
  assert(manifest.version === release.version, `extension version ${manifest.version} does not match ${release.version}`);
});

await check("CHANGELOG.md has a final dated 0.1.0 entry", async () => {
  const changelog = await readFile(path.join(root, "CHANGELOG.md"), "utf8");
  const expected = new RegExp(`^## ${escapeRegex(release.version)} - \\d{4}-\\d{2}-\\d{2}$`, "mu");
  assert(expected.test(changelog), `CHANGELOG.md must replace "## ${release.version} - Unreleased" with a YYYY-MM-DD release date`);
});

await check(`${tag} does not exist locally or remotely`, async () => {
  const localTags = await run("git", ["tag", "--list", tag]);
  assert(localTags.trim() === "", `${tag} already exists locally`);
  const remoteTags = await run("git", ["ls-remote", "--tags", "origin", tag]);
  assert(remoteTags.trim() === "", `${tag} already exists on origin`);
});

await check("Release issue checklists are synced", async () => {
  await run("node", ["scripts/check-release-issues.mjs"]);
});

await check("v0.1.0 milestone has no open issues", async () => {
  const issues = await ghJson([
    "issue",
    "list",
    "--repo",
    repo,
    "--milestone",
    tag,
    "--state",
    "open",
    "--json",
    "number,title,url"
  ]);
  assert(issues.length === 0, `${issues.length} open milestone issue(s): ${issues.map((issue) => `#${issue.number}`).join(", ")}`);
});

await check("Signing and notarization secrets are configured", async () => {
  const output = await run("gh", ["secret", "list", "--repo", repo]);
  const configured = new Set(output.split("\n").map((line) => line.split(/\s+/u)[0]).filter(Boolean));
  const missing = requiredSecrets.filter((secret) => !configured.has(secret));
  assert(missing.length === 0, `missing ${missing.join(", ")}`);
});

await check("Latest CI run passed on main", async () => {
  const runs = await ghJson([
    "run",
    "list",
    "--repo",
    repo,
    "--workflow",
    "CI",
    "--branch",
    "main",
    "--limit",
    "1",
    "--json",
    "status,conclusion,headSha,url"
  ]);
  assert(runs[0], "no CI runs found");
  assert(runs[0].status === "completed", `latest CI is ${runs[0].status}`);
  assert(runs[0].conclusion === "success", `latest CI conclusion is ${runs[0].conclusion}`);
  assert(runs[0].headSha === currentHead, `latest CI head ${runs[0].headSha} does not match local HEAD ${currentHead}`);
});

await check("Latest Release workflow run passed", async () => {
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
  assert(runs[0], "no Release runs found");
  assert(runs[0].status === "completed", `latest Release run is ${runs[0].status}`);
  assert(runs[0].conclusion === "success", `latest Release conclusion is ${runs[0].conclusion}`);
  assert(runs[0].headSha === currentHead, `latest Release head ${runs[0].headSha} does not match local HEAD ${currentHead}`);
});

await check("Latest Release workflow artifact is available", async () => {
  const run = await latestReleaseRun();
  const artifacts = await ghJson(["api", `repos/${repo}/actions/runs/${run.databaseId}/artifacts`]);
  const artifact = (artifacts.artifacts ?? []).find((item) => item.name === "tacket-release");
  assert(artifact, "missing tacket-release artifact");
  assert(artifact.expired === false, "tacket-release artifact is expired");
  assert(artifact.size_in_bytes > 0, "tacket-release artifact is empty");
});

await check("Latest Release workflow signed and notarized when secrets are configured", async () => {
  const missing = await missingSigningSecrets();
  if (missing.length > 0) return;
  const run = await latestReleaseRun();
  const jobs = await ghJson(["api", `repos/${repo}/actions/runs/${run.databaseId}/jobs`]);
  const steps = (jobs.jobs ?? []).flatMap((job) => job.steps ?? []);
  for (const name of [
    "Import Developer ID certificate",
    "Sign app",
    "Notarize DMG",
    "Gatekeeper assessment"
  ]) {
    const step = steps.find((item) => item.name === name);
    assert(step, `missing Release workflow step: ${name}`);
    assert(step.status === "completed", `${name} status is ${step.status}`);
    assert(step.conclusion === "success", `${name} conclusion is ${step.conclusion}`);
  }
});

printSummary();
if (checks.some((item) => item.status === "fail")) process.exit(1);

async function check(label, fn) {
  try {
    await fn();
    checks.push({ label, status: "pass" });
  } catch (error) {
    checks.push({ label, status: "fail", message: error?.message ?? String(error) });
  }
}

function printSummary() {
  for (const item of checks) {
    const mark = item.status === "pass" ? "PASS" : "FAIL";
    console.log(`${mark} ${item.label}${item.message ? ` - ${item.message}` : ""}`);
  }
}

async function ghJson(args) {
  const text = await run("gh", args);
  return JSON.parse(text);
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
  assert(runs[0], "no Release runs found");
  return runs[0];
}

async function missingSigningSecrets() {
  const output = await run("gh", ["secret", "list", "--repo", repo]);
  const configured = new Set(output.split("\n").map((line) => line.split(/\s+/u)[0]).filter(Boolean));
  return requiredSecrets.filter((secret) => !configured.has(secret));
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

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
}
