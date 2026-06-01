# Testing

## Automated Checks

```bash
npm run package:release
```

`npm run package:release` runs `npm run verify`, builds the release DMG and extension zip, prepares `dist/chrome-web-store/`, and verifies both the release downloads and Chrome Web Store upload folder. `npm run verify` checks required project files and runs:

- `.tacket` bundle format tests
- `.tacket` JSON Schema and integrity validation against generated sample bundles
- transcript rendering tests
- attachment persistence tests
- Chrome save-flow fixture tests for ChatGPT, Claude, and Gemini-like pages
- website release-link and privacy-copy checks
- local-first privacy checks that reject telemetry/backends and unapproved runtime network APIs
- first-run smoke coverage for local extension setup/status/remove, saved chat validation, and Codex/Claude Code dry-run transfer in isolated temporary folders

Run only the website checks with:

```bash
npm run website:verify
```

Run only the local-first privacy checks with:

```bash
npm run privacy:verify
```

Run only the first-run smoke path with:

```bash
npm run smoke:first-run
```

After `npm run package:release` builds `dist/Tacket.dmg`, rehearse the direct-download install path with:

```bash
npm run smoke:dmg-install
```

This mounts the DMG, copies `Tacket.app` into a temporary Applications-like folder, runs the packaged Swift local host with an isolated `HOME` and save directory, validates the saved Tacket chat folder, then unmounts and removes all temporary files.

## Manual Browser Checks

Live AI apps change their pages often. Before a release, test saving manually against:

- a ChatGPT thread with text, code, and an image
- a Claude thread with text, code, and an attached or linked file
- a Gemini thread with text and code
- a long thread that requires scrolling

Create a local QA report before live testing:

```bash
npm run qa:live
```

This writes a timestamped checklist under `qa/live-capture/`. Those reports are git-ignored because they may contain local paths, extension IDs, provider notes, or other release evidence that should be reviewed before sharing. Do not paste private chat text, screenshots with private content, API keys, tokens, or private file names into QA reports.

After filling the top-level environment fields, completing the checklist, setting `Release decision: Pass`, and adding the ChatGPT, Claude, and Gemini saved chat paths, verify the report and saved chats:

```bash
npm run qa:live:verify -- qa/live-capture/<report>.md
```

If no report path is supplied, the verifier uses the newest markdown report in `qa/live-capture/`. The verifier fails if required checkboxes are missing or incomplete, if required environment/build fields are blank or placeholder-like, if the Chrome extension ID is not a valid 32-letter ID, if a provider saved chat path is missing, if a saved chat fails schema validation, if a provider manifest does not match the expected source platform, if reported message/attachment/warning evidence does not match `manifest.json`, or if the report appears to contain private secret-like text.

Generate a public-safe summary for the v0.1.0 live QA issue after verification passes:

```bash
npm run qa:live:summary -- qa/live-capture/<report>.md
```

The summary omits saved chat paths, local save folders, tester names, extension IDs, and provider notes. It includes provider names, counts, pass/fail evidence fields, release decision, and follow-up issue links.
The summary command refuses to print if its output would include a saved chat path, save folder, tester name, or Chrome extension ID.

For local extension plumbing, open:

```text
examples/capture-demo/index.html
```

For this local-only test, copy `apps/chrome-extension/manifest.dev.json` to `apps/chrome-extension/manifest.json` temporarily, reload the unpacked extension, and enable "Allow access to file URLs". Restore the production manifest before packaging.

For each source, confirm:

- message order is preserved
- user and assistant roles are correct
- code block indentation is preserved
- images are saved or clearly marked as referenced
- `.tacket/manifest.json`, `messages.jsonl`, and `transcript.md` are written locally
- the Mac app shows selected saved chat metadata and can open/copy `transcript.md`
- the Mac app can choose/reset the save folder and the Swift local host writes to the configured folder
- long conversations transfer as ordered chunks when the chunk size is smaller than the conversation
- transfer refuses saved chat folders whose target files drift from `transcript.md`
- obvious API-key-like text is reported as a local warning in `manifest.json` without redacting the saved conversation

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
Chunk size must be an integer of at least 1000 characters.

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

Local host tests also use `TACKET_CAPTURE_DIR` and `TACKET_CONFIG_FILE` to verify save-folder overrides without touching a user's real Tacket config.

After the Chrome Web Store extension is approved, verify the published extension ID without touching the real Chrome native messaging setup:

```bash
npm run store:verify-id -- --extension-id <chrome-extension-id>
```
