#!/usr/bin/env node
import { mkdir, writeFile, chmod, readFile, access, rm } from "node:fs/promises";
import { constants } from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { indexLibraryFolder, listLibrary, removeMissingBundles, searchLibrary } from "@tacket/library";
import { readTranscript, splitTranscript, writeBundle } from "@tacket/thread-format";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");

const commands = {
  "install-native-host": installNativeHost,
  "status-native-host": statusNativeHost,
  "uninstall-native-host": uninstallNativeHost,
  "library-index": libraryIndex,
  "library-search": librarySearch,
  "library-list": libraryList,
  "library-remove-missing": libraryRemoveMissing,
  sample,
  transfer,
  help
};

const [command = "help", ...args] = process.argv.slice(2);
const run = commands[command];

if (!run) {
  console.error(`Unknown command: ${command}`);
  help();
  process.exit(1);
}

Promise.resolve(run(parseArgs(args))).catch((error) => {
  console.error(error?.message ?? String(error));
  process.exit(1);
});

async function installNativeHost(options) {
  const extensionId = options["extension-id"];
  if (!extensionId) {
    throw new Error("Missing --extension-id <id>.");
  }
  validateChromeExtensionId(extensionId);

  const hostScript = path.join(rootDir, "apps/native-host/bin/tacket-native-host.js");
  const manifestDir = nativeHostManifestDir();
  const manifestPath = nativeHostManifestPath();
  const launcherPath = nativeHostLauncherPath();
  await mkdir(manifestDir, { recursive: true });
  await chmod(hostScript, 0o755);
  await writeFile(
    launcherPath,
    `#!/bin/sh\nexec ${shellQuote(process.execPath)} ${shellQuote(hostScript)}\n`,
    "utf8"
  );
  await chmod(launcherPath, 0o755);

  const manifest = {
    name: "dev.tacket.host",
    description: "Tacket local capture host",
    path: launcherPath,
    type: "stdio",
    allowed_origins: [`chrome-extension://${extensionId}/`]
  };

  await writeFile(manifestPath, JSON.stringify(manifest, null, 2) + "\n");
  console.log(`Installed Chrome native messaging host: ${manifestPath}`);
}

async function statusNativeHost() {
  const manifestPath = nativeHostManifestPath();
  try {
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    console.log(JSON.stringify({
      installed: true,
      manifestPath,
      hostPath: manifest.path,
      allowedOrigins: manifest.allowed_origins ?? []
    }, null, 2));
  } catch {
    console.log(JSON.stringify({
      installed: false,
      manifestPath
    }, null, 2));
  }
}

async function uninstallNativeHost() {
  const manifestPath = nativeHostManifestPath();
  const launcherPath = nativeHostLauncherPath();
  await rm(manifestPath, { force: true });
  await rm(launcherPath, { force: true });
  console.log(`Removed Chrome native messaging host manifest: ${manifestPath}`);
}

async function libraryIndex(options) {
  const folder = options.folder ?? options._[0];
  if (!folder) throw new Error("Usage: tacket library-index --folder <path> [--db <library.sqlite>]");
  const result = await indexLibraryFolder(folder, { db: options.db });
  console.log(JSON.stringify(result, null, 2));
}

async function librarySearch(options) {
  const query = options._.join(" ").trim();
  if (!query) throw new Error("Usage: tacket library-search <query> [--db <library.sqlite>] [--limit <n>]");
  const result = await searchLibrary(query, { db: options.db, limit: options.limit });
  console.log(JSON.stringify(result, null, 2));
}

async function libraryList(options) {
  const result = await listLibrary({ db: options.db });
  console.log(JSON.stringify(result, null, 2));
}

async function libraryRemoveMissing(options) {
  const result = await removeMissingBundles({ db: options.db });
  console.log(JSON.stringify(result, null, 2));
}

async function sample(options) {
  const out = expandHome(options.out ?? path.join(os.tmpdir(), "tacket-sample"));
  await mkdir(out, { recursive: true });
  const result = await writeBundle(
    {
      title: "Tacket sample thread",
      source: { url: "https://chatgpt.com/c/sample" },
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "I want the full raw thread transferred, not a summary." }]
        },
        {
          role: "assistant",
          content: [
            { type: "text", text: "Understood. Preserve the raw transcript and paste it into the coding agent." },
            { type: "code", language: "bash", text: "tacket transfer ./thread.tacket --to codex" }
          ]
        }
      ]
    },
    out
  );

  console.log(result.bundlePath);
}

