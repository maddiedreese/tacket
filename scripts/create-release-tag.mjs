import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const root = path.resolve(new URL("..", import.meta.url).pathname);
const release = JSON.parse(await readFile(path.join(root, "release.json"), "utf8"));
const tag = `v${release.version}`;
const args = parseArgs(process.argv.slice(2));

if (args.help) {
  usage();
  process.exit(0);
}

const tagMessage = args.message ?? `Tacket ${release.version}`;

if (args["dry-run"]) {
  console.log(`Would run: npm run release:pretag`);
  console.log(`Would run: git tag -a ${tag} -m "${tagMessage}"`);
  if (args.push) console.log(`Would run: git push origin ${tag}`);
  else console.log(`Would leave ${tag} local. Pass --push to push it.`);
  process.exit(0);
}

await run("npm", ["run", "release:pretag"]);
await assertCleanWorktree();
await assertTagMissing(tag);

await run("git", ["tag", "-a", tag, "-m", tagMessage]);
console.log(`Created release tag ${tag}.`);

if (args.push) {
  await run("git", ["push", "origin", tag]);
  console.log(`Pushed release tag ${tag} to origin.`);
} else {
  console.log(`Tag ${tag} is local. Push with: git push origin ${tag}`);
}

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (value === "--push" || value === "--dry-run" || value === "--help") {
      parsed[value.slice(2)] = true;
      continue;
    }
    if (value === "--message") {
      parsed.message = values[index + 1];
      index += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${value}`);
  }
  return parsed;
}

function usage() {
  console.log(`Usage: npm run release:tag -- [--push] [--dry-run] [--message "Tacket ${release.version}"]`);
}

async function assertCleanWorktree() {
  const status = await run("git", ["status", "--porcelain"]);
  if (status.trim()) {
    throw new Error("Working tree must be clean before creating the release tag.");
  }
}

async function assertTagMissing(name) {
  const local = await run("git", ["tag", "--list", name]);
  if (local.trim()) throw new Error(`${name} already exists locally.`);
  const remote = await run("git", ["ls-remote", "--tags", "origin", name]);
  if (remote.trim()) throw new Error(`${name} already exists on origin.`);
}

async function run(command, argsForCommand) {
  const { stdout } = await execFileAsync(command, argsForCommand, {
    cwd: root,
    maxBuffer: 1024 * 1024 * 10
  });
  return stdout.trim();
}
