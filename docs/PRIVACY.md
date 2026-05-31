# Privacy

Tacket is local-only and local-first by design.

- No backend
- No analytics
- No telemetry
- No remote crash reports
- No background chat collection
- No model calls
- No summarization

The extension captures content only after the user clicks **Capture This Thread** on a supported AI chat page. The popup checks the active tab host and refuses capture outside ChatGPT, Claude, and Gemini. Captured thread content is sent to the local Tacket app through Chrome Native Messaging, not to a backend service.

Captured thread content is stored locally in `.tacket` bundles. If a user chooses to place those bundles inside a git repository, normal git hygiene applies. Future versions may add secret detection before writing to repo folders, but v1 treats files as user-controlled local artifacts.

Tacket may add local-only warnings to `manifest.json` when captured text appears to contain common token formats such as API keys or private keys. These warnings do not redact, summarize, upload, or otherwise alter the raw transcript.

Tacket stores app preferences locally in `~/Library/Application Support/Tacket/config.json`. This file contains settings such as the selected capture directory; it does not contain captured thread content.

Tacket's Chrome extension should request the narrowest practical host permissions for supported AI chat domains.

## macOS Automation

When transferring to Codex or Claude Code, Tacket copies the raw transcript to the local clipboard, opens Terminal, and asks macOS to paste. macOS may show Automation or Accessibility prompts for this action. These permissions are not used for capture, background monitoring, networking, or reading other apps.
