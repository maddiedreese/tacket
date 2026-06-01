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

The recommended extension install path is the Chrome Web Store. That means Google handles extension distribution and may have normal store/install metadata. It does not change Tacket's save path: chat content is sent to the local Tacket app, not to the developer or a Tacket server.

Saved chat content is stored locally in user-controlled folders. If a user chooses to place those folders inside a git repository, normal git hygiene applies.

When the Library feature is used, Tacket builds a local search index from the saved chats the user chooses. The index contains conversation text for local search. It does not leave the machine, call a model, create embeddings, or sync anywhere.

Tacket may add local-only warnings when saved text appears to contain common token formats such as API keys or private keys. These warnings do not redact, summarize, upload, or otherwise alter the saved conversation.

Tacket stores app preferences locally in `~/Library/Application Support/Tacket/config.json`. This file contains settings such as the selected save folder; saved chat content remains in user-visible local folders and, if the user indexes them, the local search library.

Tacket's Chrome extension should request the narrowest practical host permissions for supported AI chat domains.

`npm run privacy:verify` is part of `npm run verify`. It checks production runtime files for unapproved telemetry, backend/network APIs, broad extension manifest expansion, and new hardcoded remote endpoints. The only approved runtime network-like operation is the user-clicked capture adapter reading the image `src` from the currently open supported chat page so an image can be preserved locally when the browser permits it.

## macOS Automation

When transferring to Codex or Claude Code, Tacket copies the saved conversation to the local clipboard, opens Terminal, and asks macOS to paste. macOS may show Automation or Accessibility prompts for this action. These permissions are not used for saving chats, background monitoring, networking, or reading other apps.
