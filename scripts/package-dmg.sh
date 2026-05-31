#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/Tacket.app"
DMG_PATH="$DIST_DIR/Tacket.dmg"
STAGING_DIR="$DIST_DIR/dmg-staging"
VOLUME_NAME="Tacket"

if [[ ! -d "$APP_PATH" ]]; then
  bash "$ROOT_DIR/scripts/package-mac-dev.sh" >/dev/null
fi

rm -f "$DMG_PATH"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/Tacket.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo "$DMG_PATH"
