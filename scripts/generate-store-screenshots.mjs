import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";

const root = path.resolve(new URL("..", import.meta.url).pathname);
const outDir = path.join(root, "store-assets/chrome-web-store/screenshots");
const chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const width = 1280;
const height = 800;
const iconDataUrl = `data:image/png;base64,${(await readFile(path.join(root, "website/assets/icon-180.png"))).toString("base64")}`;

const scenes = [
  {
    name: "01-capture-popup-1280x800.png",
    eyebrow: "User-click save",
    title: "Save the chat you want, when you click.",
    body: "Tacket saves the current ChatGPT, Claude, or Gemini thread to a private local library on your Mac.",
    mockup: popupMockup()
  },
  {
    name: "02-local-bundle-1280x800.png",
    eyebrow: "Local files",
    title: "Keep every saved chat as files you control.",
    body: "Each Tacket folder contains the readable transcript, structured message data, and local attachment references.",
    mockup: bundleMockup()
  },
  {
    name: "03-local-library-1280x800.png",
    eyebrow: "Local library",
    title: "Search saved chats from one private place.",
    body: "Tacket indexes only the saved chats you add, then lets you open, copy, reveal, or transfer the full transcript.",
    mockup: libraryMockup()
  }
];

await import("node:fs/promises").then((fs) => fs.mkdir(outDir, { recursive: true }));

const tmp = await mkdtemp(path.join(os.tmpdir(), "tacket-store-screenshots-"));
try {
  for (const scene of scenes) {
    const htmlPath = path.join(tmp, scene.name.replace(".png", ".html"));
    const screenshotPath = path.join(outDir, scene.name);
    await writeFile(htmlPath, renderScene(scene), "utf8");
    await run(chromePath, [
      "--headless=new",
      "--disable-gpu",
      "--hide-scrollbars",
      `--window-size=${width},${height}`,
      `--screenshot=${screenshotPath}`,
      `file://${htmlPath}`
    ]);
  }
} finally {
  await rm(tmp, { recursive: true, force: true });
}

console.log(`Generated ${scenes.length} Chrome Web Store screenshots.`);

