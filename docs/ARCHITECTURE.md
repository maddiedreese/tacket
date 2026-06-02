# Architecture

Tacket has three local components that save, index, search, and transfer AI chat conversations without a backend.

## Chrome Extension

The extension runs only on supported AI chat pages:

- ChatGPT: `chatgpt.com`, `chat.openai.com`
- Claude: `claude.ai`
- Gemini: `gemini.google.com`

Saving is user-click only. The extension reads a page when the user opens the popup and clicks **Save Conversation**. It does not run background collection, keep hidden memory, or send chat content over the network.

The extension auto-scrolls the current conversation after the user clicks save, normalizes saved messages into Tacket's chat model, and sends them to the local app through Chrome's native messaging system. Fetchable images are stored as local attachment bytes; other files and images are preserved as references with attachment status.

## Native Host

The native host is a small local process registered with Chrome. The packaged app uses the Swift `TacketNativeHost` executable; the Node host remains available for development. The host receives one saved chat payload at a time, writes a `.tacket` folder to disk, and returns the local path to the extension.

Default development output:

```text
~/Documents/Tacket Captures/
```

The production Mac app owns local Chrome registration, output folder selection, local library indexing/search, and transfer target configuration. The selected save directory is stored locally at:

```text
~/Library/Application Support/Tacket/config.json
```

Both native host implementations read that file before falling back to `~/Documents/Tacket Captures/`. `TACKET_CAPTURE_DIR` can override the save folder in tests, and `TACKET_CONFIG_FILE` can point at an isolated config file for smoke tests.

## Local Library

Tacket treats saved `.tacket` chat folders as the source of truth. The Mac app and CLI can add those folders to a local SQLite database at:

```text
~/Library/Application Support/Tacket/library.sqlite
```

The library uses SQLite FTS5 over saved message text and chat metadata, with local fallback matching when FTS5 is unavailable. Advanced search can switch between exact phrase, all-term, and any-term matching; scope queries to conversation text or titles; and filter by source or message role. It is explicit: users add the save folder or another chosen folder, or click a local agent import button for recent Codex or Claude Code JSONL sessions. Tacket does not silently scan app session stores, summarize conversations, create embeddings, use model/API calls, or sync library data to a backend.

## CLI and Mac App

The Mac app owns the direct-download user workflow:

- browse and search saved Tacket chat folders
- install the local Chrome app connection
- import recent local Codex and Claude Code JSONL sessions into `.tacket` folders
- capture visible text from open desktop chat apps with local macOS Accessibility/OCR
- reveal the local save folder
- choose saved Tacket chats
- copy full saved conversations
- launch Codex or Claude Code and request paste through macOS automation

The CLI remains useful for development and scripted checks:

- render `transcript.md`
- index/search/list local saved Tacket chats
- copy the full saved conversation to the clipboard
- launch Codex or Claude Code in Terminal
- paste the saved conversation using macOS automation when requested

## Data Flow

```text
AI chat page
  -> user clicks Tacket extension
  -> content script extracts messages/assets
  -> extension sends payload to the local app
  -> local app writes a .tacket folder
  -> Mac app/CLI adds the saved chat to local search
  -> CLI/Mac app searches locally or transfers the saved conversation to the chosen target

Codex or Claude Code local JSONL session
  -> user clicks local agent import in the Mac app
  -> Mac app reads recent session files from the user's home folder
  -> Mac app writes .tacket folders
  -> Mac app adds imported chats to local search

Open desktop chat window
  -> user clicks visible desktop capture in the Mac app
  -> Mac app reads visible text locally with Accessibility/OCR
  -> Mac app writes a .tacket folder
  -> Mac app adds the saved chat to local search
```
