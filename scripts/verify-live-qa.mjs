import { readdir, readFile, stat } from "node:fs/promises";
import { spawn } from "node:child_process";
import path from "node:path";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const reportPath = await resolveReportPath(process.argv[2]);
const report = await readFile(reportPath, "utf8");
const currentHead = (await run("git", ["rev-parse", "HEAD"])).trim();

const failures = [];
const decision = extractField(report, "Release decision");
if (decision !== "Pass") {
  failures.push(`Release decision must be Pass, found: ${decision || "missing"}`);
}

for (const field of [
  "Tester",
  "Tacket commit",
  "Tacket version",
  "macOS",
  "Chrome",
  "Native host",
  "Save folder"
]) {
  requireFilledTopLevelField(field);
}

const tacketCommit = extractField(report, "Tacket commit").toLowerCase();
if (!/^[0-9a-f]{7,40}$/u.test(tacketCommit)) {
  failures.push("Tacket commit must be a git commit hash for the live QA build.");
} else if (!currentHead.startsWith(tacketCommit)) {
  failures.push(`Tacket commit ${tacketCommit} must match current HEAD ${currentHead.slice(0, 12)}.`);
}

const extensionId = extractField(report, "Extension ID");
if (!/^[a-p]{32}$/u.test(extensionId)) {
  failures.push("Extension ID must be the 32-letter Chrome extension ID tested.");
}

for (const finding of secretFindings(report)) {
  failures.push(`Report appears to include private secret-like text: ${finding}`);
}

for (const unchecked of report.matchAll(/^- \[ \] (.+)$/gmu)) {
  failures.push(`Incomplete checkbox: ${unchecked[1]}`);
}

requireCheckedItems([
  "Repo is clean or all local changes are intentional.",
  "`npm run package:release` passed locally or in GitHub CI.",
  "Production extension manifest does not include `file:///*`.",
  "Native messaging connector is installed for the tested Chrome extension ID.",
  "Save folder is known and writable.",
  "Existing test bundles are moved aside or clearly separated.",
  "ChatGPT Text user turn",
  "ChatGPT Text assistant turn",
  "ChatGPT Code block",
  "ChatGPT Image or image-like attachment",
  "ChatGPT Long enough to require scrolling",
  "Claude Text user turn",
  "Claude Text assistant turn",
  "Claude Code block",
  "Claude Attached or linked file",
  "Claude Long enough to require scrolling",
  "Gemini Text user turn",
  "Gemini Text model turn",
  "Gemini Code block",
  "Gemini Long enough to require scrolling",
  "Choose Saved Chat shows title, platform, URL, saved date, and message count.",
  "Possible-secret warnings render without exposing secret values in app chrome.",
  "Reveal in Finder opens Finder at the selected saved chat.",
  "Open Conversation File opens `transcript.md`.",
  "Copy Conversation copies the full saved conversation.",
  "Choose Save Folder persists to `~/Library/Application Support/Tacket/config.json`.",
  "Reset Folder returns to `~/Documents/Tacket Captures`.",
  "Clipboard transfer copies the full saved conversation.",
  "Codex transfer launches Terminal and requests paste.",
  "Claude Code transfer launches Terminal and requests paste.",
  "`--dry-run` CLI transfer works for Codex.",
  "`--dry-run` CLI transfer works for Claude Code.",
  "Small chunk size produces ordered raw chunks."
]);

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
    verifyReportedManifestEvidence(provider.heading, section, manifest);
  } catch (error) {
    failures.push(`${provider.heading} manifest could not be inspected: ${error.message}`);
  }
}

