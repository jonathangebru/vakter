#!/usr/bin/env bash
# Build the Vakter binaries via SPM, then assemble the Vakter.app bundle.
#
# Output: build/Vakter.app
#
# Note on naming: SwiftPM compiles products with these target names —
#
#   VakterApp, VakterHelper, VakterHelperPoke, VakterPrivilegedDaemon
#
# We *rename* each binary on copy into the .app bundle so that
# Contents/MacOS/ contains user-visible names (Vakter, VakterHelper,
# VakterPrivilegedDaemon). This is what macOS reads when it shows the
# privileged-auth dialog title and similar surfaces.
#
# Usage:
#   ./Scripts/build-app.sh [release|debug]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# -------------------------------------------------------------------
# Team ID templating
# -------------------------------------------------------------------
# The daemon's Info.plist contains an SMAuthorizedClients code-requirement
# that pins the helper's signing identity by Team ID. We don't want to
# hardcode anyone's Team ID in source — instead we keep a placeholder
# `__TEAM_ID__` in the plist on disk, then substitute it just before
# `swift build` (so the linker bakes the resolved ID into the binary's
# `__TEXT,__info_plist` section), and restore the placeholder afterwards
# so source-tree state is preserved.
#
# Resolves the Team ID from the active Developer ID Application identity
# in the user's keychain. If the user has multiple signing certs, the
# `CODESIGN_IDENTITY` env var lets them pin a specific one.
DAEMON_INFO_PLIST="${ROOT}/Sources/VakterPrivilegedDaemon/Resources/Info.plist"
DAEMON_INFO_BACKUP="${DAEMON_INFO_PLIST}.tpl"

resolve_team_id() {
  # If user pinned an identity, use its Team ID.
  if [[ -n "${TEAM_ID:-}" ]]; then
    echo "${TEAM_ID}"; return
  fi
  # Else parse the first Developer ID Application cert. The CN format is
  #   "Developer ID Application: Full Name (TEAMID)"
  local line
  line="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application:" | head -1)"
  if [[ -z "${line}" ]]; then
    echo "ERR_NO_CERT"
    return
  fi
  # Extract the parenthesised TEAMID.
  echo "${line}" | sed -nE 's/.*\(([A-Z0-9]+)\).*/\1/p'
}

TEAM_ID_RESOLVED="$(resolve_team_id)"
if [[ "${TEAM_ID_RESOLVED}" == "ERR_NO_CERT" || -z "${TEAM_ID_RESOLVED}" ]]; then
  echo "==> WARNING: no Developer ID Application cert found in keychain."
  echo "    Building unsigned — the privileged daemon will refuse all"
  echo "    XPC connections (no Team ID to validate against). Add a"
  echo "    Developer ID cert and rerun, or set TEAM_ID=XXXXXXXXXX env."
  TEAM_ID_RESOLVED="UNSIGNED__"
else
  echo "==> Using Team ID: ${TEAM_ID_RESOLVED}"
fi

# Always restore the source-tree plist on exit (success or failure).
restore_daemon_info() {
  if [[ -f "${DAEMON_INFO_BACKUP}" ]]; then
    mv "${DAEMON_INFO_BACKUP}" "${DAEMON_INFO_PLIST}"
  fi
}
trap restore_daemon_info EXIT INT TERM

# Snapshot the source-tree plist, then substitute the placeholder.
cp "${DAEMON_INFO_PLIST}" "${DAEMON_INFO_BACKUP}"
sed -i '' "s/__TEAM_ID__/${TEAM_ID_RESOLVED}/g" "${DAEMON_INFO_PLIST}"

echo "==> swift build --configuration ${CONFIG} (arm64-only)"
swift build --configuration "${CONFIG}" --arch arm64

BIN_DIR="$(swift build --configuration "${CONFIG}" --arch arm64 --show-bin-path)"
APP="${ROOT}/build/Vakter.app"

echo "==> Assembling .app bundle at ${APP}"
rm -rf "${APP}"
# Also clean up the legacy Anchor.app if present from a pre-rebrand build.
rm -rf "${ROOT}/build/Anchor.app"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"
mkdir -p "${APP}/Contents/Frameworks"
mkdir -p "${APP}/Contents/Library/LaunchAgents"
mkdir -p "${APP}/Contents/Library/LaunchDaemons"

# Main executable — copied with its bundle-visible name "Vakter".
# CFBundleExecutable in Info.plist must match this filename exactly.
cp "${BIN_DIR}/VakterApp" "${APP}/Contents/MacOS/Vakter"

# User-level LaunchAgent helper — renamed to VakterHelper so the
# privileged-auth dialog (when fallback is triggered) reads "Vakter"
# (driven by the embedded CFBundleName) rather than the SwiftPM
# product name.
cp "${BIN_DIR}/VakterHelper" "${APP}/Contents/MacOS/VakterHelper"

# Privileged root daemon — same rename.
cp "${BIN_DIR}/VakterPrivilegedDaemon" "${APP}/Contents/MacOS/VakterPrivilegedDaemon"

# Info.plist + entitlements live alongside the app source; copy in
cp "${ROOT}/Sources/VakterApp/Resources/Info.plist" "${APP}/Contents/Info.plist"

# App icon (.icns).
if [[ -f "${ROOT}/Sources/VakterApp/Resources/AppIcon.icns" ]]; then
  cp "${ROOT}/Sources/VakterApp/Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
fi

