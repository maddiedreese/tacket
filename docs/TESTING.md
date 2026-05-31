# Testing

## Automated Checks

```bash
npm run package:release
```

`npm run package:release` runs `npm run verify`, builds the release DMG and extension zip, prepares `dist/chrome-web-store/`, and verifies both the release downloads and Chrome Web Store upload folder. `npm run verify` checks required project files and runs:

- `.tacket` bundle format tests
- `.tacket` JSON Schema validation against a generated sample bundle
- transcript rendering tests
- attachment persistence tests
- Chrome capture fixture tests for ChatGPT, Claude, and Gemini-like DOMs
- website release-link and privacy-copy checks
- local-first privacy checks that reject telemetry/backends and unapproved runtime network APIs
- first-run smoke coverage for connector install/status/remove, native-host capture, bundle validation, and Codex/Claude Code dry-run transfer in isolated temporary folders

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

This mounts the DMG, copies `Tacket.app` into a temporary Applications-like folder, runs the packaged Swift native host with an isolated `HOME` and capture directory, validates the captured `.tacket` bundle, then unmounts and removes all temporary files.

## Manual Browser Checks

Live AI apps change their DOMs. Before a release, test capture manually against:

- a ChatGPT thread with text, code, and an image
- a Claude thread with text, code, and an attached or linked file
- a Gemini thread with text and code
- a long thread that requires scrolling

Create a local QA report before live testing:

```bash
npm run qa:live
```

This writes a timestamped checklist under `qa/live-capture/`. Those reports are git-ignored because they may contain local paths, extension IDs, provider notes, or other release evidence that should be reviewed before sharing. Do not paste private transcript text, screenshots with private content, API keys, tokens, or private file names into QA reports.

After filling the top-level environment fields, completing the checklist, setting `Release decision: Pass`, and adding the ChatGPT, Claude, and Gemini bundle paths, verify the report and captured bundles:

```bash
npm run qa:live:verify -- qa/live-capture/<report>.md
```

If no report path is supplied, the verifier uses the newest markdown report in `qa/live-capture/`. The verifier fails if required checkboxes are incomplete, if required environment/build fields are blank or placeholder-like, if the Chrome extension ID is not a valid 32-letter ID, if a provider bundle path is missing, if a bundle fails schema validation, if a provider bundle manifest does not match the expected source platform, if reported message/attachment/warning evidence does not match `manifest.json`, or if the report appears to contain private secret-like text.

Generate a public-safe summary for the v0.1.0 live QA issue after verification passes:

```bash
npm run qa:live:summary -- qa/live-capture/<report>.md
```

The summary omits bundle paths, local capture folders, tester names, extension IDs, and provider notes. It includes provider names, counts, pass/fail evidence fields, release decision, and follow-up issue links.
The summary command refuses to print if its output would include a captured bundle path, capture folder, tester name, or Chrome extension ID.

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

Native host tests also use `TACKET_CAPTURE_DIR` and `TACKET_CONFIG_FILE` to verify capture-folder overrides without touching a user's real Tacket config.

After the Chrome Web Store extension is approved, verify the published extension ID without touching the real Chrome native messaging setup:

```bash
npm run store:verify-id -- --extension-id <chrome-extension-id>
```
