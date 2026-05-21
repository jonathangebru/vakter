#!/usr/bin/env bash
# Submit Vakter.app for Apple notarisation, wait for the result, and staple
# the ticket back into the bundle.
#
# Credentials live in the user's login keychain under a profile name. The
# default `anchor-notarytool` is kept for backwards compatibility with the
# original Anchor-era setup — the profile is just a keychain entry that
# stores your Apple ID + Team ID + app-specific password, and it doesn't
# care what the binary you're submitting is called. Override with the
# NOTARY_PROFILE env var if you'd rather use a Vakter-named profile.
#
# To create / rotate the profile:
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
APP="${ROOT}/build/Vakter.app"
ZIP="${ROOT}/build/Vakter.zip"

[[ -e "${APP}" ]] || { echo "Build first (./Scripts/build-app.sh)"; exit 1; }

# Confirm the profile exists before doing anything else.
if ! xcrun notarytool history --keychain-profile "${PROFILE}" > /dev/null 2>&1; then
  echo "ERROR: keychain profile '${PROFILE}' is not configured."
  echo "Run xcrun notarytool store-credentials ${PROFILE} ... first."
  exit 1
fi

echo "==> Zipping ${APP} for submission"
rm -f "${ZIP}"
# Clean up any legacy Anchor zip from a pre-rebrand submission too.
rm -f "${ROOT}/build/Anchor.zip"
ditto -c -k --keepParent "${APP}" "${ZIP}"

echo "==> Submitting to Apple (this can take 1–10 minutes)"
xcrun notarytool submit "${ZIP}" \
  --keychain-profile "${PROFILE}" \
  --wait

echo "==> Stapling notarisation ticket into the .app"
# Apple staples at the bundle level (the ticket lives inside the .app's
# `_CodeSignature/CodeResources`, not in each Mach-O). The notary ticket
# covers every binary inside the bundle transitively — no per-Mach-O
# stapling is needed or possible (it returns error 73).
xcrun stapler staple "${APP}"

echo "==> Verifying"
xcrun stapler validate "${APP}"
spctl --assess --type execute --verbose=4 "${APP}"

echo ""
echo "✅ ${APP} is notarised and ready to distribute."
