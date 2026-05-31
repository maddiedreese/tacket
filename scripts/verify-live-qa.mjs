import { readdir, readFile, stat } from "node:fs/promises";
import { spawn } from "node:child_process";
import path from "node:path";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const reportPath = await resolveReportPath(process.argv[2]);
const report = await readFile(reportPath, "utf8");

const failures = [];
const decision = extractField(report, "Release decision");
if (decision !== "Pass") {
  failures.push(`Release decision must be Pass, found: ${decision || "missing"}`);
}

for (const unchecked of report.matchAll(/^- \[ \] (.+)$/gmu)) {
  failures.push(`Incomplete checkbox: ${unchecked[1]}`);
}

for (const forbidden of [
  "Release decision: Unset",
  "Bundle path:\n",
  "Bundle path:\r\n"
]) {
  if (report.includes(forbidden)) failures.push(`Report still contains placeholder: ${forbidden.trim()}`);
}

for (const provider of [
  { heading: "ChatGPT", platform: "chatgpt" },
  { heading: "Claude", platform: "claude" },
  { heading: "Gemini", platform: "gemini" }
]) {
  await verifyProviderBundle(provider);
}

if (failures.length > 0) {
  console.error(`Live QA verification failed for ${reportPath}:`);
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`Live QA verification passed for ${reportPath}`);

async function verifyProviderBundle(provider) {
  const section = extractSection(report, provider.heading);
  if (!section) {
    failures.push(`Missing ${provider.heading} section.`);
    return;
  }

  const bundlePath = extractField(section, "Bundle path");
  if (!bundlePath) {
    failures.push(`${provider.heading} bundle path is missing.`);
    return;
  }

  const absoluteBundlePath = path.resolve(path.dirname(reportPath), bundlePath);
  try {
    const info = await stat(absoluteBundlePath);
    if (!info.isDirectory()) failures.push(`${provider.heading} bundle path is not a directory: ${absoluteBundlePath}`);
  } catch (error) {
    failures.push(`${provider.heading} bundle path is not readable: ${absoluteBundlePath} (${error.code ?? error.message})`);
    return;
  }

  try {
    await run("node", ["scripts/validate-bundle.mjs", absoluteBundlePath]);
  } catch (error) {
    failures.push(`${provider.heading} bundle failed validate-bundle.mjs: ${error.message}`);
    return;
  }

  try {
    const manifest = JSON.parse(await readFile(path.join(absoluteBundlePath, "manifest.json"), "utf8"));
    if (manifest.source?.platform !== provider.platform) {
      failures.push(`${provider.heading} manifest platform must be ${provider.platform}, found ${manifest.source?.platform ?? "missing"}.`);
    }
    if (!Number.isInteger(manifest.messageCount) || manifest.messageCount < 1) {
      failures.push(`${provider.heading} manifest messageCount must be at least 1.`);
    }
  } catch (error) {
    failures.push(`${provider.heading} manifest could not be inspected: ${error.message}`);
  }
}

async function resolveReportPath(argument) {
  if (argument) return path.resolve(argument);

  const qaDir = path.join(root, "qa", "live-capture");
  const entries = await readdir(qaDir);
  const reports = entries
    .filter((entry) => entry.endsWith(".md"))
    .map((entry) => path.join(qaDir, entry))
    .sort();
  const latest = reports.at(-1);
  if (!latest) {
    console.error("Usage: npm run qa:live:verify -- qa/live-capture/<report>.md");
    console.error("No markdown reports found in qa/live-capture/.");
    process.exit(1);
  }
  return latest;
}

function extractSection(markdown, heading) {
  const pattern = new RegExp(`(?:^|\\n)## ${escapeRegex(heading)}\\n([\\s\\S]*?)(?=\\n## |$)`, "u");
  return markdown.match(pattern)?.[1] ?? "";
}

function extractField(markdown, label) {
  const pattern = new RegExp(`^${escapeRegex(label)}:\\s*(.+?)\\s*$`, "imu");
  return markdown.match(pattern)?.[1]?.trim() ?? "";
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
}

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: root,
      stdio: ["ignore", "pipe", "pipe"]
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) resolve(Buffer.concat(stdout).toString("utf8"));
      else reject(new Error(Buffer.concat(stderr).toString("utf8").trim() || `${command} ${args.join(" ")} failed with ${code}`));
    });
  });
}
