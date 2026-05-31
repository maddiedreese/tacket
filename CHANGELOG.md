# Changelog

All notable changes to Tacket are documented here.

## 0.1.0 - Unreleased

Initial local-first v1.

### Added

- Chrome extension capture for ChatGPT, Claude, and Gemini, initiated only by user click.
- Popup host guard that refuses capture outside supported chat domains.
- Local Chrome Native Messaging bridge and packaged Swift native host.
- `.tacket` bundle format with `manifest.json`, `messages.jsonl`, `transcript.md`, attachments, and target transcripts.
- Raw transcript transfer to clipboard, Codex, and Claude Code, with ordered chunking for long transcripts.
- Mac app for connector setup, capture-folder selection, bundle review, transcript copy/open, and transfer.
- CLI for native-host install/status/remove, sample bundle generation, and transfer.
- Local possible-secret warnings in bundle manifests without redacting raw transcript content.
- JSON Schema validation for generated `.tacket` bundles.
- Direct-download packaging for unsigned local builds, DMG layout, extension zip, and SHA-256 checksums.
- Release, testing, privacy, distribution, troubleshooting, Chrome Web Store, security, and contribution docs.
