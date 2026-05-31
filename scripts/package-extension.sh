#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/dist"
OUT_FILE="$OUT_DIR/tacket-chrome-extension.zip"

mkdir -p "$OUT_DIR"
rm -f "$OUT_FILE"

cd "$ROOT_DIR/apps/chrome-extension"
zip -qr "$OUT_FILE" \
  manifest.json \
  src \
  icons \
  -x "*/test/*" \
  -x "*.DS_Store"

echo "$OUT_FILE"
