import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const hostPath = process.argv[2];
if (!hostPath) {
  console.error("Usage: node scripts/smoke-swift-host.mjs <TacketNativeHost path>");
  process.exit(1);
}

const outputRoot = await mkdtemp(path.join(os.tmpdir(), "tacket-swift-host-"));
const configuredRoot = await mkdtemp(path.join(os.tmpdir(), "tacket-swift-host-configured-"));
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

try {
  const response = await sendNativeMessage(hostPath, {
    type: "saveCapture",
    capture: {
      title: "Swift Host Smoke",
      source: { url: "https://chatgpt.com/c/swift" },
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "swift host raw transfer sk-1234567890abcdefghijklmnopqrstuvwxyz" }]
        },
        {
          role: "assistant",
          content: [{ type: "code", language: "swift", text: "print(\"ok\")" }]
        }
      ]
    }
  }, outputRoot);

  if (!response.ok) throw new Error(response.error ?? "Swift host returned failure.");
  if (response.manifest.messageCount !== 2) throw new Error("Swift host wrote wrong message count.");
  if (response.manifest.source.platform !== "chatgpt") throw new Error("Swift host wrote wrong platform.");
  if (response.manifest.warnings?.[0]?.kind !== "openai_api_key") {
    throw new Error("Swift host did not emit possible-secret warning.");
  }

  const jsonl = await readFile(path.join(response.bundlePath, "messages.jsonl"), "utf8");
  const lines = jsonl.trim().split("\n");
  if (lines.length !== 2) throw new Error("Swift host did not write one JSON object per line.");
  for (const line of lines) JSON.parse(line);
  await run("node", ["scripts/validate-bundle.mjs", response.bundlePath]);

  const configured = await sendNativeMessage(hostPath, {
    type: "saveCapture",
    capture: {
      title: "Swift Host Config",
      source: { url: "https://claude.ai/chat/config" },
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "config path test" }]
        }
      ]
    }
  }, null, configuredRoot);
  if (!configured.bundlePath.startsWith(configuredRoot)) {
    throw new Error("Swift host did not honor configured capture directory.");
  }
  await run("node", ["scripts/validate-bundle.mjs", configured.bundlePath]);

  const invalid = await sendNativeMessage(hostPath, {
    type: "saveCapture",
    capture: {
      title: "Invalid Empty",
      source: { url: "https://chatgpt.com/c/invalid" },
      messages: []
    }
  }, outputRoot);
  if (invalid.ok !== false || !/at least one message/u.test(invalid.error ?? "")) {
    throw new Error("Swift host did not reject an empty capture payload.");
  }

  const truncatedBody = Buffer.from(JSON.stringify({
    type: "saveCapture",
    capture: {
      title: "Swift Host Truncated",
      source: { url: "https://chatgpt.com/c/truncated" },
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "truncated framing test" }]
        }
      ]
    }
  }));
  const truncatedHeader = Buffer.alloc(4);
  truncatedHeader.writeUInt32LE(truncatedBody.length + 10, 0);
  const truncated = await sendRawNativeBytes(hostPath, Buffer.concat([truncatedHeader, truncatedBody]), outputRoot);
  if (truncated.ok !== false || !/shorter than declared length/u.test(truncated.error ?? "")) {
    throw new Error("Swift host did not reject truncated native-message input.");
  }

  const trailingBody = Buffer.from(JSON.stringify({
    type: "saveCapture",
    capture: {
      title: "Swift Host Trailing",
      source: { url: "https://chatgpt.com/c/trailing" },
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "trailing framing test" }]
        }
      ]
    }
  }));
  const trailingHeader = Buffer.alloc(4);
  trailingHeader.writeUInt32LE(trailingBody.length, 0);
  const trailing = await sendRawNativeBytes(hostPath, Buffer.concat([trailingHeader, trailingBody, Buffer.from([0])]), outputRoot);
  if (trailing.ok !== false || !/expected exactly one native message/u.test(trailing.error ?? "")) {
    throw new Error("Swift host did not reject trailing native-message input.");
  }

  const anthropic = await sendNativeMessage(hostPath, {
    type: "saveCapture",
    capture: {
      title: "Swift Host Anthropic Warning",
      source: { url: "https://claude.ai/chat/anthropic-key" },
      messages: [
        {
          role: "user",
          content: [{ type: "text", text: "sk-ant-1234567890abcdefghijklmnopqrstuvwxyz" }]
        }
      ]
    }
  }, outputRoot);
  const warningKinds = (anthropic.manifest?.warnings ?? []).map((warning) => warning.kind);
  if (warningKinds.length !== 1 || warningKinds[0] !== "anthropic_api_key") {
    throw new Error(`Swift host misclassified Anthropic warning kinds: ${warningKinds.join(", ")}`);
  }

  const invalidAttachment = await sendNativeMessage(hostPath, {
    type: "saveCapture",
    capture: {
      title: "Swift Host Invalid Attachment",
      source: { url: "https://chatgpt.com/c/invalid-attachment" },
      messages: [
        {
          role: "user",
          content: [
            {
              type: "attachment",
              status: "captured",
              name: "broken.png",
              mimeType: "image/png",
              dataUrl: "not-a-data-url"
            }
          ]
        }
      ]
    }
  }, outputRoot);
  if (!invalidAttachment.ok) throw new Error(invalidAttachment.error ?? "Swift host rejected invalid attachment capture.");
  if (invalidAttachment.manifest.attachments.referenced !== 1) {
    throw new Error("Swift host did not downgrade invalid attachment data URL to referenced.");
  }
  const invalidAttachmentJsonl = await readFile(path.join(invalidAttachment.bundlePath, "messages.jsonl"), "utf8");
  const invalidAttachmentMessage = JSON.parse(invalidAttachmentJsonl.trim());
  const attachment = invalidAttachmentMessage.content[0];
  if (attachment.status !== "referenced" || attachment.dataUrl !== undefined) {
    throw new Error("Swift host preserved invalid attachment data URL.");
  }
  await run("node", ["scripts/validate-bundle.mjs", invalidAttachment.bundlePath]);

  console.log("Swift native host smoke passed.");
} finally {
  await rm(outputRoot, { recursive: true, force: true });
  await rm(configuredRoot, { recursive: true, force: true });
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
      else reject(new Error(`${command} ${args.join(" ")} failed with ${code}\n${Buffer.concat(stdout).toString("utf8")}\n${Buffer.concat(stderr).toString("utf8")}`));
    });
  });
}

