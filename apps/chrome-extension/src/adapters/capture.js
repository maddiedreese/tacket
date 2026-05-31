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
    const nodes = uniqueElements([
      ...document.querySelectorAll("[data-message-author-role]"),
      ...document.querySelectorAll("[data-testid^='conversation-turn']")
    ]);

    const messages = await Promise.all(nodes.map((node, index) => {
      const role = normalizeRole(node.getAttribute("data-message-author-role") ?? guessRole(node, index));
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
    const seenText = new Set();
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT, {
      acceptNode(node) {
        if (node.matches?.("button, nav, menu, svg, style, script")) return NodeFilter.FILTER_REJECT;
        if (node.matches?.("pre, code, img, a[href], [data-testid*='attachment'], [aria-label*='attachment' i]")) {
          return NodeFilter.FILTER_ACCEPT;
        }
        return NodeFilter.FILTER_SKIP;
      }
    });

    let current;
    while ((current = walker.nextNode())) {
      if (current.matches("pre")) {
        const text = current.innerText.trimEnd();
        if (text && !seenText.has(text)) {
          seenText.add(text);
          parts.push({ type: "code", text, language: languageFromPre(current) });
        }
      } else if (current.matches("img")) {
        const attachment = await attachmentFromImage(current);
        if (attachment) parts.push(attachment);
      } else if (current.matches("a[href]") && looksLikeAttachment(current)) {
        parts.push({
          type: "attachment",
          status: "referenced",
          name: current.textContent.trim() || "link",
          url: current.href
        });
      }
    }

    const text = textWithoutCode(root);
    if (text) parts.unshift({ type: "text", text });
    return dedupeParts(parts);
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

  function textWithoutCode(root) {
    const clone = root.cloneNode(true);
    clone.querySelectorAll("pre, code, button, nav, menu, svg, style, script").forEach((node) => node.remove());
    return clone.innerText
      .replace(/\n{3,}/gu, "\n\n")
      .replace(/^\s*(Copy|Edit|Share|Retry|Like|Dislike)\s*$/gimu, "")
      .trim();
  }

  function languageFromPre(pre) {
    const className = pre.className || pre.querySelector("code")?.className || "";
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
      if ([...seen].some((other) => other.contains(node))) return false;
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
