import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { JSDOM } from "jsdom";

const script = await readFile(new URL("../src/adapters/capture.js", import.meta.url), "utf8");

test("captures ChatGPT-like turns with code and data URL images", async () => {
  const capture = await runCapture(
    "https://chatgpt.com/c/test",
    `
      <main>
        <article data-message-author-role="user">
          <div>Hello, transfer this whole thread.</div>
          <img alt="sketch" src="data:image/png;base64,aGVsbG8=">
        </article>
        <article data-message-author-role="assistant">
          <p>Use this command.</p>
          <pre class="language-js">console.log("raw");</pre>
        </article>
      </main>
    `
  );

  assert.equal(capture.source.platform, "chatgpt");
  assert.equal(capture.messages.length, 2);
  assert.equal(capture.messages[0].role, "user");
  assert.equal(capture.messages[1].content.some((part) => part.type === "code" && part.language === "js"), true);
  assert.equal(capture.messages[0].content.some((part) => part.type === "attachment" && part.status === "captured"), true);
});

test("captures Claude-like user and assistant messages", async () => {
  const capture = await runCapture(
    "https://claude.ai/chat/test",
    `
      <main>
        <div data-testid="user-message">Prioritize raw transcript transfer.</div>
        <div data-testid="assistant-message">
          <p>No summaries in v1.</p>
          <a href="https://example.com/context.pdf">context.pdf</a>
        </div>
      </main>
    `
  );

  assert.equal(capture.source.platform, "claude");
  assert.equal(JSON.stringify(capture.messages.map((message) => message.role)), JSON.stringify(["user", "assistant"]));
  assert.equal(capture.messages[1].content.some((part) => part.type === "attachment" && part.name === "context.pdf"), true);
});

test("captures Gemini-like user-query and model-response nodes", async () => {
  const capture = await runCapture(
    "https://gemini.google.com/app/test",
    `
      <main>
        <user-query>Can Tacket include Gemini?</user-query>
        <model-response>Yes, Gemini is in v1.</model-response>
      </main>
    `
  );

  assert.equal(capture.source.platform, "gemini");
  assert.equal(capture.messages.length, 2);
  assert.match(capture.messages[0].content[0].text, /Gemini/);
  assert.match(capture.messages[1].content[0].text, /v1/);
});

async function runCapture(url, body) {
  const dom = new JSDOM(`<!doctype html><title>Tacket Fixture</title>${body}`, {
    url,
    pretendToBeVisual: true,
    runScripts: "outside-only"
  });

  const { window } = dom;
  window.scrollTo = (_options) => {};
  window.fetch = async () => {
    throw new Error("Network disabled in capture fixtures.");
  };
  window.CSS ??= { escape: (value) => String(value).replace(/"/gu, '\\"') };

  Object.defineProperty(window.HTMLElement.prototype, "innerText", {
    configurable: true,
    get() {
      return this.textContent;
    }
  });

  return window.eval(script);
}
