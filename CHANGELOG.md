# Changelog

All notable changes to Tacket are documented here.

## 0.1.0 - 2026-06-01

Initial local-first v1.

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
- Exact local transcript import for Codex App, Claude App, and Claude Code sessions.
- Local desktop app capture previews for ChatGPT, Claude, and Codex desktop apps using macOS Accessibility with on-device OCR fallback.
- Optional menu bar Quick Capture for starting desktop app previews from the frontmost supported chat app.
- Light, dark, and system appearance modes.
- CLI for native-host install/status/remove, sample bundle generation, and transfer.
- Local possible-secret warnings in saved chat metadata without redacting saved conversation content.
- JSON Schema validation for generated `.tacket` bundles.
- Direct-download packaging for unsigned local builds, DMG layout, extension zip, and SHA-256 checksums.
- Release, testing, privacy, distribution, troubleshooting, Chrome Web Store, security, and contribution docs.