function renderScene(scene) {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <style>
      :root {
        --bg: #f8f7f4;
        --ink: #151515;
        --muted: #5f6368;
        --line: #ddd8ce;
        --panel: #ffffff;
        --accent: #075a91;
        --tack: #d9c88f;
      }
      * { box-sizing: border-box; }
      body {
        width: 1280px;
        height: 800px;
        margin: 0;
        overflow: hidden;
        color: var(--ink);
        background: var(--bg);
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }
      .top {
        height: 18px;
        background: var(--accent);
      }
      main {
        display: grid;
        grid-template-columns: 0.92fr 1.08fr;
        gap: 54px;
        width: 1120px;
        margin: 70px auto 0;
        align-items: center;
      }
      .brand {
        display: flex;
        gap: 14px;
        align-items: center;
        margin-bottom: 46px;
        font-size: 28px;
        font-weight: 750;
      }
      .icon {
        display: grid;
        width: 48px;
        height: 48px;
        place-items: center;
        border-radius: 10px;
        background: transparent;
        overflow: hidden;
      }
      .icon img {
        display: block;
        width: 48px;
        height: 48px;
      }
      .eyebrow {
        margin: 0 0 16px;
        color: var(--accent);
        font-size: 20px;
        font-weight: 800;
      }
      h1 {
        margin: 0;
        max-width: 520px;
        font-size: 56px;
        line-height: 1.02;
        letter-spacing: 0;
      }
      p {
        max-width: 500px;
        margin: 24px 0 0;
        color: var(--muted);
        font-size: 24px;
        line-height: 1.35;
      }
      .mockup {
        min-height: 560px;
      }
      .window {
        overflow: hidden;
        border: 1px solid var(--line);
        border-radius: 8px;
        background: var(--panel);
      }
      .chrome {
        display: flex;
        gap: 8px;
        align-items: center;
        height: 42px;
        padding: 0 16px;
        border-bottom: 1px solid var(--line);
      }
      .dot { width: 11px; height: 11px; border-radius: 99px; background: var(--line); }
      .bar { height: 12px; border-radius: 99px; background: #ece8df; }
      .content { padding: 26px; }
      .button {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 44px;
        padding: 0 18px;
        border-radius: 6px;
        color: white;
        background: var(--accent);
        font-size: 18px;
        font-weight: 750;
      }
      .muted-button {
        color: var(--ink);
        background: #ece8df;
      }
      .row { display: flex; gap: 12px; align-items: center; }
      .card {
        border: 1px solid var(--line);
        border-radius: 8px;
        background: #fff;
      }
      .code {
        color: #234;
        background: #f1efe8;
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      }
      ${sceneCss()}
    </style>
  </head>
  <body>
    <div class="top"></div>
    <main>
      <section>
        <div class="brand"><div class="icon"><img src="${iconDataUrl}" alt="" /></div><span>Tacket</span></div>
        <p class="eyebrow">${escapeHtml(scene.eyebrow)}</p>
        <h1>${escapeHtml(scene.title)}</h1>
        <p>${escapeHtml(scene.body)}</p>
      </section>
      <section class="mockup">${scene.mockup}</section>
    </main>
  </body>
</html>`;
}

function popupMockup() {
  return `<div class="window popup-window">
    <div class="chrome"><div class="dot"></div><div class="dot"></div><div class="dot"></div><div class="bar grow"></div></div>
    <div class="content">
      <div class="thread card">
        <div class="message user"></div>
        <div class="message assistant wide"></div>
        <div class="message code"></div>
        <div class="message assistant"></div>
      </div>
      <div class="popup card">
        <h2>Tacket</h2>
        <p>Supported source detected.</p>
        <div class="button">Save Conversation</div>
        <div class="fine">Saves locally through the Tacket app</div>
      </div>
    </div>
  </div>`;
}

function bundleMockup() {
  return `<div class="window">
    <div class="chrome"><div class="dot"></div><div class="dot"></div><div class="dot"></div><div class="bar grow"></div></div>
    <div class="content bundle">
      <div class="folder-title">2026-06-01 - ChatGPT - Planning.tacket</div>
      ${fileRow("manifest.json", "source, warnings, counts")}
      ${fileRow("messages.jsonl", "structured message data")}
      ${fileRow("transcript.md", "readable conversation")}
      ${fileRow("attachments/", "captured or referenced files")}
      ${fileRow("targets/codex.md", "paste-ready conversation")}
      <div class="warning">possible_secret warning saved locally, no upload</div>
    </div>
  </div>`;
}

function libraryMockup() {
  return `<div class="window app-window">
    <div class="chrome"><div class="dot"></div><div class="dot"></div><div class="dot"></div><div class="bar grow"></div></div>
    <div class="app">
      <aside>
        <b>Flow</b>
        <span>Save new chats</span>
        <b>Library</b>
        <span class="active">All Tackets</span>
        <span>Search</span>
        <span>Advanced</span>
      </aside>
      <section>
        <div class="search-row">
          <div class="search-field">Search saved chats</div>
          <div class="button">Add Saved Chats</div>
        </div>
        <div class="library-grid">
          <div class="tacket-card selected">
            <strong>Planning Tacket v1</strong>
            <span>ChatGPT · 18 messages</span>
            <div class="snippet"></div>
            <div class="snippet short"></div>
          </div>
          <div class="tacket-card">
            <strong>Claude QA notes</strong>
            <span>Claude · 12 messages</span>
            <div class="snippet"></div>
            <div class="snippet short"></div>
          </div>
          <div class="tacket-card">
            <strong>Gemini research</strong>
            <span>Gemini · 9 messages</span>
            <div class="snippet"></div>
            <div class="snippet short"></div>
          </div>
        </div>
        <div class="action-row">
          <div class="button">Copy Full Text</div>
          <div class="button muted-button">Open</div>
          <div class="button muted-button">Reveal</div>
        </div>
      </section>
    </div>
  </div>`;
}

function fileRow(name, meta) {
  return `<div class="file-row"><strong>${name}</strong><span>${meta}</span></div>`;
}

function sceneCss() {
  return `
    .grow { flex: 1; }
    .popup-window .content { position: relative; min-height: 510px; }
    .thread { padding: 26px; width: 420px; height: 390px; }
    .message { height: 36px; margin-bottom: 24px; border-radius: 8px; background: #ece8df; }
    .message.user { width: 68%; background: var(--accent); }
    .message.assistant { width: 82%; }
    .message.wide { width: 94%; }
    .message.code { width: 78%; height: 78px; }
    .popup { position: absolute; right: 28px; bottom: 28px; width: 260px; padding: 22px; }
    .popup h2, .app h2 { margin: 0 0 10px; font-size: 24px; }
    .popup p { margin: 0 0 18px; font-size: 17px; }
    .fine { margin-top: 16px; color: var(--muted); font-size: 14px; }
    .bundle { padding: 34px; }
    .folder-title { margin-bottom: 22px; font-size: 30px; font-weight: 800; }
    .file-row { display: grid; grid-template-columns: 190px 1fr; gap: 20px; padding: 17px 0; border-bottom: 1px solid var(--line); font-size: 19px; }
    .file-row span { color: var(--muted); }
    .warning { display: inline-flex; margin-top: 24px; padding: 12px 14px; border-radius: 6px; background: #fff5d1; color: #5f4b00; font-weight: 700; }
    .app { display: grid; grid-template-columns: 160px 1fr; min-height: 520px; }
    aside { display: flex; flex-direction: column; gap: 14px; padding: 28px; border-right: 1px solid var(--line); background: #fbfaf7; }
    aside b { margin-top: 12px; color: var(--muted); text-transform: uppercase; font-size: 13px; }
    aside span { font-size: 17px; }
    aside .active { color: var(--accent); font-weight: 800; }
    .app section { padding: 28px; }
    .search-row { display: grid; grid-template-columns: 1fr auto; gap: 14px; margin-bottom: 22px; }
    .search-field { display: flex; align-items: center; min-height: 46px; padding: 0 16px; border: 1px solid var(--line); border-radius: 6px; color: var(--muted); font-size: 17px; }
    .library-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
    .tacket-card { min-height: 132px; padding: 18px; border: 1px solid var(--line); border-radius: 8px; background: #fff; }
    .tacket-card.selected { border-color: var(--accent); box-shadow: inset 4px 0 0 var(--accent); }
    .tacket-card strong { display: block; margin-bottom: 8px; font-size: 18px; }
    .tacket-card span { display: block; margin-bottom: 16px; color: var(--muted); font-size: 15px; }
    .snippet { width: 92%; height: 10px; margin-bottom: 10px; border-radius: 999px; background: #ece8df; }
    .snippet.short { width: 64%; }
    .action-row { display: flex; gap: 12px; margin-top: 22px; }
    .panel { margin-bottom: 22px; padding: 24px; border: 1px solid var(--line); border-radius: 8px; }
    .long { width: 92%; }
    .medium { width: 68%; margin-top: 14px; }
    .progress { width: 72%; height: 10px; margin-top: 24px; background: var(--accent); }
  `;
}

function escapeHtml(value) {
  return value.replace(/[&<>"']/gu, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;"
  }[character]));
}

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    const stderr = [];
    child.stdout.resume();
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} failed with ${code}\n${Buffer.concat(stderr).toString("utf8")}`));
    });
  });
}
