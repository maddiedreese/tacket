# Tacket

Tacket is a local-first Mac app and Chrome extension for moving complete AI chat threads into coding agents without summarizing them.

The v1 goal is deliberately narrow:

- capture raw threads from ChatGPT, Claude, and Gemini in Chrome when the user clicks capture
- preserve text, code blocks, images, and attachment references in an inspectable `.tacket` bundle
- write the bundle locally
- copy and paste the raw transcript into Codex or Claude Code
- use no backend, no analytics, and no cloud storage

Tacket is not an agent harness and does not try to mutate private app session stores. It transfers user-owned conversation artifacts as local files and raw transcript text.

## Project Layout

```text
.github/workflows/      GitHub Actions CI
apps/chrome-extension/  Chrome MV3 extension for user-click thread capture
apps/cli/               `tacket` CLI for installing the host, packing, and transferring
apps/native-host/       Chrome Native Messaging host
apps/mac/               SwiftUI Mac app and packaged native messaging host
packages/thread-format/ Shared `.tacket` bundle writer and transcript renderer
schemas/                JSON Schemas for portable thread data
docs/                   Architecture, privacy, distribution, and format docs
website/                Static website and public privacy page
```

For setup or first-run issues, see `docs/TROUBLESHOOTING.md`.
For release notes, see `CHANGELOG.md`.

## Current Development Flow

```bash
cd Tacket
npm install
npm run generate:icons
npm run verify
sample_path=$(node apps/cli/bin/tacket.js sample --out /tmp/tacket-demo)
node apps/cli/bin/tacket.js transfer "$sample_path" --to clipboard
```

Install the native messaging host for Chrome development:

```bash
node apps/cli/bin/tacket.js install-native-host \
  --extension-id <chrome-extension-id>
node apps/cli/bin/tacket.js status-native-host
```

Then load `apps/chrome-extension` as an unpacked extension in Chrome, open a supported thread, and click **Capture This Thread** from the extension popup.

Transfer a saved bundle into a coding agent:

```bash
node apps/cli/bin/tacket.js transfer ~/Documents/Tacket\ Captures/example.tacket --to codex
node apps/cli/bin/tacket.js transfer ~/Documents/Tacket\ Captures/example.tacket --to claude-code
```

Tacket copies the raw transcript and requests a paste into Terminal. Use `--no-paste` to launch/copy without the automation step.
Long transcripts are copied as ordered raw chunks. The Mac app exposes the chunk size in the transfer panel; the CLI uses `--chunk-size`.

Run the Mac shell during development:

```bash
cd apps/mac/TacketApp
swift run
```

## End-to-End Development Checklist

1. Run `npm install` from the repository root.
2. Open `chrome://extensions`.
3. Enable Developer Mode.
4. Load `apps/chrome-extension` as an unpacked extension.
5. Copy the generated extension ID.
6. Run `node apps/cli/bin/tacket.js install-native-host --extension-id <id>`.
7. Open a ChatGPT, Claude, or Gemini thread in Chrome.
8. Click the Tacket extension and choose **Capture This Thread**.
9. Choose the saved `.tacket` bundle from `~/Documents/Tacket Captures`.
10. Review the selected bundle manifest, warnings, and raw transcript in the Mac app.
11. Transfer it with the CLI or Mac app.

The first time Tacket requests automated paste into Terminal, macOS may ask for Automation and Accessibility permission. Tacket copies the transcript locally first; those permissions are only used to open Terminal and press paste for the selected coding agent.

Chrome extension IDs are 32 lowercase letters from `a` to `p`. Copy the exact ID from `chrome://extensions`; Tacket rejects malformed IDs before writing the connector manifest.

The Mac app stores its capture-folder preference at:

```text
~/Library/Application Support/Tacket/config.json
```

Remove the development connector:

```bash
node apps/cli/bin/tacket.js uninstall-native-host
```

Package local development artifacts:

```bash
npm run package:release
```

## License

Apache-2.0
