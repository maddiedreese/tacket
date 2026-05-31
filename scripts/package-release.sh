#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

npm --prefix "$ROOT_DIR" run generate:icons
npm --prefix "$ROOT_DIR" run verify
bash "$ROOT_DIR/scripts/package-extension.sh"
bash "$ROOT_DIR/scripts/package-mac-dev.sh"
bash "$ROOT_DIR/scripts/package-dmg.sh"
npm --prefix "$ROOT_DIR" run generate:checksums
npm --prefix "$ROOT_DIR" run verify:release
npm --prefix "$ROOT_DIR" run smoke:dmg-install

printf "Release artifacts ready in %s/dist\n" "$ROOT_DIR"
