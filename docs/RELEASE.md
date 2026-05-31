# Release Checklist

Tacket v1 is direct-download and local-only.

## Before Release

- Confirm `npm run package:release` passes.
- Create a local live-capture QA report with `npm run qa:live`.
- Test unpacked Chrome extension capture on ChatGPT, Claude, and Gemini.
- Test native messaging host installation with the Chrome Web Store extension ID.
- Test native messaging host status and removal from the Mac app.
- Test capture output in `~/Documents/Tacket Captures`.
- Test selected bundle review in the Mac app, including warning display and transcript open/copy actions.
- Test transfer to Clipboard, Codex, and Claude Code.
- Confirm the macOS Automation prompt explains that Tacket opens Terminal and pastes raw transcripts.
- Update `CHANGELOG.md`.
- Review `docs/PRIVACY.md` and Chrome listing copy for consistency.
- Review `docs/CHROME_WEB_STORE.md` before submitting the extension.
- Prepare Chrome Web Store images using `docs/STORE_ASSETS.md`.
- Run `npm run release:readiness` before pushing the release tag.

The repository can build unsigned local artifacts without paid accounts. Public distribution additionally requires:

- Apple Developer ID certificate for signing
- Apple notarization credentials
- Chrome Web Store developer account
- live capture validation against current ChatGPT, Claude, and Gemini pages

## Chrome Web Store

The extension should request only:

- `activeTab`
- `scripting`
- `nativeMessaging`
- host permissions for supported AI chat domains

The listing should say that capture happens only after the user clicks the extension button and that chat content is saved locally by the Tacket app.

Listing copy and permission justifications live in `docs/CHROME_WEB_STORE.md`.

## Direct Download

The public Mac build should be signed with Developer ID and notarized. A `.dmg` release can be attached to GitHub Releases and linked from the static website.

The signing script enables hardened runtime and signs the app with `apps/mac/TacketApp/Tacket.entitlements`. That entitlement file is intentionally small: it grants Apple Events automation so Tacket can open Terminal and paste the raw transcript after the user chooses Codex or Claude Code. Keep `NSAppleEventsUsageDescription` in `Info.plist` aligned with that behavior.

The GitHub Actions release workflow builds `Tacket.dmg`, `tacket-chrome-extension.zip`, and `SHA256SUMS` on `v*` tags or manual dispatch. Manual dispatch can produce unsigned test artifacts. Tag releases are stricter: they fail unless all signing and notarization secrets are configured, then import the Developer ID certificate, sign the app, package the DMG, notarize it, verify the final artifacts, upload an Actions artifact, and publish a GitHub Release.

Required GitHub secrets for signed release builds:

- `DEVELOPER_ID_APPLICATION`
- `DEVELOPER_ID_CERTIFICATE_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

Build local unsigned release artifacts:

```bash
npm run package:release
```

This runs icons, verification, extension packaging, Mac app packaging, DMG packaging, checksum generation, and release verification.

Development app bundle:

```bash
bash scripts/package-mac-dev.sh
open dist/Tacket.app
```

This creates an unsigned development `.app` bundle with the Swift app, Swift native messaging host, and Chrome extension resources. A public release still needs Developer ID signing, notarization, and a DMG packaging step.

Create a local DMG:

```bash
bash scripts/package-dmg.sh
```

The DMG should open with `Tacket.app` and an `Applications` shortcut. `npm run verify:release` mounts the DMG and checks that install layout.

Generate release checksums after packaging:

```bash
npm run generate:checksums
```

Attach `dist/SHA256SUMS` with the DMG and extension zip. `npm run verify:release` recomputes the hashes and fails if the checksum file is stale.

Sign and notarize when Developer ID credentials are available:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
bash scripts/sign-mac-app.sh
bash scripts/package-dmg.sh

export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
bash scripts/notarize-dmg.sh
```

Check remote release readiness:

```bash
npm run release:readiness
```

This command uses GitHub CLI to confirm the public repository is reachable, Pages is enabled, latest CI and manual Release workflow runs passed, v0.1.0 milestone issues are closed, required signing/notarization secrets are configured, and the release tag has not already been published.

## Versioning

Keep these versions aligned for public releases:

- `release.json`
- root `package.json`
- `apps/chrome-extension/manifest.json`
- `apps/mac/TacketApp`
- `.tacket` `schemaVersion`, when the bundle format changes
- `nativeHostName`, when changing the Chrome native messaging host identifier
