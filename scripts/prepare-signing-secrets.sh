#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/prepare-signing-secrets.sh \
    --repo maddiedreese/tacket \
    --certificate path/to/developer-id.p12 \
    --developer-id-application "Developer ID Application: Name (TEAMID)" \
    --apple-id you@example.com \
    --apple-team-id TEAMID

Required environment variables:
  DEVELOPER_ID_CERTIFICATE_PASSWORD
  KEYCHAIN_PASSWORD
  APPLE_APP_SPECIFIC_PASSWORD

Options:
  --dry-run    Validate inputs and print the secret names that would be set.

This script sends secrets to GitHub with `gh secret set`. It does not write the
base64 certificate to disk and does not print secret values.
USAGE
}

REPO="maddiedreese/tacket"
CERTIFICATE_PATH=""
DEVELOPER_ID_APPLICATION_VALUE=""
APPLE_ID_VALUE=""
APPLE_TEAM_ID_VALUE=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --certificate)
      CERTIFICATE_PATH="${2:-}"
      shift 2
      ;;
    --developer-id-application)
      DEVELOPER_ID_APPLICATION_VALUE="${2:-}"
      shift 2
      ;;
    --apple-id)
      APPLE_ID_VALUE="${2:-}"
      shift 2
      ;;
    --apple-team-id)
      APPLE_TEAM_ID_VALUE="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$CERTIFICATE_PATH" || -z "$DEVELOPER_ID_APPLICATION_VALUE" || -z "$APPLE_ID_VALUE" || -z "$APPLE_TEAM_ID_VALUE" ]]; then
  usage
  exit 2
fi

required_env=(
  DEVELOPER_ID_CERTIFICATE_PASSWORD
  KEYCHAIN_PASSWORD
  APPLE_APP_SPECIFIC_PASSWORD
)

for name in "${required_env[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Set $name before running this script." >&2
    exit 2
  fi
done

if [[ ! -f "$CERTIFICATE_PATH" ]]; then
  echo "Certificate not found: $CERTIFICATE_PATH" >&2
  exit 2
fi

if [[ "$CERTIFICATE_PATH" != *.p12 ]]; then
  echo "Expected a .p12 Developer ID certificate: $CERTIFICATE_PATH" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required: https://cli.github.com/" >&2
  exit 2
fi

gh auth status >/dev/null

if ! security cms -D -i "$CERTIFICATE_PATH" >/dev/null 2>&1; then
  # Password-protected .p12 files are not CMS blobs, so fall through to openssl validation.
  :
fi

if ! openssl pkcs12 -in "$CERTIFICATE_PATH" -nokeys -passin "pass:$DEVELOPER_ID_CERTIFICATE_PASSWORD" >/dev/null 2>&1; then
  echo "Could not read certificate with DEVELOPER_ID_CERTIFICATE_PASSWORD." >&2
  exit 2
fi

set_secret() {
  local name="$1"
  local value="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "Would set $name on $REPO"
  else
    printf '%s' "$value" | gh secret set "$name" --repo "$REPO" --body-file -
  fi
}

certificate_base64="$(base64 < "$CERTIFICATE_PATH" | tr -d '\n')"

set_secret "DEVELOPER_ID_APPLICATION" "$DEVELOPER_ID_APPLICATION_VALUE"
set_secret "DEVELOPER_ID_CERTIFICATE_BASE64" "$certificate_base64"
set_secret "DEVELOPER_ID_CERTIFICATE_PASSWORD" "$DEVELOPER_ID_CERTIFICATE_PASSWORD"
set_secret "KEYCHAIN_PASSWORD" "$KEYCHAIN_PASSWORD"
set_secret "APPLE_ID" "$APPLE_ID_VALUE"
set_secret "APPLE_TEAM_ID" "$APPLE_TEAM_ID_VALUE"
set_secret "APPLE_APP_SPECIFIC_PASSWORD" "$APPLE_APP_SPECIFIC_PASSWORD"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry run complete. No GitHub secrets were changed."
else
  echo "Signing and notarization secrets set for $REPO."
  echo "Run: npm run release:readiness"
fi
