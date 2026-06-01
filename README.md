# Tacket

Tacket is a private local library for AI and agent transcripts.

It is a local-first Mac app with a Chrome extension for ChatGPT, Claude, and Gemini. Click the extension on a supported chat page, save the full thread as a local `.tacket` bundle, search the raw transcript later, then transfer the exact conversation to Clipboard, Codex, or Claude Code when you need it.

Tacket will always be free and open source. It has no accounts, no analytics, no telemetry, and no backend that can see your chats.

## What It Does

- Captures supported AI chats only after you click the extension.
- Saves readable local bundles in `~/Documents/Tacket Captures`.
- Indexes saved `.tacket` bundles into a local SQLite search library.
- Preserves the raw transcript as Markdown and structured JSONL.
- Searches saved chats, code snippets, decisions, and errors without sending them anywhere.
- Transfers exact raw transcripts to Clipboard, Codex, or Claude Code.
- Uses no backend, no analytics, no telemetry, and no model/API calls.

Tacket is not an agent harness. It does not run agents for you or reach into private app session stores.

## Install

Public releases will be the shortest path:

1. Download `Tacket.dmg` from the [latest release](https://github.com/maddiedreese/tacket/releases).
2. Open the DMG and drag Tacket into Applications.
3. Add the Tacket Chrome extension.
4. Open Tacket once so it can install its local Chrome connector.

You can also build it from source:

```bash
npm install
npm run package:release
open dist/Tacket.app
```

Then load `apps/chrome-extension` as an unpacked Chrome extension and install the connector:

```bash
node apps/cli/bin/tacket.js install-native-host --extension-id <chrome-extension-id>
```

## Use

1. Open a ChatGPT, Claude, or Gemini thread in Chrome.
2. Click the Tacket extension.
3. Choose **Capture This Thread**.
4. Open Tacket and choose **Index Capture Folder** in Library.
5. Search or select the saved thread.
6. Transfer it to Clipboard, Codex, or Claude Code.

The first automated transfer may trigger a macOS permission prompt. Tacket uses that permission only to open Terminal and paste the transcript after you choose a transfer target.

## Local Bundles

Each capture is saved as a folder ending in `.tacket`:

```text
2026-06-01 10.51 - ChatGPT - Planning the app.tacket/
  README.md
  manifest.json
  messages.jsonl
  transcript.md
  attachments/
  targets/
    codex.md
    claude-code.md
```

You can inspect the files yourself. The folder name includes the capture date, source app, and thread title. If Tacket saves the same thread name twice, it adds a Finder-style suffix like `(2)`. The transcript is plain Markdown.

## Local Library

Tacket can index `.tacket` bundles into:

```text
~/Library/Application Support/Tacket/library.sqlite
```

The library uses local SQLite full-text search. It does not summarize transcripts, generate embeddings, call a model, sync to a server, or send indexed text anywhere.

Advanced search can match an exact phrase, all terms, or any term; search everything, transcript text, or titles; and filter by source or message role.

## Privacy

Tacket is designed to stay on your Mac. See [docs/PRIVACY.md](docs/PRIVACY.md) and the public [privacy page](website/privacy.html) for the current privacy contract.

## Support

Tacket is made by [@maddiedreese](https://github.com/maddiedreese). If you want to support the project, you can sponsor development on [GitHub Sponsors](https://github.com/sponsors/maddiedreese).

## Contributing

Issues and pull requests are welcome. Before opening a PR, run:

```bash
npm run verify
```

Release planning lives in [docs/ROADMAP.md](docs/ROADMAP.md). Troubleshooting lives in [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## License

Apache-2.0