function verifyReportedManifestEvidence(heading, section, manifest) {
  const messageCount = numberField(section, "Message count");
  if (messageCount === null) {
    failures.push(`${heading} Message count must be a number matching manifest.json.`);
  } else if (messageCount !== manifest.messageCount) {
    failures.push(`${heading} Message count ${messageCount} does not match manifest.json ${manifest.messageCount}.`);
  }

  const attachmentCounts = attachmentCountsField(section, "Attachment counts");
  if (!attachmentCounts) {
    failures.push(`${heading} Attachment counts must use "captured / referenced / unavailable" numbers.`);
  } else {
    for (const key of ["captured", "referenced", "unavailable"]) {
      if (attachmentCounts[key] !== manifest.attachments?.[key]) {
        failures.push(`${heading} Attachment counts ${key}=${attachmentCounts[key]} does not match manifest.json ${manifest.attachments?.[key] ?? "missing"}.`);
      }
    }
  }

  const reportedWarnings = warningKindsField(section, "Warning kinds");
  if (!reportedWarnings) {
    failures.push(`${heading} Warning kinds must be "none" or a comma-separated list matching manifest.json.`);
  } else {
    const actualWarnings = new Set((manifest.warnings ?? []).map((warning) => warning.kind).filter(Boolean));
    if (!sameSet(reportedWarnings, actualWarnings)) {
      failures.push(`${heading} Warning kinds ${formatSet(reportedWarnings)} does not match manifest.json ${formatSet(actualWarnings)}.`);
    }
  }

  for (const field of ["Transcript opens", "Message order preserved", "Roles correct", "Code indentation preserved"]) {
    requireAffirmativeField(heading, section, field);
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
  const pattern = new RegExp(`^\\s*(?:-\\s*)?${escapeRegex(label)}:\\s*(.+?)\\s*$`, "imu");
  return markdown.match(pattern)?.[1]?.trim() ?? "";
}

function numberField(markdown, label) {
  const value = extractField(markdown, label);
  if (!/^\d+$/u.test(value)) return null;
  return Number(value);
}

function attachmentCountsField(markdown, label) {
  const value = extractField(markdown, label);
  const match = value.match(/^(\d+)\s*\/\s*(\d+)\s*\/\s*(\d+)$/u);
  if (!match) return null;
  return {
    captured: Number(match[1]),
    referenced: Number(match[2]),
    unavailable: Number(match[3])
  };
}

function warningKindsField(markdown, label) {
  const value = extractField(markdown, label).toLowerCase();
  if (!value) return null;
  if (["none", "no warnings", "n/a"].includes(value)) return new Set();
  return new Set(value.split(",").map((item) => item.trim()).filter(Boolean));
}

function requireAffirmativeField(heading, section, label) {
  const value = extractField(section, label).toLowerCase();
  if (!["yes", "pass", "passed", "true", "ok"].includes(value)) {
    failures.push(`${heading} ${label} must be affirmative, found: ${value || "missing"}.`);
  }
}

function requireFilledTopLevelField(label) {
  const value = extractField(report, label);
  if (!value || ["unset", "todo", "tbd", "unknown", "n/a", "test"].includes(value.toLowerCase())) {
    failures.push(`${label} must identify the live QA environment.`);
  }
}

function requireCheckedItems(labels) {
  const checked = checkedItemsBySection();
  for (const label of labels) {
    if (checked.has(label)) continue;
    failures.push(`Required checked item missing: ${label}`);
  }
}

function checkedItemsBySection() {
  const checked = new Set();
  let section = "";
  for (const line of report.split(/\r?\n/u)) {
    const heading = line.match(/^##\s+(.+)$/u);
    if (heading) {
      section = heading[1];
      continue;
    }
    const item = line.match(/^- \[[xX]\] (.+)$/u);
    if (!item) continue;
    checked.add(item[1]);
    if (["ChatGPT", "Claude", "Gemini"].includes(section)) {
      checked.add(`${section} ${item[1]}`);
    }
  }
  return checked;
}

function sameSet(a, b) {
  if (a.size !== b.size) return false;
  for (const item of a) {
    if (!b.has(item)) return false;
  }
  return true;
}

function formatSet(value) {
  return value.size === 0 ? "none" : [...value].sort().join(", ");
}

function secretFindings(text) {
  const patterns = [
    ["OpenAI API key", /sk-(?!ant-)[A-Za-z0-9_-]{20,}/u],
    ["Anthropic API key", /sk-ant-[A-Za-z0-9_-]{20,}/u],
    ["AWS access key id", /AKIA[0-9A-Z]{16}/u],
    ["GitHub token", /gh[pousr]_[A-Za-z0-9_]{20,}/u],
    ["Slack token", /xox[baprs]-[A-Za-z0-9-]{20,}/u],
    ["private key block", /-----BEGIN [A-Z ]*PRIVATE KEY-----/u]
  ];
  return patterns
    .filter(([, pattern]) => pattern.test(text))
    .map(([label]) => label);
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
