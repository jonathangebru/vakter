#!/usr/bin/env bash
# Submit Anchor.app for Apple notarisation, wait for the result, and staple
# the ticket back into the bundle.
#
# Credentials live in the user's login keychain under the profile name
# `anchor-notarytool`. To create / rotate the profile:
#
#   xcrun notarytool store-credentials anchor-notarytool \
#     --apple-id   "<your-developer-apple-id>" \
#     --team-id    "<your-10-char-team-id>" \
#     --password   "<app-specific-password-from-appleid.apple.com>"
#
# Requirements:
#   - The Developer ID Application identity must be in your keychain
#   - The app must already be signed (./Scripts/sign.sh)
#
# Usage:
#   ./Scripts/notarize.sh
set -euo pipefail

PROFILE="${NOTARY_PROFILE:-anchor-notarytool}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${ROOT}/build/Anchor.app"
ZIP="${ROOT}/build/Anchor.zip"

[[ -e "${APP}" ]] || { echo "Build first (./Scripts/build-app.sh)"; exit 1; }

# Confirm the profile exists before doing anything else.
if ! xcrun notarytool history --keychain-profile "${PROFILE}" > /dev/null 2>&1; then
  echo "ERROR: keychain profile '${PROFILE}' is not configured."
  echo "Run xcrun notarytool store-credentials ${PROFILE} ... first."
  exit 1
fi

echo "==> Zipping ${APP} for submission"
rm -f "${ZIP}"
ditto -c -k --keepParent "${APP}" "${ZIP}"

echo "==> Submitting to Apple (this can take 1–10 minutes)"
xcrun notarytool submit "${ZIP}" \
  --keychain-profile "${PROFILE}" \
  --wait

echo "==> Stapling notarisation ticket into the .app"
xcrun stapler staple "${APP}"

echo "==> Verifying"
xcrun stapler validate "${APP}"
spctl --assess --type execute --verbose=4 "${APP}"

echo ""
echo "✅ ${APP} is notarised and ready to distribute."
