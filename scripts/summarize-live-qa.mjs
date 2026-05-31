import { readdir, readFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import path from "node:path";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const options = parseArgs(process.argv.slice(2));
const reportPath = await resolveReportPath(options.reportPath);
const report = await readFile(reportPath, "utf8");

if (!options.noVerify) {
  await run("node", ["scripts/verify-live-qa.mjs", reportPath]);
}

const providers = ["ChatGPT", "Claude", "Gemini"].map((name) => {
  const section = extractSection(report, name);
  return {
    name,
    messageCount: extractField(section, "Message count"),
    attachments: extractField(section, "Attachment counts"),
    warnings: normalizeWarnings(extractField(section, "Warning kinds")),
    transcriptOpens: extractField(section, "Transcript opens"),
    messageOrder: extractField(section, "Message order preserved"),
    roles: extractField(section, "Roles correct"),
    codeIndentation: extractField(section, "Code indentation preserved")
  };
});

const summary = [
  "## Live QA Summary",
  "",
  `Report date: ${extractField(report, "Date") || "unknown"}`,
  `Tacket commit: ${extractField(report, "Tacket commit") || "unknown"}`,
  `Tacket version: ${extractField(report, "Tacket version") || "unknown"}`,
  `macOS: ${extractField(report, "macOS") || "unknown"}`,
  `Chrome: ${extractField(report, "Chrome") || "unknown"}`,
  `Native host: ${extractField(report, "Native host") || "unknown"}`,
  `Release decision: ${extractField(report, "Release decision") || "unknown"}`,
  "",
  "| Provider | Messages | Attachments captured / referenced / unavailable | Warning kinds | Transcript opens | Order | Roles | Code |",
  "| --- | ---: | --- | --- | --- | --- | --- | --- |",
  ...providers.map((provider) =>
    `| ${provider.name} | ${provider.messageCount || "unknown"} | ${provider.attachments || "unknown"} | ${provider.warnings} | ${status(provider.transcriptOpens)} | ${status(provider.messageOrder)} | ${status(provider.roles)} | ${status(provider.codeIndentation)} |`
  ),
  "",
  "Follow-up issue links:",
  ...followUpLinks(report).map((link) => `- ${link}`)
];

if (summary.at(-1) === "Follow-up issue links:") summary.push("- None recorded");

const summaryText = summary.join("\n");
assertPublicSummarySafe(summaryText);
console.log(summaryText);

function parseArgs(values) {
  const parsed = {};
  for (const value of values) {
    if (value === "--no-verify") {
      parsed.noVerify = true;
      continue;
    }
    if (value.startsWith("--")) throw new Error(`Unknown argument: ${value}`);
    if (parsed.reportPath) throw new Error(`Unexpected extra argument: ${value}`);
    parsed.reportPath = value;
  }
  return parsed;
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
    throw new Error("Usage: npm run qa:live:summary -- qa/live-capture/<report>.md");
  }
  return latest;
}

function extractSection(markdown, heading) {
  const pattern = new RegExp(`(?:^|\\n)## ${escapeRegex(heading)}\\n([\\s\\S]*?)(?=\\n## |$)`, "u");
  return markdown.match(pattern)?.[1] ?? "";
}

function extractField(markdown, label) {
  const pattern = new RegExp(`^\\s*(?:-\\s*)?${escapeRegex(label)}:\\s*(.*?)\\s*$`, "imu");
  return markdown.match(pattern)?.[1]?.trim() ?? "";
}

function followUpLinks(markdown) {
  const section = markdown.split(/^Follow-up issue links:\s*$/mu)[1] ?? "";
  return [...section.matchAll(/https:\/\/github\.com\/[^\s)]+/gu)].map((match) => match[0]);
}

function normalizeWarnings(value) {
  const normalized = value.trim();
  if (!normalized || ["none", "no warnings", "n/a"].includes(normalized.toLowerCase())) return "none";
  return normalized;
}

function status(value) {
  return value || "unknown";
}

function assertPublicSummarySafe(summaryText) {
  for (const [label, value] of privateReportValues()) {
    if (value && summaryText.includes(value)) {
      throw new Error(`Live QA summary would leak private ${label}.`);
    }
  }
  if (/\b[a-p]{32}\b/u.test(summaryText)) {
    throw new Error("Live QA summary would leak a Chrome extension ID.");
  }
  if (/Bundle path:/iu.test(summaryText)) {
    throw new Error("Live QA summary would leak bundle path labels.");
  }
}

function privateReportValues() {
  const values = [
    ["tester", extractField(report, "Tester")],
    ["extension ID", extractField(report, "Extension ID")],
    ["capture folder", extractField(report, "Capture folder")]
  ];
  for (const name of ["ChatGPT", "Claude", "Gemini"]) {
    const section = extractSection(report, name);
    values.push([`${name} bundle path`, extractField(section, "Bundle path")]);
  }
  return values.filter(([, value]) => value && !["none", "n/a"].includes(value.toLowerCase()));
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
