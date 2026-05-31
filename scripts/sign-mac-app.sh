#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/dist/Tacket.app}"
ENTITLEMENTS_PATH="$ROOT_DIR/apps/mac/TacketApp/Tacket.entitlements"

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "Set DEVELOPER_ID_APPLICATION to your Developer ID Application identity." >&2
  echo "Example: Developer ID Application: Your Name (TEAMID)" >&2
  exit 2
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  exit 2
fi

if [[ ! -f "$ENTITLEMENTS_PATH" ]]; then
  echo "Entitlements file not found: $ENTITLEMENTS_PATH" >&2
  exit 2
fi

codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" \
  "$APP_PATH/Contents/MacOS/TacketNativeHost"

codesign \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS_PATH" \
  --sign "$DEVELOPER_ID_APPLICATION" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH" || true

echo "$APP_PATH"
