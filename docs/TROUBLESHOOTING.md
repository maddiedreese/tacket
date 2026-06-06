# Troubleshooting

Tacket runs locally, so most setup issues are local app connection, browser permission, local library, or macOS permission issues.

## The Extension Says Save Failed

Confirm the active tab is a supported chat page:

- `https://chatgpt.com/*`
- `https://chat.openai.com/*`
- `https://claude.ai/*`
- `https://gemini.google.com/*`

Tacket refuses to save pages outside supported chat sites.

If the page is supported but no messages are found, reload the chat page and try again. Live AI apps change their pages often, so bug reports should include the source app, Chrome version, Tacket version, and a synthetic or minimal reproduction when possible.

## Chrome Extension Cannot Reach the App

The Chrome extension talks to the Tacket app through Chrome's local app connection system. For normal users, open Tacket, go to **Settings**, click **Install Local Connector**, then add the published extension from the Chrome Web Store:

```text
https://chromewebstore.google.com/detail/tacket/cbpgfpcajomllnfoigagibafblmnbbdh
```

If saving still fails, click **Check Connector** in Settings and confirm Chrome has the Tacket extension installed and enabled. The published extension ID is:

```text
cbpgfpcajomllnfoigagibafblmnbbdh
```

For development:

```bash
node apps/cli/bin/tacket.js status-native-host
node apps/cli/bin/tacket.js install-native-host --extension-id <chrome-extension-id>
```

For development builds, use the development-only Chrome connection settings:

1. Click **Chrome Extensions**.
2. Enable Developer Mode.
3. Copy the extension ID.
4. Paste it into Tacket.
5. Click **Install Development Connector**.
6. Click **Check Connector**.

Chrome extension IDs are 32 lowercase letters from `a` to `p`.

## Saved Chats Go to the Wrong Folder

The Mac app stores the selected save folder at:

```text
~/Library/Application Support/Tacket/config.json
```

Use **Choose Save Folder** or **Reset Folder** in the Mac app. `TACKET_CAPTURE_DIR` overrides it for tests.

## Library Search Finds Nothing

Tacket only searches saved chats that you have added to the Library. In the Mac app, open Library and click **Add Saved Chats** to add the current save folder, or choose another folder that contains Tacket chat folders.

The local search database is stored at:

```text
~/Library/Application Support/Tacket/library.sqlite
```

If files were moved or deleted, click **Remove Missing Chats** and add the folder again.

## Terminal Paste Does Not Happen

Tacket copies the saved conversation to the clipboard before trying to automate Terminal. If macOS blocks automation, you can still paste manually.

Check macOS settings for:

- Privacy & Security -> Automation
- Privacy & Security -> Accessibility

The CLI can launch/copy without requesting paste:

```bash
node apps/cli/bin/tacket.js transfer "path/to/saved-chat.tacket" --to codex --no-paste
```

For automated checks, use `--dry-run`.

## Transfer Is Rejected

Before copying to the clipboard or opening Terminal, Tacket checks that the selected saved chat still has the files it needs. If this fails, save the conversation again or restore the missing files.

## Unsigned App Warning

Local development builds are unsigned. Public direct-download builds should be signed with Developer ID and notarized before release. See `docs/RELEASE.md`.

## Local File Demo Does Not Capture

The production extension manifest does not include `file://` permissions. For the local demo in `examples/capture-demo`, use `apps/chrome-extension/manifest.dev.json` temporarily and enable **Allow access to file URLs** in Chrome. Restore the production manifest before packaging.

## Uninstall Tacket

Tacket does not install a background service. To remove a direct-download install:

1. Open Tacket and click **Remove Connector** in Settings, or run:

   ```bash
   node apps/cli/bin/tacket.js uninstall-native-host
   ```

2. Remove the Chrome extension from `chrome://extensions`.
3. Delete `Tacket.app` from `/Applications` or wherever you placed it.

Optional local files:

- Connector manifest: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.tacket.host.json`
- App preferences: `~/Library/Application Support/Tacket/config.json`
- Default save folder: `~/Documents/Tacket Captures/`

Only delete saved Tacket chat folders if you no longer need those conversations.
