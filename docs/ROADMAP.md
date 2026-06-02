# Roadmap

Tacket v1 is focused on a private local library for AI chats, with full-conversation transfer to coding tools when users need to move context.

Current builds support the Chrome extension browser flow plus Mac app visible capture for open ChatGPT, Claude, and Codex desktop app chats.

## v0.1.0

Public tracking lives in the GitHub milestone:

```text
https://github.com/maddiedreese/tacket/milestone/1
```

The first public release covered:

- live save validation for current ChatGPT, Claude, and Gemini pages
- Developer ID signing and Apple notarization for direct-download Mac builds, with secrets prepared by `scripts/prepare-signing-secrets.sh`
- Chrome Web Store draft listing prepared without submitting for review
- signed GitHub release with `Tacket.dmg`, `tacket-chrome-extension.zip`, and `SHA256SUMS`

## Later

- import saved Tacket chat folders from more places
- coding-agent to coding-agent transfer
- optional target-specific prompt helpers, without replacing full-conversation storage or transfer
- additional browsers after the Chrome v1 path is stable
- exact per-app transcript import when desktop apps expose stable local stores or richer native export APIs
- Homebrew cask once the direct-download release is proven
