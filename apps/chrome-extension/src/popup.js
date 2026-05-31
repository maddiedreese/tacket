const captureButton = document.querySelector("#capture");
const status = document.querySelector("#status");
const result = document.querySelector("#result");

captureButton.addEventListener("click", async () => {
  result.hidden = true;
  result.className = "";
  captureButton.disabled = true;
  status.textContent = "Capturing visible thread content...";

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

    status.textContent = `Captured ${capture.messages.length} messages. Saving locally...`;
    const response = await chrome.runtime.sendMessage({
      type: "TACKET_SAVE_CAPTURE",
      capture
    });

    if (!response?.ok) throw new Error(response?.error ?? "Native host did not save the capture.");

    result.hidden = false;
    result.textContent = `Saved ${capture.messages.length} messages to ${response.bundlePath}`;
    status.textContent = "Capture complete.";
  } catch (error) {
    result.hidden = false;
    result.className = "error";
    result.textContent = error?.message ?? String(error);
    status.textContent = "Capture failed.";
  } finally {
    captureButton.disabled = false;
  }
});

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
