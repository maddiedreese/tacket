# Release Checklist

Tacket v1 is direct-download and local-only.

## Before Release

- Confirm `npm run package:release` passes and refreshes `dist/chrome-web-store/`.
- Confirm `npm run smoke:first-run` passes for the local connector/capture/transfer rehearsal.
- Confirm `npm run smoke:dmg-install` passes for the packaged direct-download install rehearsal.
- Create a local live-capture QA report with `npm run qa:live`.
- Generate a public-safe live QA issue summary with `npm run qa:live:summary -- qa/live-capture/<report>.md`.
- Test unpacked Chrome extension capture on ChatGPT, Claude, and Gemini.
- Test native messaging host installation with the Chrome Web Store extension ID.
- Test native messaging host status and removal from the Mac app.
- Test capture output in `~/Documents/Tacket Captures`.
- Test selected bundle review in the Mac app, including warning display and transcript open/copy actions.
- Test transfer to Clipboard, Codex, and Claude Code.
- Confirm the macOS Automation prompt explains that Tacket opens Terminal and pastes raw transcripts.
- Update `CHANGELOG.md`.
- Review `docs/PRIVACY.md` and Chrome listing copy for consistency.
- Confirm `npm run website:verify` passes before publishing Pages changes.
- Review `docs/CHROME_WEB_STORE.md` before submitting the extension.
- Prepare Chrome Web Store images using `docs/STORE_ASSETS.md`.
- Prepare or refresh the Chrome Web Store upload folder with `npm run package:release` or `npm run store:prepare`, confirm `npm run store:verify` passes, then review `dist/chrome-web-store/listing.md`, `privacy.md`, and every image before uploading.
- After Chrome Web Store approval, verify the published extension ID with `npm run store:verify-id -- --extension-id <chrome-extension-id>`.
- Check the current blocker dashboard with `npm run release:status`.
- Confirm GitHub release issue checklists match the repo tooling with `npm run release:issues`.
- Run `npm run release:readiness` before pushing the release tag.
- Date the changelog with `npm run release:date-changelog -- --date YYYY-MM-DD` only after external release gates are complete.
- Run `npm run release:pretag` immediately before creating the release tag.
- Create and push the tag with `npm run release:tag -- --push`.
- After the GitHub Release is published, run `npm run release:postflight`.

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

The GitHub Actions release workflow builds `Tacket.dmg`, `tacket-chrome-extension.zip`, `SHA256SUMS`, and `dist/chrome-web-store/` on `v*` tags or manual dispatch. Manual dispatch can produce unsigned test artifacts. Tag releases are stricter: they fail unless all signing and notarization secrets are configured, then import the Developer ID certificate, sign the app, package the DMG, notarize it, run Gatekeeper assessment, verify the final artifacts, prepare the Chrome Web Store upload folder, upload an Actions artifact, and publish a GitHub Release.

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

This runs icons, verification, extension packaging, Mac app packaging, DMG packaging, checksum generation, release verification, DMG install smoke testing, Chrome Web Store upload folder preparation, store package verification, and a final release verification after the store zip/checksum refresh. Release verification checks the packaged native host binary, bundled extension resources, DMG layout, checksums, and the Chrome native messaging manifest contract used by the Mac app.

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
npm run release:status
```

This non-failing status command summarizes the current v0.1.0 milestone issues, signing/notarization secrets, release issue checklist sync state, latest CI/Release workflow state, whether those workflow runs match local `HEAD`, whether the latest Release workflow artifact is available and its contents verify, whether the GitHub Release already exists, and the next commands for each remaining blocker.

Verify the latest manual Release workflow artifact contents:

```bash
npm run release:verify-artifact
```

This downloads the latest `tacket-release` workflow artifact for the local `HEAD`, confirms it contains the public release downloads plus the Chrome Web Store upload folder, confirms the store zip matches the release extension zip, then runs the download verifier against the extracted files. To inspect a specific run or keep the downloaded copy:

```bash
npm run release:verify-artifact -- --run-id <github-actions-run-id> --keep
```

Check that v0.1.0 GitHub issue bodies match the canonical release checklist text:

```bash
npm run release:issues
```

To update issue bodies from the repository-maintained checklist text:

```bash
npm run release:issues -- --sync
```

Run the strict remote release gate:

```bash
npm run release:readiness
```

This command uses GitHub CLI to confirm the working tree is clean, the public repository is reachable, Pages is enabled, latest CI passed for the local `HEAD`, the latest manual Release workflow run passed for the local `HEAD`, the `tacket-release` workflow artifact is available and its contents verify, signing/notarization Release workflow steps ran successfully when signing secrets are configured, release issue checklists are synced, v0.1.0 milestone issues are closed, required signing/notarization secrets are configured, and the release tag has not already been published.

When the external release gates are complete, date the changelog entry:

```bash
npm run release:date-changelog -- --date YYYY-MM-DD
```

This replaces `## 0.1.0 - Unreleased` with a final dated heading. To confirm the changelog is ready without editing it:

```bash
npm run release:date-changelog -- --date YYYY-MM-DD --check
```

Check final pre-tag release state:

```bash
npm run release:pretag
```

This command verifies the working tree is clean, local release artifacts, the Chrome Web Store submission folder prepared by `npm run package:release` or `npm run store:prepare`, version alignment, a dated `CHANGELOG.md` entry, no existing `v0.1.0` tag, synced release issue checklists, no open v0.1.0 milestone issues, configured signing/notarization secrets, current green CI for the local `HEAD`, the latest green Release workflow run for the local `HEAD`, an available `tacket-release` workflow artifact with verified contents, and successful signing/notarization workflow steps when signing secrets are configured. It is intentionally stricter than local packaging and should fail until the external release blockers are finished.

Create the release tag after `release:pretag` passes:

```bash
npm run release:tag -- --push
```

This runs `npm run release:pretag`, requires a clean working tree, creates annotated tag `v0.1.0`, and pushes it only when `--push` is provided. To preview without running the gate or creating a tag:

```bash
npm run release:tag -- --dry-run --push
```

Verify public release downloads after the tag workflow publishes the GitHub Release:

```bash
npm run release:verify-download
```

This downloads `Tacket.dmg`, `tacket-chrome-extension.zip`, and `SHA256SUMS` from the `v0.1.0` GitHub Release, verifies the checksums, verifies the DMG with `hdiutil`, and checks the extension zip for required production files. To test the same verifier against local artifacts before a release exists, run:

```bash
npm run release:verify-download -- --dir dist
```

Run the full post-release verification:

```bash
npm run release:postflight
```

This verifies the website, downloads and checks the GitHub Release artifacts, confirms the published GitHub Release has `Tacket.dmg`, `tacket-chrome-extension.zip`, and `SHA256SUMS`, then runs Gatekeeper assessment. To rehearse against local `dist/` artifacts before the GitHub Release exists:

```bash
npm run release:postflight -- --dir dist --dry-run-gatekeeper
```

Assess signed and notarized artifacts with Gatekeeper:

```bash
npm run release:assess
```

This verifies the app signature, confirms the app is signed by a Developer ID Application certificate, asks Gatekeeper to assess the app and DMG, verifies the DMG, and validates the notarization staple. It is expected to fail for unsigned local development artifacts. To preview the exact commands without running assessment:

```bash
npm run release:assess -- --dry-run
```

## Versioning

Keep these versions aligned for public releases:

- `release.json`
- root `package.json`
- `apps/chrome-extension/manifest.json`
- `apps/mac/TacketApp`
- `.tacket` `schemaVersion`, when the bundle format changes
- `nativeHostName`, when changing the Chrome native messaging host identifier