async function transfer(options) {
  const bundlePath = options._[0];
  if (!bundlePath) throw new Error("Usage: tacket transfer <bundle.tacket> [--to clipboard|codex|claude-code] [--chunk-size 24000]");
  await ensureExists(bundlePath);
  await assertBundleReadyForTransfer(bundlePath);

  const target = options.to ?? "clipboard";
  const chunkSize = Number(options["chunk-size"] ?? 24000);
  if (!Number.isSafeInteger(chunkSize) || chunkSize < 1000) {
    throw new Error("Invalid chunk size. Expected an integer of at least 1000 characters.");
  }
  const transcript = await readTranscript(bundlePath);
  const chunks = splitTranscript(transcript, chunkSize);

  if (target === "clipboard") {
    await copyToClipboard(chunks.join("\n\n"));
    console.log(`Copied ${chunks.length} raw transcript chunk(s) to the clipboard.`);
    return;
  }

  if (target === "codex" || target === "claude-code") {
    const command = target === "codex" ? "codex" : "claude";
    const terminalTitle = target === "codex" ? "Tacket Codex Transfer" : "Tacket Claude Code Transfer";
    await copyToClipboard(chunks.join("\n\n"));
    if (options["dry-run"] === true) {
      console.log(`Copied ${chunks.length} raw transcript chunk(s); dry run skipped Terminal launch for ${command}.`);
      return;
    }
    const shouldPaste = options.paste !== false && options["no-paste"] !== true;
    const launch = launchTerminal(command, terminalTitle, shouldPaste);
    if (!launch.ok) {
      console.log(`Copied ${chunks.length} raw transcript chunk(s), but Terminal launch did not complete: ${launch.error}`);
      return;
    }
    const pasteDetail = shouldPaste ? "and requested paste into Terminal" : "without requesting paste";
    console.log(`Launched ${command}, copied ${chunks.length} raw transcript chunk(s), ${pasteDetail}.`);
    return;
  }

  throw new Error(`Unsupported transfer target: ${target}`);
}

function help() {
  console.log(`Tacket

Usage:
  tacket install-native-host --extension-id <chrome-extension-id>
  tacket status-native-host
  tacket uninstall-native-host
  tacket library-index --folder ~/Documents/Tacket\\ Captures
  tacket library-search "stripe webhook"
  tacket library-list
  tacket library-remove-missing
  tacket sample --out /tmp/tacket-demo
  tacket transfer <bundle.tacket> --to clipboard
  tacket transfer <bundle.tacket> --to codex
  tacket transfer <bundle.tacket> --to claude-code

Options:
  --no-paste          Launch target and copy transcript, but do not request Cmd+V
  --dry-run           Copy transcript and skip target launch
  --chunk-size <n>    Maximum characters per raw transcript chunk
`);
}

function parseArgs(args) {
  const parsed = { _: [] };
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith("--")) {
      parsed._.push(arg);
      continue;
    }
    const key = arg.slice(2);
    const next = args[index + 1];
    if (!next || next.startsWith("--")) {
      parsed[key] = true;
    } else {
      parsed[key] = next;
      index += 1;
    }
  }
  return parsed;
}

async function copyToClipboard(value) {
  const child = spawn("pbcopy", [], { stdio: ["pipe", "ignore", "inherit"] });
  child.stdin.end(value);
  await new Promise((resolve, reject) => {
    child.on("exit", (code) => code === 0 ? resolve() : reject(new Error(`pbcopy exited with ${code}`)));
    child.on("error", reject);
  });
}

function launchTerminal(command, title, paste) {
  const escaped = command.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  const pasteScript = paste
    ? `
delay 1.5
tell application "System Events"
  keystroke "v" using command down
end tell`
    : "";
  const script = `
tell application "Terminal"
  activate
  do script "printf '\\\\e]0;${title}\\\\a'; ${escaped}"
end tell${pasteScript}`;
  const result = spawnSync("osascript", ["-e", script], {
    stdio: "ignore",
    timeout: 10000
  });
  if (result.error) {
    return { ok: false, error: result.error.message };
  }
  if (result.status !== 0) {
    return { ok: false, error: `osascript exited with ${result.status ?? "unknown"}` };
  }
  return { ok: true };
}

async function ensureExists(target) {
  await access(target, constants.R_OK);
}

async function assertBundleReadyForTransfer(bundlePath) {
  await Promise.all([
    readFile(path.join(bundlePath, "manifest.json"), "utf8"),
    readFile(path.join(bundlePath, "messages.jsonl"), "utf8")
  ]);
  const transcript = await readTranscript(bundlePath);
  for (const target of ["codex.md", "claude-code.md"]) {
    const targetText = await readFile(path.join(bundlePath, "targets", target), "utf8");
    if (targetText !== transcript) {
      throw new Error(`Invalid .tacket bundle: targets/${target} must match transcript.md exactly.`);
    }
  }
}

function expandHome(value) {
  if (value === "~") return os.homedir();
  if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2));
  return value;
}

function nativeHostManifestDir() {
  return path.join(os.homedir(), "Library/Application Support/Google/Chrome/NativeMessagingHosts");
}

function nativeHostManifestPath() {
  return path.join(nativeHostManifestDir(), "dev.tacket.host.json");
}

function nativeHostLauncherPath() {
  return path.join(nativeHostManifestDir(), "dev.tacket.host.sh");
}

function validateChromeExtensionId(extensionId) {
  if (!/^[a-p]{32}$/.test(extensionId)) {
    throw new Error("Invalid Chrome extension ID. Expected 32 lowercase letters from a to p.");
  }
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}
