# Tacket

Tacket moves complete AI chat threads into coding agents without turning them into summaries.

It is a local-first Mac app with a Chrome extension for ChatGPT, Claude, and Gemini. Click the extension on a supported chat page, save the full thread as a local `.tacket` bundle, then transfer the raw transcript into Codex or Claude Code.

Tacket is pre-release. Signed direct-download builds are coming with the first public release.

## What It Does

- Captures supported AI chats only after you click the extension.
- Saves readable local bundles in `~/Documents/Tacket Captures`.
- Preserves the raw transcript as Markdown and structured JSONL.
- Transfers to Clipboard, Codex, or Claude Code.
- Uses no backend, no analytics, no telemetry, and no model/API calls.

Tacket is not an agent harness. It does not run agents for you or reach into private app session stores.

## Install

Public releases will be the shortest path:

1. Download `Tacket.dmg` from the [latest release](https://github.com/maddiedreese/tacket/releases).
2. Open the DMG and drag Tacket into Applications.
3. Add the Tacket Chrome extension.
4. Open Tacket once so it can install its local Chrome connector.

Until the signed release is ready, you can try it from source:

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
4. Open Tacket and select the saved bundle.
5. Transfer it to Clipboard, Codex, or Claude Code.

The first automated transfer may trigger a macOS permission prompt. Tacket uses that permission only to open Terminal and paste the transcript after you choose a transfer target.

## Local Bundles

Each capture is saved as a folder ending in `.tacket`:

```text
example.tacket/
  manifest.json
  messages.jsonl
  transcript.md
  attachments/
  targets/
    codex.md
    claude-code.md
```

You can inspect the files yourself. The transcript is plain Markdown.

## Privacy

Tacket is designed to stay on your Mac. See [docs/PRIVACY.md](docs/PRIVACY.md) and the public [privacy page](website/privacy.html) for the current privacy contract.

## Contributing

Issues and pull requests are welcome. Before opening a PR, run:

```bash
npm run verify
```

Release planning lives in [docs/ROADMAP.md](docs/ROADMAP.md). Troubleshooting lives in [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## License

Apache-2.0
