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

# -------------------------------------------------------------------
# Sparkle.framework — sub-bundles + framework itself
# -------------------------------------------------------------------
# Sparkle ships pre-signed by the Sparkle project, but Apple's
# Developer ID notarisation pipeline requires every nested bundle to
# be re-signed by OUR Developer ID Application identity. The hardened-
# runtime XPC services + Updater.app + Autoupdate helper each have
# their own bundle IDs and need their own codesign invocations.
#
# Order matters: sub-bundles first, then the framework wrapper. If we
# sign the framework first, its _CodeSignature seals over the
# (currently Sparkle-signed) sub-bundles and a subsequent codesign on
# the XPC services breaks that seal. Inside-out only.
SPARKLE_FW="${APP}/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERS_DIR="${SPARKLE_FW}/Versions/B"
if [[ -d "${SPARKLE_FW}" ]]; then
  echo "==> Signing Sparkle sub-bundles"
  # XPC services — hardened-runtime download + install paths.
  for XPC in "${SPARKLE_VERS_DIR}/XPCServices/"*.xpc; do
    [[ -e "${XPC}" ]] || continue
    echo "    + $(basename "${XPC}")"
    codesign --force --options runtime --timestamp \
      --sign "${DEVELOPER_ID_APPLICATION}" \
      "${XPC}"
  done

  # Updater.app — the small GUI shown while the new build is being
  # written to /Applications during an update. It's a real .app
  # bundle so we sign it as one (codesign handles the inner binary
  # implicitly).
  if [[ -d "${SPARKLE_VERS_DIR}/Updater.app" ]]; then
    echo "    + Updater.app"
    codesign --force --options runtime --timestamp \
      --sign "${DEVELOPER_ID_APPLICATION}" \
      "${SPARKLE_VERS_DIR}/Updater.app"
  fi

  # Autoupdate — the standalone helper binary that does the install
  # swap. Lives directly under Versions/B (not inside a bundle).
  if [[ -f "${SPARKLE_VERS_DIR}/Autoupdate" ]]; then
    echo "    + Autoupdate"
    codesign --force --options runtime --timestamp \
      --sign "${DEVELOPER_ID_APPLICATION}" \
      "${SPARKLE_VERS_DIR}/Autoupdate"
  fi

  echo "==> Signing Sparkle.framework"
  # The framework wrapper. After this seal, ANY subsequent codesign on
  # a nested item would invalidate the framework signature — so do it
  # last, and never re-run the sub-bundle loop above without re-running
  # this line too.
  codesign --force --options runtime --timestamp \
    --sign "${DEVELOPER_ID_APPLICATION}" \
    "${SPARKLE_FW}"
fi

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
