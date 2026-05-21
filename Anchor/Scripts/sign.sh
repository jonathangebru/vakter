#!/usr/bin/env bash
# Codesign the Vakter.app bundle and the embedded helper + privileged daemon.
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
APP="${ROOT}/build/Vakter.app"
# Binary filenames inside the bundle have been renamed by build-app.sh
# from the SwiftPM product names to user-visible Vakter names.
APP_BIN="${APP}/Contents/MacOS/Vakter"
HELPER="${APP}/Contents/MacOS/VakterHelper"
DAEMON="${APP}/Contents/MacOS/VakterPrivilegedDaemon"
APP_ENT="${ROOT}/Sources/VakterApp/Resources/Vakter.entitlements"
HELPER_ENT="${ROOT}/Sources/VakterHelper/Resources/VakterHelper.entitlements"
DAEMON_ENT="${ROOT}/Sources/VakterPrivilegedDaemon/Resources/VakterPrivilegedDaemon.entitlements"

[[ -e "${APP}" ]] || { echo "Build first (./Scripts/build-app.sh)"; exit 1; }

# Daemon first (deepest in the bundle, signed inside-out).
echo "==> Signing privileged daemon"
codesign --force --options runtime \
  --entitlements "${DAEMON_ENT}" \
  --sign "${DEVELOPER_ID_APPLICATION}" \
  --timestamp \
  "${DAEMON}"

# Helper next.
echo "==> Signing helper"
codesign --force --options runtime \
  --entitlements "${HELPER_ENT}" \
  --sign "${DEVELOPER_ID_APPLICATION}" \
  --timestamp \
  "${HELPER}"

# (App binary is signed implicitly as part of the bundle below, but we
# could also sign it explicitly — codesign on the .app bundle covers it.)

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
