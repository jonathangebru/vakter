#!/usr/bin/env bash
# Codesign the Anchor.app bundle and the embedded helper.
#
# Identity is auto-detected from your keychain. If you have more than one
# Developer ID Application identity, set DEVELOPER_ID_APPLICATION explicitly.
#
# Usage:
#   ./Scripts/sign.sh
set -euo pipefail

# Auto-detect identity if not explicitly set.
if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  DEVELOPER_ID_APPLICATION="$(
    security find-identity -v -p codesigning \
      | awk -F'"' '/Developer ID Application/ {print $2; exit}'
  )"
  if [[ -z "${DEVELOPER_ID_APPLICATION}" ]]; then
    echo "ERROR: no 'Developer ID Application' identity found in your keychain."
    echo "Verify with:  security find-identity -v -p codesigning"
    exit 1
  fi
fi

echo "==> Signing as: ${DEVELOPER_ID_APPLICATION}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${ROOT}/build/Anchor.app"
HELPER="${APP}/Contents/MacOS/AnchorHelper"
APP_ENT="${ROOT}/Sources/AnchorApp/Resources/Anchor.entitlements"
HELPER_ENT="${ROOT}/Sources/AnchorHelper/Resources/AnchorHelper.entitlements"

[[ -e "${APP}" ]] || { echo "Build first (./Scripts/build-app.sh)"; exit 1; }

# Helper first (inside-out signing).
echo "==> Signing helper"
codesign --force --options runtime \
  --entitlements "${HELPER_ENT}" \
  --sign "${DEVELOPER_ID_APPLICATION}" \
  --timestamp \
  "${HELPER}"

echo "==> Signing app"
codesign --force --options runtime \
  --entitlements "${APP_ENT}" \
  --sign "${DEVELOPER_ID_APPLICATION}" \
  --timestamp \
  "${APP}"

echo "==> Verifying"
codesign --verify --deep --strict --verbose=2 "${APP}"
spctl --assess --type execute --verbose=4 "${APP}" \
  || echo "(spctl rejects unnotarised apps; run ./Scripts/notarize.sh next.)"
