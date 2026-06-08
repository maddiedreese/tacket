#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).version)' "$ROOT_DIR/release.json")"
BUILD="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).build)' "$ROOT_DIR/release.json")"
BUNDLE_ID="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).bundleIdentifier)' "$ROOT_DIR/release.json")"
APP_DIR="$ROOT_DIR/dist/Tacket.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

node "$ROOT_DIR/scripts/generate-icons.mjs" >/dev/null
cp "$ROOT_DIR/dist/Tacket.icns" "$RESOURCES_DIR/Tacket.icns"

swift build \
  --package-path "$ROOT_DIR/apps/mac/TacketApp" \
  -c release

cp "$ROOT_DIR/apps/mac/TacketApp/.build/release/TacketApp" "$MACOS_DIR/Tacket"
cp "$ROOT_DIR/apps/mac/TacketApp/.build/release/TacketNativeHost" "$MACOS_DIR/TacketNativeHost"
chmod +x "$MACOS_DIR/Tacket"
chmod +x "$MACOS_DIR/TacketNativeHost"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Tacket</string>
  <key>CFBundleIdentifier</key>
  <string>__BUNDLE_ID__</string>
  <key>CFBundleName</key>
  <string>Tacket</string>
  <key>CFBundleDisplayName</key>
  <string>Tacket</string>
  <key>CFBundleIconFile</key>
  <string>Tacket</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>__VERSION__</string>
  <key>CFBundleVersion</key>
  <string>__BUILD__</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Tacket uses macOS automation to open Terminal and paste the saved conversation into the coding agent you choose.</string>
  <key>NSAccessibilityUsageDescription</key>
  <string>Tacket uses Accessibility to scroll and read the desktop app chat you choose. Captured text is saved locally on your Mac.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Tacket uses local screen capture only when needed to read a desktop app chat with on-device OCR. Captured text is saved locally on your Mac.</string>
</dict>
</plist>
PLIST

perl -0pi -e "s/__VERSION__/$VERSION/g; s/__BUILD__/$BUILD/g; s/__BUNDLE_ID__/$BUNDLE_ID/g" "$CONTENTS_DIR/Info.plist"

EXTENSION_RESOURCES_DIR="$RESOURCES_DIR/chrome-extension"
mkdir -p "$EXTENSION_RESOURCES_DIR/src" "$EXTENSION_RESOURCES_DIR/icons"
cp "$ROOT_DIR/apps/chrome-extension/manifest.json" "$EXTENSION_RESOURCES_DIR/manifest.json"
cp "$ROOT_DIR/apps/chrome-extension/src/popup.html" "$EXTENSION_RESOURCES_DIR/src/popup.html"
cp "$ROOT_DIR/apps/chrome-extension/src/popup.css" "$EXTENSION_RESOURCES_DIR/src/popup.css"
cp "$ROOT_DIR/apps/chrome-extension/src/popup.js" "$EXTENSION_RESOURCES_DIR/src/popup.js"
cp "$ROOT_DIR/apps/chrome-extension/src/background.js" "$EXTENSION_RESOURCES_DIR/src/background.js"
mkdir -p "$EXTENSION_RESOURCES_DIR/src/adapters"
cp "$ROOT_DIR/apps/chrome-extension/src/adapters/capture.js" "$EXTENSION_RESOURCES_DIR/src/adapters/capture.js"
cp "$ROOT_DIR/apps/chrome-extension/icons/tacket-"*.png "$EXTENSION_RESOURCES_DIR/icons/"
cp "$ROOT_DIR/README.md" "$RESOURCES_DIR/"

SIGN_IDENTITY="${TACKET_CODESIGN_IDENTITY:-${DEVELOPER_ID_APPLICATION:-}}"
ENTITLEMENTS_PATH="$ROOT_DIR/apps/mac/TacketApp/Tacket.entitlements"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign \
    --force \
    --options runtime \
    --sign "$SIGN_IDENTITY" \
    "$MACOS_DIR/TacketNativeHost" >/dev/null
  codesign \
    --force \
    --options runtime \
    --entitlements "$ENTITLEMENTS_PATH" \
    --sign "$SIGN_IDENTITY" \
    "$APP_DIR" >/dev/null
else
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
