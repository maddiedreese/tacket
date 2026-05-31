import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const root = path.resolve(new URL("..", import.meta.url).pathname);
const cli = path.join(root, "apps", "cli", "bin", "tacket.js");
const extensionId = option("--extension-id");

if (!extensionId) {
  console.error("Usage: npm run store:verify-id -- --extension-id <chrome-extension-id>");
  process.exit(2);
}

if (!/^[a-p]{32}$/u.test(extensionId)) {
  throw new Error("Invalid Chrome extension ID. Expected 32 lowercase letters from a to p.");
}

const home = await mkdtemp(path.join(os.tmpdir(), "tacket-web-store-id-"));
try {
  await run(process.execPath, [cli, "install-native-host", "--extension-id", extensionId], { HOME: home });
  const status = JSON.parse(await run(process.execPath, [cli, "status-native-host"], { HOME: home }));
  const expectedOrigin = `chrome-extension://${extensionId}/`;
  if (status.installed !== true) throw new Error("Native messaging host status did not report installed.");
  if (!status.allowedOrigins?.includes(expectedOrigin)) {
    throw new Error(`Native messaging host missing expected origin: ${expectedOrigin}`);
  }

  const manifest = JSON.parse(await readFile(status.manifestPath, "utf8"));
  if (manifest.name !== "dev.tacket.host") throw new Error(`Native host name mismatch: ${manifest.name}`);
  if (manifest.type !== "stdio") throw new Error(`Native host type mismatch: ${manifest.type}`);
  if (manifest.allowed_origins?.length !== 1 || manifest.allowed_origins[0] !== expectedOrigin) {
    throw new Error(`Native host allowed_origins must contain only ${expectedOrigin}`);
  }

  await run(process.execPath, [cli, "uninstall-native-host"], { HOME: home });
  const after = JSON.parse(await run(process.execPath, [cli, "status-native-host"], { HOME: home }));
  if (after.installed !== false) throw new Error("Native messaging host uninstall did not clear the manifest.");

  console.log(`Chrome Web Store extension ID verification passed for ${extensionId}.`);
} finally {
  await rm(home, { recursive: true, force: true });
}

function option(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) return undefined;
  const value = process.argv[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`${name} requires a value.`);
  return value;
}

async function run(command, args, env = {}) {
  const { stdout } = await execFileAsync(command, args, {
    cwd: root,
    env: { ...process.env, ...env },
    maxBuffer: 1024 * 1024 * 10
  });
  return stdout.trim();
}
