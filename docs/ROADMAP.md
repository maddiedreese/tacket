# Roadmap

Tacket is focused on a private local library for AI chats, with full-conversation reuse when users need to move context.

The current release supports the Chrome extension browser flow, Mac app desktop capture for current open ChatGPT, Claude, and Codex desktop app chats, local library browsing/search, and full-conversation copy/open/reveal actions. Direct local imports from Codex App, Claude App, and Claude Code are in the pipeline, but they are not part of the working release yet.

## v0.1.0

The first public release is published:

```text
https://github.com/maddiedreese/tacket/releases/tag/v0.1.0
```

It includes:

- live save validation for current ChatGPT, Claude, and Gemini pages
- local library browsing, pagination, search, and advanced filters
- desktop capture previews for current open ChatGPT, Claude, and Codex desktop app chats
- optional menu bar Quick Capture
- Developer ID signing and Apple notarization for direct-download Mac builds, with secrets prepared by `scripts/prepare-signing-secrets.sh`
- Chrome Web Store package and listing assets for the browser extension
- signed GitHub release with `Tacket.dmg`, `tacket-chrome-extension.zip`, and `SHA256SUMS`

The milestone is closed:

```text
https://github.com/maddiedreese/tacket/milestone/1
```

## v0.2.0

The next milestone is Windows support and the cross-platform library groundwork needed to make Tacket useful outside macOS:

```text
https://github.com/maddiedreese/tacket/milestone/2
```

Planned work:

- Windows app support for saving, browsing, searching, and reusing local Tacket libraries
- Windows native messaging support for the Chrome extension
- Windows-friendly storage locations, open/reveal actions, and reuse flows
- release packaging and signing research for a direct-download Windows build
- shared cross-platform library behavior so saved `.tacket` folders stay portable

## Future

- import saved Tacket chat folders from more places
- direct local imports from Codex App, Claude App, and Claude Code once the flow is reliable enough to ship
- coding-agent to coding-agent transfer
- richer local import controls, including source selection and per-session review before import
- optional target-specific prompt helpers, without replacing full-conversation storage or transfer
- additional browsers after the Chrome path is stable
- per-app transcript import when desktop apps expose stable local stores or richer native export APIs
- Homebrew cask once the direct-download Mac release is proven
