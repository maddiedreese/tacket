import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const repo = "maddiedreese/tacket";
const release = JSON.parse(await readFile("release.json", "utf8"));
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
const currentHead = await git(["rev-parse", "HEAD"]);

await check("GitHub CLI authenticated", async () => {
  await gh(["auth", "status"]);
});

await check("Working tree is clean", async () => {
  const status = await git(["status", "--porcelain"]);
  assert(status.trim() === "", "working tree has uncommitted changes");
});

await check("Repository is reachable", async () => {
  const repoInfo = await ghJson([
    "repo",
    "view",
    repo,
    "--json",
    "nameWithOwner,visibility,url,deleteBranchOnMerge,hasProjectsEnabled,hasWikiEnabled,isSecurityPolicyEnabled"
  ]);
  assert(repoInfo.nameWithOwner === repo, `expected ${repo}, found ${repoInfo.nameWithOwner}`);
  assert(repoInfo.visibility === "PUBLIC", `expected PUBLIC visibility, found ${repoInfo.visibility}`);
  assert(repoInfo.deleteBranchOnMerge === true, "expected delete branch on merge");
  assert(repoInfo.hasProjectsEnabled === false, "expected repository projects disabled");
  assert(repoInfo.hasWikiEnabled === false, "expected wiki disabled");
  assert(repoInfo.isSecurityPolicyEnabled === true, "expected SECURITY.md policy enabled");
});

await check("GitHub Pages is enabled", async () => {
  const pages = await ghJson(["api", `repos/${repo}/pages`]);
  assert(pages.build_type === "workflow", `expected workflow Pages build, found ${pages.build_type}`);
  assert(pages.https_enforced === true, "expected HTTPS enforcement");
});

await check("Security reporting and dependency alerts are enabled", async () => {
  const privateReporting = await ghJson(["api", `repos/${repo}/private-vulnerability-reporting`]);
  assert(privateReporting.enabled === true, "expected private vulnerability reporting enabled");
  await gh(["api", `repos/${repo}/vulnerability-alerts`, "-i"]);
  await gh(["api", `repos/${repo}/automated-security-fixes`, "-i"]);
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

await check("Latest manual Release run passed", async () => {
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
    "status,conclusion,event,url"
  ]);
  assert(runs[0], "no Release runs found");
  assert(runs[0].status === "completed", `latest Release run is ${runs[0].status}`);
  assert(runs[0].conclusion === "success", `latest Release conclusion is ${runs[0].conclusion}`);
});

await check("Release issue checklists are synced", async () => {
  await execFileAsync("node", ["scripts/check-release-issues.mjs"], {
    maxBuffer: 1024 * 1024 * 10
  });
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
  const output = await gh(["secret", "list", "--repo", repo]);
  const configured = new Set(output.split("\n").map((line) => line.split(/\s+/u)[0]).filter(Boolean));
  const missing = requiredSecrets.filter((secret) => !configured.has(secret));
  assert(missing.length === 0, `missing ${missing.join(", ")}`);
});

await check(`${tag} has not already been released`, async () => {
  const output = await gh(["release", "list", "--repo", repo, "--limit", "100"]);
  const exists = output.split("\n").some((line) => line.split(/\s+/u).includes(tag));
  assert(!exists, `${tag} already exists`);
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

async function gh(args) {
  const { stdout } = await execFileAsync("gh", args, {
    maxBuffer: 1024 * 1024 * 10
  });
  return stdout.trim();
}

async function git(args) {
  const { stdout } = await execFileAsync("git", args, {
    maxBuffer: 1024 * 1024 * 10
  });
  return stdout.trim();
}

async function ghJson(args) {
  const text = await gh(args);
  return JSON.parse(text);
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
