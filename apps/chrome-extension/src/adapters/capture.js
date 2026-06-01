(async () => {
  const url = location.href;
  const platform = detectPlatform(location.hostname);

  return {
    title: document.title.replace(/\s[|-]\s(ChatGPT|Claude|Gemini).*$/u, "").trim() || document.title,
    source: {
      platform,
      url
    },
    capturedAt: new Date().toISOString(),
    messages: await captureMessages(platform)
  };

  function detectPlatform(hostname) {
    if (hostname === "chatgpt.com" || hostname === "chat.openai.com") return "chatgpt";
    if (hostname === "claude.ai") return "claude";
    if (hostname === "gemini.google.com") return "gemini";
    return "unknown";
  }

  async function captureMessages(currentPlatform) {
    const captureCurrent = () => {
      if (currentPlatform === "chatgpt") return captureChatGpt();
      if (currentPlatform === "claude") return captureClaude();
      if (currentPlatform === "gemini") return captureGemini();
      return captureGeneric();
    };
    return captureAcrossScroll(captureCurrent);
  }

  async function captureChatGpt() {
    const roleNodes = [...document.querySelectorAll("[data-message-author-role]")];
    const nodes = roleNodes.length > 0
      ? uniqueElements(roleNodes)
      : uniqueElements([...document.querySelectorAll("[data-testid^='conversation-turn']")]);

    const messages = await Promise.all(nodes.map((node, index) => {
      const role = normalizeRole(
        node.getAttribute("data-message-author-role") ??
        node.querySelector("[data-message-author-role]")?.getAttribute("data-message-author-role") ??
        guessRole(node, index)
      );
      return messageFromNode(node, role, "chatgpt", index);
    }));
    return messages.filter(hasContent);
  }

  async function captureClaude() {
    const nodes = uniqueElements([
      ...document.querySelectorAll("[data-testid='user-message']"),
      ...document.querySelectorAll("[data-testid='assistant-message']"),
      ...document.querySelectorAll("[data-is-streaming]")
    ]);

    const messages = await Promise.all(nodes.map((node, index) => {
      const testId = node.getAttribute("data-testid") ?? "";
      const role = testId.includes("user") ? "user" : testId.includes("assistant") ? "assistant" : guessRole(node, index);
      return messageFromNode(node, role, "claude", index);
    }));
    return messages.filter(hasContent);
  }

  async function captureGemini() {
    const nodes = uniqueElements([
      ...document.querySelectorAll("user-query"),
      ...document.querySelectorAll("model-response"),
      ...document.querySelectorAll("[data-response-index]"),
      ...document.querySelectorAll(".conversation-container [id^='message-content']")
    ]);

    const messages = await Promise.all(nodes.map((node, index) => {
      const tag = node.tagName.toLowerCase();
      const role = tag === "user-query" ? "user" : tag === "model-response" ? "assistant" : guessRole(node, index);
      return messageFromNode(node, role, "gemini", index);
    }));
    return messages.filter(hasContent);
  }

  async function captureGeneric() {
    const nodes = uniqueElements([
      ...document.querySelectorAll("main article"),
      ...document.querySelectorAll("[role='article']"),
      ...document.querySelectorAll("main [data-testid]")
    ]);
    const messages = await Promise.all(
      nodes.map((node, index) => messageFromNode(node, guessRole(node, index), "unknown", index))
    );
    return messages.filter(hasContent);
  }

  async function captureAcrossScroll(captureCurrent) {
    const scroller = findScrollContainer();
    const originalTop = scroller === document.scrollingElement ? window.scrollY : scroller.scrollTop;
    const merged = new Map();

    try {
      setScrollTop(scroller, 0);
      await sleep(250);

      let previousTop = -1;
      for (let step = 0; step < 80; step += 1) {
        for (const message of await captureCurrent()) {
          merged.set(signatureFor(message), message);
        }

        const currentTop = getScrollTop(scroller);
        const maxTop = getMaxScrollTop(scroller);
        if (currentTop >= maxTop - 8 || currentTop === previousTop) break;
        previousTop = currentTop;
        setScrollTop(scroller, Math.min(maxTop, currentTop + Math.max(360, getViewportHeight(scroller) * 0.75)));
        await sleep(180);
      }
    } finally {
      setScrollTop(scroller, originalTop);
    }

    return [...merged.values()].map((message, index) => ({
      ...message,
      id: `${message.source.platform}-${index + 1}`
    }));
  }

  function findScrollContainer() {
    const candidates = [
      document.querySelector("main"),
      document.querySelector("[class*='conversation']"),
      document.scrollingElement,
      document.documentElement
    ].filter(Boolean);

    for (const candidate of candidates) {
      if (candidate.scrollHeight > candidate.clientHeight + 120) return candidate;
    }
    return document.scrollingElement || document.documentElement;
  }

  function getScrollTop(scroller) {
    return scroller === document.scrollingElement ? window.scrollY : scroller.scrollTop;
  }

  function setScrollTop(scroller, top) {
    if (scroller === document.scrollingElement) window.scrollTo({ top, behavior: "instant" });
    else scroller.scrollTop = top;
  }

  function getMaxScrollTop(scroller) {
    if (scroller === document.scrollingElement) {
      return Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
    }
    return Math.max(0, scroller.scrollHeight - scroller.clientHeight);
  }

  function getViewportHeight(scroller) {
    return scroller === document.scrollingElement ? window.innerHeight : scroller.clientHeight;
  }

  function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  async function messageFromNode(node, role, sourcePlatform, index) {
    return {
      id: `${sourcePlatform}-${index + 1}`,
      role,
      content: await extractParts(node),
      source: {
        platform: sourcePlatform,
        url,
        selector: selectorFor(node)
      }
    };
  }

  async function extractParts(root) {
    const parts = [];
    const textBuffer = [];
    const seenText = new Set();

    const flushText = () => {
      const text = normalizeCapturedText(textBuffer.join(""));
      textBuffer.length = 0;
      if (text && !seenText.has(text)) {
        seenText.add(text);
        parts.push({ type: "text", text });
      }
    };

    const visit = async (node) => {
      if (node.nodeType === Node.TEXT_NODE) {
        appendText(textBuffer, node.nodeValue ?? "");
        return;
      }
      if (!(node instanceof Element)) return;
      if (shouldSkipElement(node)) return;

      if (node.matches("pre")) {
        flushText();
        const text = codeTextFrom(node);
        if (text && !seenText.has(`code:${text}`)) {
          seenText.add(`code:${text}`);
          parts.push({ type: "code", text, language: languageFromCode(node) });
        }
        return;
      }

      if (node.matches("code")) {
        flushText();
        const text = codeTextFrom(node);
        if (text && !seenText.has(`code:${text}`)) {
          seenText.add(`code:${text}`);
          parts.push({ type: "code", text, language: languageFromCode(node) });
        }
        return;
      }

      if (node.matches("img")) {
        flushText();
        const attachment = await attachmentFromImage(node);
        if (attachment) parts.push(attachment);
        return;
      }

      if (node.matches("a[href]") && looksLikeAttachment(node)) {
        flushText();
        parts.push({
          type: "attachment",
          status: "referenced",
          name: node.textContent.trim() || "link",
          url: node.href
        });
        return;
      }

      if (node.matches("li")) {
        const marker = listMarkerFor(node);
        textBuffer.push("\n");
        if (marker) textBuffer.push(marker);
        for (const child of node.childNodes) await visitListItemChild(child);
        textBuffer.push("\n");
        return;
      }

      const block = isBlockish(node);
      if (block) textBuffer.push("\n");
      for (const child of node.childNodes) await visit(child);
      if (block) textBuffer.push("\n");
    };

    for (const child of root.childNodes) await visit(child);
    flushText();
    return dedupeParts(parts);

    async function visitListItemChild(child) {
      if (
        child instanceof Element &&
        isBlockish(child) &&
        !child.matches("pre, code, img, a[href], li")
      ) {
        for (const grandchild of child.childNodes) await visit(grandchild);
        return;
      }
      await visit(child);
    }
  }

  async function attachmentFromImage(image) {
    const src = image.currentSrc || image.src;
    if (!src) return null;

    const base = {
      type: "attachment",
      name: image.alt || image.getAttribute("aria-label") || "image",
      mimeType: "image/*",
      url: src,
      alt: image.alt || undefined
    };

    if (src.startsWith("data:")) {
      return {
        ...base,
        status: "captured",
        mimeType: src.slice(5, src.indexOf(";")) || "image/*",
        dataUrl: src
      };
    }

    try {
      const response = await fetch(src);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const blob = await response.blob();
      return {
        ...base,
        status: "captured",
        mimeType: blob.type || "image/*",
        dataUrl: await blobToDataUrl(blob)
      };
    } catch {
      return {
        ...base,
        status: "referenced"
      };
    }
  }

  function blobToDataUrl(blob) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(blob);
    });
  }

  function shouldSkipElement(node) {
    if (node.matches("button, nav, menu, svg, style, script, noscript, textarea, input, select")) return true;
    if (node.getAttribute("aria-hidden") === "true") return true;
    if (node.matches("h1, h2, h3, h4, h5, h6, [role='heading']") && isUiLabel(node.textContent)) return true;
    if (isCodeLabel(node)) return true;
    return false;
  }

  function isUiLabel(value) {
    const text = normalizeCapturedText(value ?? "");
    return /^(You said:?|ChatGPT said:?|Claude responded:?|Gemini said:?|Conversation with Gemini)$/iu.test(text) ||
      /^You said:/iu.test(text) ||
      /^(ChatGPT|Claude|Gemini) (said|responded):/iu.test(text);
  }

  function isCodeLabel(node) {
    const text = normalizeCapturedText(node.textContent ?? "");
    if (!/^(JavaScript|TypeScript|Python|Swift|Shell|Bash|JSON|HTML|CSS|JS|TS)$/iu.test(text)) return false;
    const parent = node.parentElement;
    return parent?.querySelector("pre, code") !== null;
  }

  function isBlockish(node) {
    return /^(ARTICLE|ASIDE|BLOCKQUOTE|DD|DIV|DL|DT|FIGCAPTION|FIGURE|FOOTER|HEADER|MAIN|OL|P|PRE|SECTION|TABLE|TBODY|TD|TH|THEAD|TR|UL|USER-QUERY|MODEL-RESPONSE)$/u.test(node.tagName) ||
      node.getAttribute("role") === "paragraph" ||
      node.getAttribute("role") === "listitem";
  }

  function listMarkerFor(item) {
    const parent = item.parentElement;
    if (parent?.matches("ol")) {
      const start = Number.parseInt(parent.getAttribute("start") ?? "1", 10);
      const siblings = [...parent.children].filter((child) => child.matches("li"));
      const index = siblings.indexOf(item);
      return `${Number.isFinite(start) ? start + index : index + 1}. `;
    }
    if (parent?.matches("ul")) return "- ";
    return "";
  }

  function appendText(buffer, value) {
    const text = value.replace(/\s+/gu, " ");
    if (isUiLabel(text)) return;
    if (!text.trim()) {
      if (buffer.length > 0 && !/\s$/u.test(buffer.at(-1) ?? "")) buffer.push(" ");
      return;
    }
    if (buffer.length > 0 && !/[\s([]$/u.test(buffer.at(-1) ?? "") && !/^[.,;:!?)]/u.test(text)) {
      buffer.push(" ");
    }
    buffer.push(text);
  }

  function normalizeCapturedText(value) {
    return String(value)
      .replace(/[ \t]*\n[ \t]*/gu, "\n")
      .replace(/[ \t]{2,}/gu, " ")
      .replace(/\n{3,}/gu, "\n\n")
      .replace(/^\s*(Copy|Edit|Share|Retry|Like|Dislike|Good response|Bad response|Redo|Download code|Copy code|Run)\s*$/gimu, "")
      .replace(/\n{3,}/gu, "\n\n")
      .trim();
  }

  function codeTextFrom(node) {
    const code = node.matches("pre") ? node.querySelector("code") : node;
    return (code?.innerText ?? code?.textContent ?? node.innerText ?? node.textContent ?? "").trimEnd();
  }

  function languageFromCode(node) {
    const code = node.matches("pre") ? node.querySelector("code") : node;
    const className = node.className || code?.className || "";
    const match = String(className).match(/language-([a-z0-9_+-]+)/iu);
    return match?.[1]?.toLowerCase();
  }

  function looksLikeAttachment(anchor) {
    const text = anchor.textContent.toLowerCase();
    const href = anchor.href.toLowerCase();
    return /\.(pdf|png|jpe?g|gif|webp|txt|md|csv|json|zip|docx?|xlsx?)($|[?#])/u.test(href) ||
      /(download|attachment|uploaded|file)/u.test(text);
  }

  function guessRole(node, index) {
    const text = [
      node.getAttribute("aria-label"),
      node.getAttribute("data-testid"),
      node.className,
      node.closest("[aria-label]")?.getAttribute("aria-label")
    ].join(" ").toLowerCase();
    if (/(user|you|human)/u.test(text)) return "user";
    if (/(assistant|model|response|claude|chatgpt|gemini)/u.test(text)) return "assistant";
    return index % 2 === 0 ? "user" : "assistant";
  }

  function normalizeRole(role) {
    if (role === "user" || role === "assistant" || role === "system" || role === "tool") return role;
    return "unknown";
  }

  function hasContent(message) {
    return message.content.some((part) => part.type === "attachment" || part.text?.trim());
  }

  function uniqueElements(nodes) {
    const seen = new Set();
    return nodes.filter((node) => {
      if (!(node instanceof Element)) return false;
      if (seen.has(node)) return false;
      if ([...seen].some((other) => other.contains(node) || node.contains(other))) return false;
      seen.add(node);
      return true;
    });
  }

  function dedupeParts(parts) {
    const seen = new Set();
    return parts.filter((part) => {
      const key = JSON.stringify(part);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }

  function selectorFor(node) {
    if (node.id) return `#${CSS.escape(node.id)}`;
    const attr = ["data-testid", "data-message-author-role", "data-response-index"]
      .map((name) => node.getAttribute(name) ? `[${name}="${CSS.escape(node.getAttribute(name))}"]` : null)
      .find(Boolean);
    if (attr) return `${node.tagName.toLowerCase()}${attr}`;
    return node.tagName.toLowerCase();
  }

  function signatureFor(message) {
    const role = message.role;
    const text = message.content
      .map((part) => part.text ?? part.url ?? part.path ?? part.name ?? "")
      .join("\n")
      .replace(/\s+/gu, " ")
      .trim()
      .slice(0, 400);
    return `${role}:${text}`;
  }
})();
