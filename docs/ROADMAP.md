# Roadmap

Tacket v1 is focused on local-first raw transcript transfer from chat apps to coding agents.

## v0.1.0

Public tracking lives in the GitHub milestone:

```text
https://github.com/maddiedreese/tacket/milestone/1
```

Release blockers:

- live capture validation for current ChatGPT, Claude, and Gemini pages
- Developer ID signing and Apple notarization for direct-download Mac builds, with secrets prepared by `scripts/prepare-signing-secrets.sh`
- Chrome Web Store draft listing prepared without submitting for review
- signed GitHub release with `Tacket.dmg`, `tacket-chrome-extension.zip`, and `SHA256SUMS`

## Later

- coding-agent to coding-agent transfer
- optional target-specific prompt helpers, without replacing raw transcript transfer
- additional browsers after the Chrome v1 path is stable
- Homebrew cask once the direct-download release is proven
