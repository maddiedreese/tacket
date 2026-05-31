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

const repoState = await githubRepoState();
const pagesState = await githubPagesState();
const securityState = await githubSecurityState();
const openIssues = await safeGhJson([
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
const secrets = await configuredSecrets();
const missingSecrets = secrets ? requiredSecrets.filter((secret) => !secrets.has(secret)) : null;
const latestCi = await latestRun("CI", ["--branch", "main"]);
const latestRelease = await latestRun("Release", []);
const releaseExists = await githubReleaseExists(tag);

console.log(`Tacket ${tag} release status`);
console.log("");
printState("Repository settings", repoState);
printState("GitHub Pages", pagesState);
printState("Security reporting/dependency alerts", securityState);
printState("Latest CI on main", runState(latestCi));
printState("Latest manual Release workflow", runState(latestRelease));
printState("Open v0.1.0 milestone issues", openIssues ? (openIssues.length === 0 ? "clear" : `${openIssues.length} open`) : "unknown");
printState("Signing/notarization secrets", missingSecrets ? (missingSecrets.length === 0 ? "configured" : `${missingSecrets.length} missing`) : "unknown");
printState(`${tag} GitHub Release`, releaseExists === null ? "unknown" : (releaseExists ? "already exists" : "not published"));

console.log("");
console.log("Open blockers:");
if (openIssues?.length === 0 && missingSecrets?.length === 0 && releaseExists === false) {
  console.log("- No tracked blockers detected. Run `npm run release:pretag` before tagging.");
} else {
  for (const issue of openIssues ?? []) {
    console.log(`- #${issue.number} ${issue.title}: ${issue.url}`);
  }
  if (missingSecrets?.length > 0) {
    console.log(`- Missing signing/notarization secrets: ${missingSecrets.join(", ")}`);
  }
  if (releaseExists === true) {
    console.log(`- ${tag} already exists on GitHub Releases.`);
  }
  if (!openIssues || !missingSecrets || releaseExists === null) {
    console.log("- Some GitHub state could not be read. Run `gh auth status` and retry.");
  }
}

console.log("");
console.log("Next commands:");
console.log("- Live QA: `npm run qa:live`, `npm run qa:live:verify -- qa/live-capture/<report>.md`, then `npm run qa:live:summary -- qa/live-capture/<report>.md`");
console.log("- Signing secrets: `scripts/prepare-signing-secrets.sh --dry-run ...` then `npm run release:readiness`");
console.log("- Chrome store: `npm run store:prepare` then `npm run store:verify-id -- --extension-id <chrome-extension-id>`");
console.log("- Date changelog: `npm run release:date-changelog -- --date YYYY-MM-DD` when the external gates are complete");
console.log("- Release gate: `npm run package:release && npm run store:prepare && npm run release:pretag`");
console.log("- Create tag: `npm run release:tag -- --push`");
console.log("- Post release: `npm run release:postflight`");

function printState(label, value) {
  console.log(`${label}: ${value}`);
}

function runState(run) {
  if (run === null) return "unknown";
  if (!run) return "missing";
  return `${run.status}/${run.conclusion ?? "none"}`;
}

async function configuredSecrets() {
  try {
    const output = await gh(["secret", "list", "--repo", repo]);
    return new Set(output.split("\n").map((line) => line.split(/\s+/u)[0]).filter(Boolean));
  } catch {
    return null;
  }
}

async function latestRun(workflow, extraArgs) {
  const runs = await safeGhJson([
    "run",
    "list",
    "--repo",
    repo,
    "--workflow",
    workflow,
    "--limit",
    "1",
    "--json",
    "status,conclusion,url",
    ...extraArgs
  ]);
  return runs ? (runs[0] ?? undefined) : null;
}

async function githubReleaseExists(releaseTag) {
  try {
    const output = await gh(["release", "list", "--repo", repo, "--limit", "100"]);
    return output.split("\n").some((line) => line.split(/\s+/u).includes(releaseTag));
  } catch {
    return null;
  }
}

async function githubRepoState() {
  const repoInfo = await safeGhJson([
    "repo",
    "view",
    repo,
    "--json",
    "nameWithOwner,visibility,deleteBranchOnMerge,hasProjectsEnabled,hasWikiEnabled,isSecurityPolicyEnabled"
  ]);
  if (!repoInfo) return "unknown";
  const ok =
    repoInfo.nameWithOwner === repo &&
    repoInfo.visibility === "PUBLIC" &&
    repoInfo.deleteBranchOnMerge === true &&
    repoInfo.hasProjectsEnabled === false &&
    repoInfo.hasWikiEnabled === false &&
    repoInfo.isSecurityPolicyEnabled === true;
  return ok ? "configured" : "review";
}

async function githubPagesState() {
  const pages = await safeGhJson(["api", `repos/${repo}/pages`]);
  if (!pages) return "unknown";
  return pages.build_type === "workflow" && pages.https_enforced === true ? "configured" : "review";
}

async function githubSecurityState() {
  const privateReporting = await safeGhJson(["api", `repos/${repo}/private-vulnerability-reporting`]);
  const dependencyAlerts = await ghStatus(["api", `repos/${repo}/vulnerability-alerts`, "-i"]);
  const securityFixes = await ghStatus(["api", `repos/${repo}/automated-security-fixes`, "-i"]);
  if (!privateReporting || dependencyAlerts === null || securityFixes === null) return "unknown";
  return privateReporting.enabled === true && dependencyAlerts && securityFixes ? "configured" : "review";
}

async function ghStatus(args) {
  try {
    await gh(args);
    return true;
  } catch {
    return null;
  }
}

async function safeGhJson(args) {
  try {
    return JSON.parse(await gh(args));
  } catch {
    return null;
  }
}

async function gh(args) {
  const { stdout } = await execFileAsync("gh", args, {
    maxBuffer: 1024 * 1024 * 10
  });
  return stdout.trim();
}
