# Architecture

Tacket has three local components that save, index, search, and transfer raw AI transcripts without a backend.

## Chrome Extension

The extension runs only on supported AI chat pages:

- ChatGPT: `chatgpt.com`, `chat.openai.com`
- Claude: `claude.ai`
- Gemini: `gemini.google.com`

Capture is user-click only. The extension reads a page when the user opens the popup and clicks **Capture This Thread**. It does not run background collection, keep hidden memory, or send chat content over the network.

The extension auto-scrolls the current conversation after the user clicks capture, normalizes captured messages into Tacket's thread model, and sends them to the local native host using Chrome Native Messaging. Fetchable images are stored as local attachment bytes; other files and images are preserved as references with capture status.

## Native Host

The native host is a small local process registered with Chrome. The packaged app uses the Swift `TacketNativeHost` executable; the Node host remains available for development. The host receives one capture payload at a time, writes a `.tacket` bundle to disk, and returns the local path to the extension.

Default development output:

```text
~/Documents/Tacket Captures/
```

The production Mac app owns host registration, output folder selection, local library indexing/search, and transfer target configuration. The selected capture directory is stored locally at:

```text
~/Library/Application Support/Tacket/config.json
```

Both native host implementations read that file before falling back to `~/Documents/Tacket Captures/`. `TACKET_CAPTURE_DIR` can override the capture folder in tests, and `TACKET_CONFIG_FILE` can point at an isolated config file for smoke tests.

## Local Library

Tacket treats `.tacket` bundles as the source of truth. The Mac app and CLI can index those bundles into a local SQLite database at:

```text
~/Library/Application Support/Tacket/library.sqlite
```

The library uses SQLite FTS5 over raw message text and bundle metadata, with local fallback matching when FTS5 is unavailable. Advanced search can switch between exact phrase, all-term, and any-term matching; scope queries to transcript text or titles; and filter by source or message role. It is explicit: users index the capture folder or another chosen folder. Tacket does not silently scan app session stores, summarize transcripts, create embeddings, use model/API calls, or sync library data to a backend.

## CLI and Mac App

The Mac app owns the direct-download user workflow:

- index and search saved `.tacket` transcript bundles
- install the Chrome native messaging manifest
- reveal the local capture folder
- choose `.tacket` bundles
- copy raw transcripts
- launch Codex or Claude Code and request paste through macOS automation

The CLI remains useful for development and scripted checks:

- render raw `transcript.md`
- index/search/list local `.tacket` bundles
- copy raw transcript to the clipboard
- launch Codex or Claude Code in Terminal
- paste the transcript using macOS automation when requested

## Data Flow

```text
AI chat page
  -> user clicks Tacket extension
  -> content script extracts messages/assets
  -> extension sends payload to native host
  -> native host writes .tacket bundle
  -> Mac app/CLI indexes raw transcript locally
  -> CLI/Mac app searches locally or transfers raw transcript to the chosen target
```
