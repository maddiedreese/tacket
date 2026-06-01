# Roadmap

Tacket v1 is focused on a local-first raw transcript library for AI chats, with exact transcript transfer to coding tools when users need to move context.

## v0.1.0

Public tracking lives in the GitHub milestone:

```text
https://github.com/maddiedreese/tacket/milestone/1
```

The first public release covered:

- live capture validation for current ChatGPT, Claude, and Gemini pages
- Developer ID signing and Apple notarization for direct-download Mac builds, with secrets prepared by `scripts/prepare-signing-secrets.sh`
- Chrome Web Store draft listing prepared without submitting for review
- signed GitHub release with `Tacket.dmg`, `tacket-chrome-extension.zip`, and `SHA256SUMS`

## Later

- import saved `.tacket` bundles from more places
- coding-agent to coding-agent transfer
- optional target-specific prompt helpers, without replacing raw transcript storage or transfer
- additional browsers after the Chrome v1 path is stable
- Homebrew cask once the direct-download release is proven
