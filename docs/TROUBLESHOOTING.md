# Troubleshooting

Tacket is local-first, so most setup issues are local connector, browser permission, or macOS permission issues.

## The Extension Says Capture Failed

Confirm the active tab is a supported chat page:

- `https://chatgpt.com/*`
- `https://chat.openai.com/*`
- `https://claude.ai/*`
- `https://gemini.google.com/*`

Tacket refuses capture on other hosts before injecting the capture script.

If the page is supported but no messages are found, reload the chat page and try again. Live AI apps change their DOMs, so capture regressions should include the source app, Chrome version, Tacket version, and a synthetic/minimal reproduction when possible.

## Native Host Not Found

Chrome Native Messaging requires a local manifest that points to the Tacket native host.

For development:

```bash
node apps/cli/bin/tacket.js status-native-host
node apps/cli/bin/tacket.js install-native-host --extension-id <chrome-extension-id>
```

For the packaged Mac app, use the **Chrome Connector** panel:

1. Click **Chrome Extensions**.
2. Enable Developer Mode or install the published extension.
3. Copy the extension ID.
4. Paste it into Tacket.
5. Click **Install Connector**.
6. Click **Check Status**.

Chrome extension IDs are 32 lowercase letters from `a` to `p`.

## Captures Go to the Wrong Folder

The Mac app stores the selected capture folder at:

```text
~/Library/Application Support/Tacket/config.json
```

Use **Choose Capture Folder** or **Reset Folder** in the Mac app. The packaged Swift host and development Node host both read this config file. `TACKET_CAPTURE_DIR` overrides it for tests.

## Terminal Paste Does Not Happen

Tacket copies the transcript to the clipboard before trying to automate Terminal. If macOS blocks automation, you can still paste manually.

Check macOS settings for:

- Privacy & Security -> Automation
- Privacy & Security -> Accessibility

The CLI can launch/copy without requesting paste:

```bash
node apps/cli/bin/tacket.js transfer path/to/thread.tacket --to codex --no-paste
```

For automated checks, use `--dry-run`.

## Bundle Transfer Is Rejected

Before copying to the clipboard or opening Terminal, Tacket checks that a selected `.tacket` bundle still has `manifest.json`, `messages.jsonl`, `transcript.md`, and transfer targets that exactly match `transcript.md`. If this fails, re-capture the thread or restore the bundle files from the original capture.

## Unsigned App Warning

Local development builds are unsigned. Public direct-download builds should be signed with Developer ID and notarized before release. See `docs/RELEASE.md`.

## Local File Demo Does Not Capture

The production extension manifest does not include `file://` permissions. For the local demo in `examples/capture-demo`, use `apps/chrome-extension/manifest.dev.json` temporarily and enable **Allow access to file URLs** in Chrome. Restore the production manifest before packaging.

## Uninstall Tacket

Tacket does not install a background service. To remove a direct-download install:

1. Open Tacket and click **Remove Connector** in the Chrome Connector panel, or run:

   ```bash
   node apps/cli/bin/tacket.js uninstall-native-host
   ```

2. Remove the Chrome extension from `chrome://extensions`.
3. Delete `Tacket.app` from `/Applications` or wherever you placed it.

Optional local files:

- Connector manifest: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.tacket.host.json`
- App preferences: `~/Library/Application Support/Tacket/config.json`
- Default capture folder: `~/Documents/Tacket Captures/`

Only delete `.tacket` bundles if you no longer need the captured transcripts.