# -------------------------------------------------------------------
# Sparkle 2 framework bundling
# -------------------------------------------------------------------
# The Sparkle binary xcframework is resolved by SwiftPM into
#   .build/<triple>/<config>/Sparkle.framework
# but SPM does NOT relocate it into the .app bundle — that's a Xcode-
# specific build phase ("Copy Frameworks"). We do it by hand here.
#
# Layout we produce (matches every other Mac app that ships Sparkle):
#
#   Vakter.app/Contents/Frameworks/Sparkle.framework
#     ├── Versions/B/Sparkle                         (the dylib)
#     ├── Versions/B/Updater.app                     (used during install)
#     ├── Versions/B/Autoupdate                      (legacy installer helper)
#     ├── Versions/B/XPCServices/Downloader.xpc      (hardened-runtime download)
#     └── Versions/B/XPCServices/Installer.xpc       (hardened-runtime install)
#
# After copying, we also add `@executable_path/../Frameworks` to the
# Vakter binary's LC_RPATH so it can resolve `@rpath/Sparkle.framework`
# at launch. SwiftPM only emits `@loader_path` which is empty for the
# top-level binary at runtime.
SPM_SPARKLE="${BIN_DIR}/Sparkle.framework"
if [[ -d "${SPM_SPARKLE}" ]]; then
  echo "==> Bundling Sparkle.framework into Contents/Frameworks/"
  # `cp -RH` follows the symlinks at the top level (so Versions/Current
  # → B resolves) but preserves the framework's internal symlink
  # structure. Sparkle's framework is the standard versioned-bundle
  # layout — losing the symlinks breaks dyld.
  cp -R "${SPM_SPARKLE}" "${APP}/Contents/Frameworks/Sparkle.framework"
  # Add the rpath so @rpath/Sparkle.framework/... resolves to
  # Contents/Frameworks/. install_name_tool prints a warning if the
  # rpath already exists; suppress with `|| true` so re-runs of
  # build-app.sh stay quiet.
  install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "${APP}/Contents/MacOS/Vakter" 2>/dev/null || true
else
  echo "==> WARNING: Sparkle.framework not found at ${SPM_SPARKLE}"
  echo "    Auto-update will be disabled in this build. Run"
  echo "    'swift package resolve' to fetch Sparkle, then rebuild."
fi

# Embedded Developer ID provisioning profile.
#
# REQUIRED whenever the app's entitlements include a "premium" capability
# (iCloud, CloudKit, Apple Push, app groups, etc). The macOS kernel
# validates entitlement values against this profile at spawn time and
# refuses to launch (error 153 "Launchd job spawn failed") if a premium
# entitlement is claimed without a matching provisioning profile.
#
# Provisioned in Apple Developer Portal → Profiles → Developer ID
# Application → app.vakter.mac. Embedded here so every fresh build picks
# it up automatically rather than relying on a hand-copy into /Applications.
if [[ -f "${ROOT}/Sources/VakterApp/Resources/embedded.provisionprofile" ]]; then
  cp "${ROOT}/Sources/VakterApp/Resources/embedded.provisionprofile" \
     "${APP}/Contents/embedded.provisionprofile"
fi

# Pre-rendered voice clips (Piper + Apple say at build time, see
# Scripts/render-voices.sh). Bundled as Resources/voices/<locale>/<phrase>.m4a
# so the AudioController can play them via AVAudioPlayer with zero
# runtime TTS dependency.
if [[ -d "${ROOT}/Sources/VakterApp/Resources/voices" ]]; then
  cp -R "${ROOT}/Sources/VakterApp/Resources/voices" "${APP}/Contents/Resources/voices"
fi

# Sample-backed alarm sounds (Sonniss GDC 2026 — Federico Soler
# "Effective Trailer Alarms Vol. 2"). Three 30-second AAC clips at
# 96 kbps for the new sample-backed AlarmSound cases (pulseAlarm,
# rhythmicKlaxon, urgentBeacon). Played via AVAudioPlayer-loop
# rather than the AVAudioEngine synth path. License: Sonniss GDC
# bundle terms — royalty-free, no attribution, commercial use OK.
if [[ -d "${ROOT}/Sources/VakterApp/Resources/sounds" ]]; then
  cp -R "${ROOT}/Sources/VakterApp/Resources/sounds" "${APP}/Contents/Resources/sounds"
fi

# LaunchAgent + LaunchDaemon plists — filenames must match the new
# Vakter bundle IDs (SMAppService.agent/daemon resolves by Label),
# and their BundleProgram keys must point to the renamed binaries.
cp "${ROOT}/Sources/VakterHelper/Resources/LaunchAgent.plist" \
   "${APP}/Contents/Library/LaunchAgents/app.vakter.mac.helper.plist"
cp "${ROOT}/Sources/VakterPrivilegedDaemon/Resources/LaunchDaemon.plist" \
   "${APP}/Contents/Library/LaunchDaemons/app.vakter.mac.privileged-helper.plist"

# NOTE: We do NOT run appintentsmetadataprocessor here. It requires
# `.swiftconstvalues` files emitted by the Swift compiler per source file,
# which SPM doesn't produce.

echo "==> Bundle assembled."
ls -la "${APP}/Contents/MacOS/"
echo ""
echo "Next:  ./Scripts/sign.sh         to codesign the bundle"
echo "       ./Scripts/notarize.sh     to submit for notarisation"
echo "       open ${APP}               to run locally"
