# Release Checklist

Tacket v1 is direct-download and local-only.

## Before Release

- Confirm `npm run package:release` passes.
- Confirm `npm run smoke:first-run` passes for the local connector/capture/transfer rehearsal.
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
- Prepare the Chrome Web Store upload folder with `npm run store:prepare`, then review `dist/chrome-web-store/listing.md`, `privacy.md`, and every image before uploading.
- Run `npm run release:readiness` before pushing the release tag.
- Run `npm run release:pretag` immediately before creating the release tag.
- After the GitHub Release is published, run `npm run release:verify-download`.

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

Set signing secrets from a local exported Developer ID `.p12` certificate:

```bash
export DEVELOPER_ID_CERTIFICATE_PASSWORD="p12-password"
export KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"

scripts/prepare-signing-secrets.sh \
  --certificate ~/Downloads/developer-id-application.p12 \
  --developer-id-application "Developer ID Application: Your Name (TEAMID)" \
  --apple-id "you@example.com" \
  --apple-team-id "TEAMID"
```

Use `--dry-run` first to validate inputs without changing GitHub secrets. The script uses `gh secret set`, does not write the base64 certificate to disk, and does not print secret values.

Build local unsigned release artifacts:

```bash
npm run package:release
```

This runs icons, verification, extension packaging, Mac app packaging, DMG packaging, checksum generation, and release verification. Release verification checks the packaged native host binary, bundled extension resources, DMG layout, checksums, and the Chrome native messaging manifest contract used by the Mac app.

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

Check final pre-tag release state:

```bash
npm run release:pretag
```

This command verifies local release artifacts, the Chrome Web Store submission folder, version alignment, a dated `CHANGELOG.md` entry, no existing `v0.1.0` tag, no open v0.1.0 milestone issues, configured signing/notarization secrets, and current green CI/Release workflow runs. It is intentionally stricter than local packaging and should fail until the external release blockers are finished.

Verify public release downloads after the tag workflow publishes the GitHub Release:

```bash
npm run release:verify-download
```

This downloads `Tacket.dmg`, `tacket-chrome-extension.zip`, and `SHA256SUMS` from the `v0.1.0` GitHub Release, verifies the checksums, verifies the DMG with `hdiutil`, and checks the extension zip for required production files. To test the same verifier against local artifacts before a release exists, run:

```bash
npm run release:verify-download -- --dir dist
```

## Versioning

Keep these versions aligned for public releases:

- `release.json`
- root `package.json`
- `apps/chrome-extension/manifest.json`
- `apps/mac/TacketApp`
- `.tacket` `schemaVersion`, when the bundle format changes
- `nativeHostName`, when changing the Chrome native messaging host identifier
