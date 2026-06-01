const captureButton = document.querySelector("#capture");
const status = document.querySelector("#status");
const result = document.querySelector("#result");
const statusText = status.querySelector("span:last-child");

captureButton.addEventListener("click", async () => {
  result.hidden = true;
  result.className = "result";
  captureButton.disabled = true;
  setStatus("Capturing visible thread content...", "working");

  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id) throw new Error("No active tab found.");
    if (!isSupportedChatUrl(tab.url)) {
      throw new Error("Open a ChatGPT, Claude, or Gemini thread before capturing.");
    }

    const [{ result: capture }] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ["src/adapters/capture.js"]
    });

    if (!capture?.messages?.length) {
      throw new Error("Tacket could not find messages on this page.");
    }

    setStatus(`Captured ${capture.messages.length} messages. Saving locally...`, "working");
    const response = await chrome.runtime.sendMessage({
      type: "TACKET_SAVE_CAPTURE",
      capture
    });

    if (!response?.ok) throw new Error(response?.error ?? "Native host did not save the capture.");

    result.hidden = false;
    result.className = "result success";
    result.replaceChildren(
      element("strong", "Saved locally"),
      document.createTextNode(`${capture.messages.length} messages written to ${response.bundlePath}`)
    );
    setStatus("Capture complete.", "success");
  } catch (error) {
    result.hidden = false;
    result.className = "result error";
    result.replaceChildren(
      element("strong", "Capture failed"),
      document.createTextNode(error?.message ?? String(error))
    );
    setStatus("Capture failed.", "error");
  } finally {
    captureButton.disabled = false;
  }
});

function setStatus(message, state = "idle") {
  status.dataset.state = state;
  statusText.textContent = message;
}

function element(tagName, text) {
  const node = document.createElement(tagName);
  node.textContent = text;
  return node;
}

function isSupportedChatUrl(value) {
  try {
    const url = new URL(value);
    if (url.protocol === "file:" && manifestAllowsFileUrls()) return true;
    const host = url.hostname;
    return host === "chatgpt.com" ||
      host === "chat.openai.com" ||
      host === "claude.ai" ||
      host === "gemini.google.com";
  } catch {
    return false;
  }
}

function manifestAllowsFileUrls() {
  return chrome.runtime.getManifest().host_permissions?.includes("file:///*") === true;
}
