# Changelog

All notable changes to Tacket are documented here.

## 0.1.0 - 2026-06-01

Initial local-first release.

### Added

- Chrome extension save flow for ChatGPT, Claude, and Gemini, initiated only by user click.
- Popup host guard that refuses to save pages outside supported chat domains.
- Local Chrome app connection and packaged Swift local host.
- `.tacket` saved chat format with `manifest.json`, `messages.jsonl`, `transcript.md`, attachments, and target conversation files.
- Local chat library with SQLite full-text search over saved Tacket chat folders.
- Paginated Mac app library browsing for larger local saved-chat collections.
- Advanced local search controls for match mode, search scope, source, and role.
- Full-conversation transfer to clipboard, Codex, and Claude Code, with ordered chunking for long conversations.
- Mac app for local extension setup, save-folder selection, local library search, saved chat review, conversation copy/open, and transfer.
- Codex and Claude desktop app capture from local transcript/session files when available, filtered to user and assistant messages.
- Local desktop app capture previews for ChatGPT desktop and fallback capture using macOS Accessibility with on-device OCR.
- Optional menu bar Quick Capture for starting desktop app capture from the frontmost supported chat app.
- Light, dark, and system appearance modes.
- CLI for native-host install/status/remove, sample bundle generation, and transfer.
- Local possible-secret warnings in saved chat metadata without redacting saved conversation content.
- JSON Schema validation for generated `.tacket` bundles.
- Direct-download packaging for unsigned local builds, DMG layout, extension zip, and SHA-256 checksums.
- Release, testing, privacy, distribution, troubleshooting, Chrome Web Store, security, and contribution docs.

### Known Limitations

- Bulk local imports from Codex App, Claude App, and Claude Code are in the pipeline, but they are not part of the working public release yet.
