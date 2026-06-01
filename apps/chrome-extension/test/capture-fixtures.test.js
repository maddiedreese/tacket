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
        <section data-testid="conversation-turn-1">
          <article data-message-author-role="user">
            <h4>You said:</h4>
            <div>Hello, transfer this whole thread.</div>
            <img alt="sketch" src="data:image/png;base64,aGVsbG8=">
          </article>
        </section>
        <section data-testid="conversation-turn-2">
          <article data-message-author-role="assistant">
            <h4>ChatGPT said:</h4>
            <p>Use this command.</p>
            <pre class="language-js"><div>JavaScript</div><button>Run</button><code>console.log("raw");</code></pre>
          </article>
        </section>
      </main>
    `
  );

  assert.equal(capture.source.platform, "chatgpt");
  assert.equal(capture.messages.length, 2);
  assert.equal(capture.messages[0].role, "user");
  assert.equal(JSON.stringify(capture.messages.map((message) => message.role)), JSON.stringify(["user", "assistant"]));
  assert.equal(JSON.stringify(capture.messages[1].content.map((part) => part.type)), JSON.stringify(["text", "code"]));
  assert.equal(capture.messages[1].content[1].text, "console.log(\"raw\");");
  assert.equal(capture.messages[1].content[1].language, "js");
  assert.doesNotMatch(JSON.stringify(capture.messages), /You said|ChatGPT said|Run/u);
  assert.equal(capture.messages[0].content.some((part) => part.type === "attachment" && part.status === "captured"), true);
});

test("captures Claude-like user and assistant messages", async () => {
  const capture = await runCapture(
    "https://claude.ai/chat/test",
    `
      <main>
        <div data-testid="user-message">Prioritize full conversation transfer.</div>
        <div data-testid="assistant-message">
          <h2>Claude responded: No summaries in v1…</h2>
          <p>No summaries in v1.</p>
          <pre><code>console.log("claude");</code></pre>
          <a href="https://example.com/context.pdf">context.pdf</a>
          <ol><li><div>Keep order.</div></li></ol>
        </div>
      </main>
    `
  );

  assert.equal(capture.source.platform, "claude");
  assert.equal(JSON.stringify(capture.messages.map((message) => message.role)), JSON.stringify(["user", "assistant"]));
  assert.equal(
    JSON.stringify(capture.messages[1].content.map((part) => part.type)),
    JSON.stringify(["text", "code", "attachment", "text"])
  );
  assert.equal(capture.messages[1].content[1].text, "console.log(\"claude\");");
  assert.doesNotMatch(capture.messages[1].content[0].text, /Claude responded/u);
  assert.equal(capture.messages[1].content.some((part) => part.type === "attachment" && part.name === "context.pdf"), true);
  assert.match(capture.messages[1].content[3].text, /1\. Keep order\./u);
});

test("captures Gemini-like user-query and model-response nodes", async () => {
  const capture = await runCapture(
    "https://gemini.google.com/app/test",
    `
      <main>
        <user-query><h2>You said</h2>Can Tacket include Gemini?</user-query>
        <model-response>
          <h2>Gemini said</h2>
          <p>Yes, Gemini is in v1.</p>
          <div><span>JavaScript</span><pre><code>console.log("gemini");</code></pre></div>
          <ol><li><div>Spacing should survive.</div></li></ol>
        </model-response>
      </main>
    `
  );

  assert.equal(capture.source.platform, "gemini");
  assert.equal(capture.messages.length, 2);
  assert.match(capture.messages[0].content[0].text, /Gemini/);
  assert.doesNotMatch(capture.messages[0].content[0].text, /You said/u);
  assert.equal(
    JSON.stringify(capture.messages[1].content.map((part) => part.type)),
    JSON.stringify(["text", "code", "text"])
  );
  assert.match(capture.messages[1].content[0].text, /Yes, Gemini is in v1\./);
  assert.equal(capture.messages[1].content[1].text, "console.log(\"gemini\");");
  assert.match(capture.messages[1].content[2].text, /1\. Spacing should survive\./u);
  assert.doesNotMatch(JSON.stringify(capture.messages[1]), /Gemini said|JavaScriptYes/u);
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
