# Privacy

Tacket is local-only and local-first by design. It saves AI chat conversations as local files, makes them searchable on your Mac only when requested, and copies or transfers the full conversation only when the user chooses a target.

- No backend
- No analytics
- No telemetry
- No remote crash reports
- No background chat collection
- No model calls
- No summarization

The extension saves content only after the user clicks the extension on a supported AI chat page. The popup checks the active tab and refuses to save pages outside ChatGPT, Claude, and Gemini. The saved conversation is sent to the local Tacket app, not to a backend service.

The Mac app can also capture the current open ChatGPT, Claude, and Codex desktop app chat. For Codex and Claude desktop chats, Tacket first saves the local transcript/session file when available and filters the saved output to user and assistant messages. For ChatGPT desktop, or when a local transcript is not available, Tacket scrolls the app window locally, reads text exposed through macOS Accessibility, and falls back to on-device OCR when needed. The fallback path shows captured text in a local preview before saving. It does not call a model, upload screenshots, send chat text to a server, or monitor apps in the background.

The optional menu bar Quick Capture feature is only a faster user-triggered way to start the same desktop capture flow. It does not watch the frontmost app continuously, capture in the background, or save without a user click.

The recommended extension install path is the Chrome Web Store. That means Google handles extension distribution and may have normal store/install metadata. It does not change Tacket's save path: chat content is sent to the local Tacket app, not to the developer or a Tacket server.

Saved chat content is stored locally in user-controlled folders. If a user chooses to place those folders inside a git repository, normal git hygiene applies.

When the Library feature is used, Tacket builds a local search index from the saved chats the user chooses. The index contains conversation text for local search. It does not leave the machine, call a model, create embeddings, or sync anywhere.

Tacket may add local-only warnings when saved text appears to contain common token formats such as API keys or private keys. These warnings do not redact, summarize, upload, or otherwise alter the saved conversation.

Tacket stores app preferences locally in `~/Library/Application Support/Tacket/config.json`. This file contains settings such as the selected save folder; saved chat content remains in user-visible local folders and, if the user indexes them, the local search library.

Tacket's Chrome extension should request the narrowest practical host permissions for supported AI chat domains.

`npm run privacy:verify` is part of `npm run verify`. It checks production runtime files for unapproved telemetry, backend/network APIs, broad extension manifest expansion, and new hardcoded remote endpoints. The only approved runtime network-like operation is the user-clicked capture adapter reading the image `src` from the currently open supported chat page so an image can be preserved locally when the browser permits it.

## macOS Automation

When transferring to Codex or Claude Code, Tacket copies the saved conversation to the local clipboard, opens Terminal, and asks macOS to paste. macOS may show Automation or Accessibility prompts for this action. These permissions are not used for saving chats, background monitoring, networking, or reading other apps.

## macOS Desktop Capture Permissions

When saving from a desktop app, Tacket may ask for Accessibility or Screen Recording permission if it needs the preview fallback. Accessibility lets Tacket read text exposed by the open app window and drive local scroll-and-read capture. Screen Recording lets Tacket use on-device OCR when an app does not expose enough text through Accessibility. Captured fallback text is shown in Tacket for review before it is written to local `.tacket` files. Codex and Claude local transcript saves do not need those permissions when the local transcript is available.

## Planned Local Agent Transcript Import

Bulk imports from Codex App, Claude App, and Claude Code are in the pipeline, but they are not part of the current working public release. Current Codex and Claude desktop capture is user-clicked capture of the current app/chat, not background library scanning. When bulk import is enabled, it should read only local session data after the user clicks import, avoid background scanning, avoid model/API calls, and write normal local `.tacket` folders.

ChatGPT desktop app chats use the desktop capture path. Tacket does not decrypt, access, or import ChatGPT's private app cache.
