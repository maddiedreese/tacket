# Tacket

Tacket is a private local library for saving, searching, and reusing AI chats.

Use the Chrome extension on ChatGPT, Claude, or Gemini in the browser to save full raw chat transcripts. Use the Mac app to save desktop app chats locally: Codex and Claude desktop captures use local transcript/session files when available, filtered to the user and assistant conversation, and ChatGPT desktop captures use the local preview path. Tacket stores saved chats on your Mac, paginates and searches the local library, and lets you copy or open saved conversations when you need the context again.

Tacket will always be free and open source. It has no accounts, no analytics, no telemetry, and no backend that can see your chats.

The first release has two local pieces: a Chrome extension for exact browser chat transcripts and a Mac app for storing, searching, desktop app capture, menu bar Quick Capture, and local transcript reuse. Browser saves go directly from the extension to the Tacket app on your Mac. For Codex and Claude desktop chats, Tacket saves the local conversation transcript when available and filters out system/tool scaffolding so the `.tacket` contains the user and assistant conversation. For ChatGPT desktop, or when a local transcript is not available, Tacket uses macOS Accessibility or on-device OCR and shows a preview before saving. Saved chat text is not sent to me or to a Tacket server.

Tacket is available for macOS now. Windows support is planned next.

## Screenshots

Browse every saved chat in the local Mac app library.

![Tacket Mac app library](docs/assets/readme/app-library.png)

Use search and filters to narrow saved transcripts without sending anything off your Mac.

![Tacket Mac app advanced search](docs/assets/readme/app-advanced-search.png)

## What It Does

- Saves browser conversations only after you click the extension.
- Saves current Codex and Claude desktop app chats from local transcript/session files when available, filtered to user and assistant messages.
- Previews and saves local Accessibility/OCR captures for ChatGPT desktop and fallback desktop capture.
- Can add an optional menu bar item for quick desktop app capture.
- Keeps saved chats as readable files on your Mac.
- Lets you browse all saved chats in one paginated local library.
- Searches saved chats, code snippets, decisions, and errors without sending them anywhere.
- Copies the full saved conversation to your clipboard and opens or reveals the local `.tacket` folder.
- Uses no backend, no analytics, no telemetry, and no model/API calls.

Tacket is not an agent harness. It does not run agents for you or scan app session stores in the background.

## Install

The shortest path is the public release:

1. Download `Tacket.dmg` from the [latest release](https://github.com/maddiedreese/tacket/releases).
2. Open the DMG and drag Tacket into Applications.
3. Open Tacket, go to **Settings**, and click **Install Local Connector**.
4. Add the [Tacket Chrome extension](https://chromewebstore.google.com/detail/tacket/cbpgfpcajomllnfoigagibafblmnbbdh).

You can also build it from source:

```bash
npm install
npm run package:release
open dist/Tacket.app
```

Then load `apps/chrome-extension` as an unpacked Chrome extension and connect it to the local app:

```bash
node apps/cli/bin/tacket.js install-native-host --extension-id cbpgfpcajomllnfoigagibafblmnbbdh
```

## Use

1. Open a ChatGPT, Claude, or Gemini conversation in Chrome and click the Tacket extension, or open a ChatGPT, Claude, or Codex desktop app chat and start desktop capture from Tacket.
2. Choose **Save Conversation** in the extension. For Codex and Claude desktop chats, Tacket saves the local transcript when available; for ChatGPT desktop and fallback capture, review the local preview before saving.
3. Open Tacket and choose **Add Saved Chats** in Library if the saved chat is not already indexed.
4. Browse pages of saved chats, search, filter, or select the saved chat.
5. Copy the transcript, open it, or reveal the local `.tacket` folder whenever you need the context again.

Desktop app capture may trigger macOS Accessibility or Screen Recording permission prompts when Tacket needs the preview fallback. Codex and Claude local transcript saves do not upload anything and filter saved output to user and assistant messages.

Optional Quick Capture lives in the menu bar after you enable it in **Settings**. It can start capture from the frontmost supported desktop chat app, or from ChatGPT, Claude, and Codex directly. It does not monitor apps in the background or save anything silently.

The approved Chrome Web Store extension ID is `cbpgfpcajomllnfoigagibafblmnbbdh`. Tacket uses that ID when you click **Install Local Connector** in Settings, so normal users do not need to copy or paste extension IDs.

Bulk local imports from Codex App, Claude App, and Claude Code are in the pipeline, but they are not part of the working public release yet. The current desktop path is user-clicked capture of the current open app/chat.

## Saved Files

Each saved chat is stored as a local folder. The folder includes a readable transcript, structured message data, and any attachments Tacket was able to save:

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

You can inspect these files yourself. The folder name includes the date you saved the chat, the source app, and the chat title. If Tacket saves the same chat name twice, it adds a Finder-style suffix like `(2)`.

## Local Library

Tacket builds a local search index from the chats you choose to add to the Library. The index stays on your Mac. It does not summarize conversations, generate embeddings, call a model, sync to a server, or send indexed text anywhere.

The Library paginates saved chats so large local collections stay readable. Advanced search can match an exact phrase, all terms, or any term; search conversation text or titles; and filter by source or message role.

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
