# Chrome Web Store Listing

## Name

Tacket

## Short Description

Capture AI chat threads locally and transfer raw transcripts to coding agents.

## Detailed Description

Tacket captures complete AI chat threads from supported pages and saves them locally on your Mac as inspectable `.tacket` bundles. It is built for moving planning conversations from ChatGPT, Claude, and Gemini into coding agents such as Codex and Claude Code without turning them into summaries. Long transcripts can be copied as ordered raw chunks.

Tacket is local-first:

- capture runs only after you click **Capture This Thread**
- captured content is sent to the local Tacket Mac app through Chrome Native Messaging
- bundles are written to your Mac
- no analytics, telemetry, backend account, or model/API calls
- no background chat collection
- local manifest warnings for possible secrets, without redaction or upload

The extension works with the Tacket Mac app. Install the app, add the Chrome extension, click capture on a supported thread, then transfer the raw transcript into your coding agent.

## Single Purpose

Tacket captures user-selected AI chat threads from supported providers and sends the captured thread to the local Tacket app for local storage and raw transcript transfer.

## Permission Justification

### `activeTab`

Used to capture the current supported AI chat page only after the user clicks the extension button.

### `scripting`

Used to inject the capture script into the active tab after the user clicks **Capture This Thread**.

### `nativeMessaging`

Used to send the captured thread to the local Tacket Mac app. Tacket does not send captured content to a remote server.

### Host permissions

Tacket requests host permissions only for supported AI chat pages:

- `https://chatgpt.com/*`
- `https://chat.openai.com/*`
- `https://claude.ai/*`
- `https://gemini.google.com/*`

These permissions allow the extension to read the current thread when the user requests capture.

## Privacy Practices

Tacket does not collect, sell, transmit, or remotely process user data. Captured data remains local unless the user chooses to share or commit the generated files.

## Screenshot Checklist

Detailed asset requirements and privacy rules live in `docs/STORE_ASSETS.md`.

Prepare Chrome Web Store screenshots showing:

- extension popup before capture
- successful capture result with local bundle path
- Tacket Mac app connector setup
- Tacket Mac app transfer target selector
- Tacket Mac app selected bundle review with local warnings
- local `.tacket` bundle files in Finder

The extension package includes generated PNG icons at 16, 32, 48, and 128 pixels.

## Submission Folder

Prepare a local upload folder with:

```bash
npm run store:prepare
```

This writes `dist/chrome-web-store/` with the extension zip, required icon, small promotional image, screenshots, `listing.md`, `privacy.md`, and a short upload README. Review every generated image before submitting.
