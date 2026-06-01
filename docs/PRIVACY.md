# Privacy

Tacket is local-only and local-first by design. It saves raw AI transcripts as local files, indexes them locally only when requested, and transfers exact transcript text only when the user chooses a target.

- No backend
- No analytics
- No telemetry
- No remote crash reports
- No background chat collection
- No model calls
- No summarization

The extension captures content only after the user clicks **Capture This Thread** on a supported AI chat page. The popup checks the active tab host and refuses capture outside ChatGPT, Claude, and Gemini. Captured thread content is sent to the local Tacket app through Chrome Native Messaging, not to a backend service.

The recommended extension install path is the Chrome Web Store. That means Google handles extension distribution and may have normal store/install metadata. It does not change Tacket's capture path: transcript content is sent to the local Tacket app, not to the developer or a Tacket server.

Captured thread content is stored locally in `.tacket` bundles. If a user chooses to place those bundles inside a git repository, normal git hygiene applies. Tacket treats files as user-controlled local artifacts.

When the Library feature is used, Tacket indexes selected `.tacket` bundles into a local SQLite database at `~/Library/Application Support/Tacket/library.sqlite`. The index contains raw transcript text for local full-text search. It does not leave the machine, call a model, create embeddings, or sync anywhere.

Tacket may add local-only warnings to `manifest.json` when captured text appears to contain common token formats such as API keys or private keys. These warnings do not redact, summarize, upload, or otherwise alter the raw transcript.

Tacket stores app preferences locally in `~/Library/Application Support/Tacket/config.json`. This file contains settings such as the selected capture directory; captured thread content remains in user-visible `.tacket` bundles and, if the user indexes them, the local SQLite library.

Tacket's Chrome extension should request the narrowest practical host permissions for supported AI chat domains.

`npm run privacy:verify` is part of `npm run verify`. It checks production runtime files for unapproved telemetry, backend/network APIs, broad extension manifest expansion, and new hardcoded remote endpoints. The only approved runtime network-like operation is the user-clicked capture adapter reading the image `src` from the currently open supported chat page so an image can be preserved locally when the browser permits it.

## macOS Automation

When transferring to Codex or Claude Code, Tacket copies the raw transcript to the local clipboard, opens Terminal, and asks macOS to paste. macOS may show Automation or Accessibility prompts for this action. These permissions are not used for capture, background monitoring, networking, or reading other apps.
