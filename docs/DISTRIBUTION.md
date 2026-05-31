# Distribution Plan

Tacket v1 will ship by direct download and GitHub, not the Mac App Store.

## Direct Download

The public app should be signed with Developer ID and notarized by Apple. Distribution can use:

- a `.dmg` from the Tacket website
- GitHub Releases
- optional Homebrew cask later

Local unsigned builds use:

```bash
bash scripts/package-mac-dev.sh
bash scripts/package-dmg.sh
```

The DMG contains `Tacket.app` and an `Applications` shortcut so users can drag the app into `/Applications`.

Release downloads should include `SHA256SUMS` for `Tacket.dmg` and `tacket-chrome-extension.zip`.

Uninstall guidance lives in `docs/TROUBLESHOOTING.md`.

## Chrome Extension

The Chrome extension should be published through the Chrome Web Store. On macOS and Windows, Chrome extensions should come from the Web Store rather than a bundled local CRX.

The app installer can still install the local native messaging host, then open the Chrome Web Store listing so the user can add the extension.

## No Backend

Tacket should not require hosted infrastructure. The public website is the static `website/` directory and is deployed by Netlify from GitHub. The repository includes `netlify.toml` with:

- build command: `npm run website:verify`
- publish directory: `website`

No Netlify environment variables are required for v1. A custom domain can be added in Netlify later without changing the app architecture.

## Expected Costs

- Apple Developer Program: yearly cost for Developer ID signing and notarization.
- Chrome Web Store developer registration: one-time registration fee.
- Domain: yearly registrar cost.
- Website hosting: Netlify free tier should be enough for v1.
- Backend: none required for v1.
- AI/API usage: none required for v1.
