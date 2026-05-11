#!/usr/bin/env bash
# Build AnchorApp + AnchorHelper via SPM, then assemble Anchor.app bundle.
#
# Output: build/Anchor.app
#
# Usage:
#   ./Scripts/build-app.sh [release|debug]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> swift build --configuration ${CONFIG} (arm64-only)"
swift build --configuration "${CONFIG}" --arch arm64

BIN_DIR="$(swift build --configuration "${CONFIG}" --arch arm64 --show-bin-path)"
APP="${ROOT}/build/Anchor.app"

echo "==> Assembling .app bundle at ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"
mkdir -p "${APP}/Contents/Library/LaunchAgents"

# Main executable
cp "${BIN_DIR}/AnchorApp" "${APP}/Contents/MacOS/AnchorApp"

# Helper executable, embedded as a LaunchAgent program
cp "${BIN_DIR}/AnchorHelper" "${APP}/Contents/MacOS/AnchorHelper"

# Info.plist + entitlements live alongside the app source; copy in
cp "${ROOT}/Sources/AnchorApp/Resources/Info.plist" "${APP}/Contents/Info.plist"
cp "${ROOT}/Sources/AnchorHelper/Resources/LaunchAgent.plist" "${APP}/Contents/Library/LaunchAgents/app.anchor.mac.helper.plist"

# Helper Info.plist sits inside Contents/Library, referenced by SMAppService
# (see SMAppService.agent docs).

echo "==> Bundle assembled."
ls -la "${APP}/Contents/MacOS/"
echo ""
echo "Next:  ./Scripts/sign.sh         to codesign the bundle"
echo "       ./Scripts/notarize.sh     to submit for notarisation"
echo "       open ${APP}               to run locally"
