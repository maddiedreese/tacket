# Testing

## Automated Checks

```bash
npm run package:release
```

`npm run verify` checks required project files and runs:

- `.tacket` bundle format tests
- `.tacket` JSON Schema validation against a generated sample bundle
- transcript rendering tests
- attachment persistence tests
- Chrome capture fixture tests for ChatGPT, Claude, and Gemini-like DOMs

## Manual Browser Checks

Live AI apps change their DOMs. Before a release, test capture manually against:

- a ChatGPT thread with text, code, and an image
- a Claude thread with text, code, and an attached or linked file
- a Gemini thread with text and code
- a long thread that requires scrolling

For local extension plumbing, open:

```text
examples/capture-demo/index.html
```

For this local-only test, copy `apps/chrome-extension/manifest.dev.json` to `apps/chrome-extension/manifest.json` temporarily, reload the unpacked extension, and enable "Allow access to file URLs". Restore the production manifest before packaging.

For each source, confirm:

- message order is preserved
- user and assistant roles are correct
- code block indentation is preserved
- images are captured or clearly marked as referenced
- `.tacket/manifest.json`, `messages.jsonl`, and `transcript.md` are written locally
- the Mac app shows selected bundle metadata and can open/copy `transcript.md`
- the Mac app can choose/reset the capture folder and the Swift native host writes to the configured folder
- long transcripts transfer as ordered raw chunks when the chunk size is smaller than the transcript
- obvious API-key-like text is reported as a local warning in `manifest.json` without redacting the transcript

## Transfer Checks

Use a sample bundle:

```bash
sample_path=$(node apps/cli/bin/tacket.js sample --out /tmp/tacket-demo)
node apps/cli/bin/tacket.js transfer "$sample_path" --to clipboard
node apps/cli/bin/tacket.js transfer "$sample_path" --to codex --dry-run
node apps/cli/bin/tacket.js transfer "$sample_path" --to claude-code --dry-run
node apps/cli/bin/tacket.js transfer "$sample_path" --to clipboard --chunk-size 1000
```

The `--dry-run` flag is useful in automated/manual testing because it avoids launching Terminal or requiring Automation or Accessibility permission.

## Connector Checks

Use an isolated `HOME` when testing native messaging install/remove:

```bash
tmp_home=$(mktemp -d)
HOME="$tmp_home" node apps/cli/bin/tacket.js status-native-host
HOME="$tmp_home" node apps/cli/bin/tacket.js install-native-host --extension-id abcdefghijklmnopqrstuvwxyzabcdef
HOME="$tmp_home" node apps/cli/bin/tacket.js status-native-host
HOME="$tmp_home" node apps/cli/bin/tacket.js uninstall-native-host
HOME="$tmp_home" node apps/cli/bin/tacket.js status-native-host
```

The Mac app has equivalent **Check Status** and **Remove Connector** actions in the Chrome Connector panel.

Native host tests also use `TACKET_CAPTURE_DIR` and `TACKET_CONFIG_FILE` to verify capture-folder overrides without touching a user's real Tacket config.
