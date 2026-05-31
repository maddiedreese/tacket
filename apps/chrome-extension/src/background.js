const HOST_NAME = "dev.tacket.host";

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "TACKET_SAVE_CAPTURE") return false;

  chrome.runtime.sendNativeMessage(
    HOST_NAME,
    {
      type: "saveCapture",
      capture: message.capture
    },
    (response) => {
      const error = chrome.runtime.lastError;
      if (error) {
        sendResponse({ ok: false, error: error.message });
        return;
      }
      sendResponse(response ?? { ok: false, error: "No response from Tacket host." });
    }
  );

  return true;
});
