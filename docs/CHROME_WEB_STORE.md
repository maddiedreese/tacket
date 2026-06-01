# Chrome Web Store Listing

## Name

Tacket

## Short Description

Save AI chats locally and search them later.

## Detailed Description

Tacket saves ChatGPT, Claude, and Gemini conversations to your Mac so you can search them later and reuse the full conversation when you need the context again. Saved chats can be copied to your clipboard or sent to coding tools such as Codex and Claude Code.

Tacket is local-first:

- Tacket saves a conversation only after you click the extension
- saved chat text goes to the Tacket app on your Mac
- saved chats are written to local files you control
- local library search stays on your Mac
- no analytics, telemetry, backend account, or model/API calls
- no background chat collection
- local manifest warnings for possible secrets, without redaction or upload
- Chrome Web Store distribution does not mean saved chat text is sent to the developer or a Tacket server

The extension works with the Tacket Mac app. Install the app, add the Chrome extension, save a supported conversation, then browse, search, copy, or transfer it from your local library.

## Single Purpose

Tacket saves user-selected AI chat conversations from supported providers and sends the saved conversation to the local Tacket app for local storage, local search, and user-chosen transfer.

## Permission Justification

### `activeTab`

Used to read the current supported AI chat page only after the user clicks the extension button.

### `scripting`

Used to read the active supported chat tab after the user clicks the save button.

### `nativeMessaging`

Used to send the saved conversation to the local Tacket Mac app. Tacket does not send saved chat content to a remote server.

### Host permissions

Tacket requests host permissions only for supported AI chat pages:

- `https://chatgpt.com/*`
- `https://chat.openai.com/*`
- `https://claude.ai/*`
- `https://gemini.google.com/*`

These permissions allow the extension to read the current conversation when the user asks Tacket to save it.

## Privacy Practices

Tacket does not collect, sell, transmit, or remotely process user data. Saved chat content remains local unless the user chooses to share the generated files. Google may process normal Chrome Web Store installation and distribution metadata, but Tacket does not send saved chat content to the developer or to a Tacket backend.

## Screenshot Checklist

Detailed asset requirements and privacy rules live in `docs/STORE_ASSETS.md`.

Prepare Chrome Web Store screenshots showing:

- extension popup before saving
- successful save result with a local folder path
- Tacket Mac app local connection setup
- Tacket Mac app transfer target selector
- Tacket Mac app selected saved chat review with local warnings
- local Tacket chat files in Finder

The extension package includes generated PNG icons at 16, 32, 48, and 128 pixels.

## Submission Folder

Prepare a local upload folder with:

```bash
npm run store:prepare
```

This writes `dist/chrome-web-store/` with the extension zip, required icon, small promotional image, screenshots, `listing.md`, `privacy.md`, and a short upload README. Review every generated image before submitting.

`npm run package:release` also runs this preparation step after building the DMG and release zip. If release artifacts already exist in `dist/`, `store:prepare` refreshes `SHA256SUMS` after rebuilding the extension zip so the release checksums do not go stale.

The GitHub Actions Release workflow also prepares `dist/chrome-web-store/` and includes it in the `tacket-release` Actions artifact for manual review/submission. The public GitHub Release still attaches only `Tacket.dmg`, `tacket-chrome-extension.zip`, and `SHA256SUMS`.

Verify the prepared upload folder independently with:

```bash
npm run store:verify
```

This checks the extension zip contents, confirms the upload zip matches `dist/tacket-chrome-extension.zip`, verifies production manifest permissions and host permissions, generated image dimensions, listing/privacy copy, and obvious secret-like text.

## Published Extension ID

After Chrome Web Store approval, verify the published extension ID can be used by the local app connection:

```bash
npm run store:verify-id -- --extension-id <chrome-extension-id>
```

The command uses an isolated temporary home directory, installs the local Chrome app connection for that exact ID, checks the `allowed_origins` entry, then uninstalls it. It does not modify the user's real Chrome setup.
