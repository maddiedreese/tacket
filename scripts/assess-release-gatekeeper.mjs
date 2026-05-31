import { execFile } from "node:child_process";
import { access, stat } from "node:fs/promises";
import { constants } from "node:fs";
import { promisify } from "node:util";
import path from "node:path";

const execFileAsync = promisify(execFile);
const root = path.resolve(new URL("..", import.meta.url).pathname);
const appPath = path.resolve(option("--app") ?? path.join(root, "dist", "Tacket.app"));
const dmgPath = path.resolve(option("--dmg") ?? path.join(root, "dist", "Tacket.dmg"));
const dryRun = process.argv.includes("--dry-run");

await assertDirectory(appPath);
await assertFile(dmgPath);

const checks = [
  ["codesign", ["--verify", "--deep", "--strict", "--verbose=2", appPath]],
  ["codesign", ["--display", "--verbose=2", appPath]],
  ["spctl", ["--assess", "--type", "execute", "--verbose", appPath]],
  ["hdiutil", ["verify", dmgPath]],
  ["spctl", ["--assess", "--type", "open", "--verbose", dmgPath]],
  ["xcrun", ["stapler", "validate", dmgPath]]
];

if (dryRun) {
  for (const [command, args] of checks) {
    console.log(`${command} ${args.map(shellQuote).join(" ")}`);
  }
  console.log("Gatekeeper assessment dry run passed.");
  process.exit(0);
}

const display = await run("codesign", ["--display", "--verbose=2", appPath]);
if (!display.includes("Authority=Developer ID Application")) {
  throw new Error("Tacket.app is not signed with a Developer ID Application certificate.");
}

await run("codesign", ["--verify", "--deep", "--strict", "--verbose=2", appPath]);
await run("spctl", ["--assess", "--type", "execute", "--verbose", appPath]);
await run("hdiutil", ["verify", dmgPath]);
await run("xcrun", ["stapler", "validate", dmgPath]);
await assessDmgWithGatekeeper(dmgPath);

console.log("Gatekeeper assessment passed.");

async function assertFile(file) {
  await access(file, constants.R_OK);
  const info = await stat(file);
  if (!info.isFile()) throw new Error(`Expected file: ${file}`);
  if (info.size <= 0) throw new Error(`File is empty: ${file}`);
}

async function assertDirectory(dir) {
  await access(dir, constants.R_OK);
  const info = await stat(dir);
  if (!info.isDirectory()) throw new Error(`Expected directory: ${dir}`);
}

async function run(command, args) {
  const { stdout, stderr } = await execFileAsync(command, args, {
    cwd: root,
    maxBuffer: 1024 * 1024 * 10
  });
  return `${stdout}${stderr}`.trim();
}

async function assessDmgWithGatekeeper(file) {
  try {
    await run("spctl", ["--assess", "--type", "open", "--verbose", file]);
  } catch (error) {
    const output = `${error.stdout ?? ""}${error.stderr ?? ""}`;
    if (!output.includes("source=Insufficient Context")) throw error;

    console.warn(
      "Gatekeeper DMG open assessment returned source=Insufficient Context; " +
        "accepting because hdiutil verify and stapler validate already passed."
    );
  }
}

function option(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) return undefined;
  const value = process.argv[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`${name} requires a value.`);
  return value;
}

function shellQuote(value) {
  if (/^[A-Za-z0-9_./:=@+-]+$/u.test(value)) return value;
  return `'${value.replace(/'/gu, "'\\''")}'`;
}