async function writeConfig(configFile, captureDirectory) {
  const fs = await import("node:fs/promises");
  await fs.mkdir(path.dirname(configFile), { recursive: true });
  await fs.writeFile(configFile, JSON.stringify({ captureDirectory }, null, 2));
}

async function sendNativeMessage(hostPath, message, outputRoot, configuredRoot) {
  const configFile = configuredRoot ? path.join(await mkdtemp(path.join(os.tmpdir(), "tacket-config-")), "config.json") : null;
  if (configFile) await writeConfig(configFile, configuredRoot);
  const body = Buffer.from(JSON.stringify(message));
  const header = Buffer.alloc(4);
  header.writeUInt32LE(body.length, 0);
  return sendRawNativeBytes(hostPath, Buffer.concat([header, body]), outputRoot, configFile);
}

function sendRawNativeBytes(hostPath, input, outputRoot, configFile) {
  return new Promise((resolve, reject) => {
    const child = spawn(hostPath, {
      stdio: ["pipe", "pipe", "pipe"],
      env: {
        ...process.env,
        ...(configFile ? { TACKET_CONFIG_FILE: configFile } : {}),
        ...(outputRoot ? { TACKET_CAPTURE_DIR: outputRoot } : {})
      }
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", reject);
    child.on("exit", (code) => {
      if (configFile) rm(path.dirname(configFile), { recursive: true, force: true }).catch(() => {});
      if (code !== 0) {
        reject(new Error(`Swift host exited with ${code}: ${Buffer.concat(stderr).toString("utf8")}`));
        return;
      }
      const output = Buffer.concat(stdout);
      const length = output.readUInt32LE(0);
      resolve(JSON.parse(output.subarray(4, 4 + length).toString("utf8")));
    });
    child.stdin.end(input);
  });
}
