#!/usr/bin/env bash
# Package the signed, notarised Anchor.app into a distributable .dmg
# that a friend can download, open, and drag into /Applications.
#
# Prerequisites (run in order before this script):
#   ./Scripts/build-app.sh     → produces build/Anchor.app
#   ./Scripts/sign.sh          → signs everything inside the bundle
#   ./Scripts/notarize.sh      → submits to Apple + staples the ticket
#
# Output: build/Anchor.dmg
#
# The .dmg layout is the standard Mac convention:
#   - Anchor.app (the bundle, draggable)
#   - Applications  (a symlink the user drags into)
# So friends just open the .dmg and drag the icon to the symlink.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${ROOT}/build/Anchor.app"
DMG="${ROOT}/build/Anchor.dmg"
STAGING="${ROOT}/build/dmg-staging"

[[ -e "${APP}" ]] || {
    echo "ERROR: ${APP} not found. Build it first:"
    echo "  ./Scripts/build-app.sh && ./Scripts/sign.sh && ./Scripts/notarize.sh"
    exit 1
}

# Friendly warning if the bundle isn't notarised. The .dmg still works
# locally for the developer, but friends who download it will see a
# Gatekeeper warning ("Apple cannot check…") unless we've notarised.
if ! /usr/bin/xcrun stapler validate "${APP}" >/dev/null 2>&1; then
    echo "⚠  WARNING: ${APP} has no notarisation ticket stapled."
    echo "   Friends who download this will hit a Gatekeeper warning."
    echo "   Run ./Scripts/notarize.sh first if you want a clean install."
    read -r -p "   Continue anyway? [y/N] " response
    case "$response" in [Yy]*) ;; *) exit 1 ;; esac
fi

echo "==> Building staging directory at ${STAGING}"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
cp -R "${APP}" "${STAGING}/Anchor.app"
ln -s /Applications "${STAGING}/Applications"

# Optional: a small README inside the .dmg explaining what to do.
cat > "${STAGING}/Read me first.txt" << 'EOF'
Anchor

1. Drag Anchor into the Applications folder shortcut next to it.
2. Open Anchor from your Applications folder.
3. The first launch will ask you to approve a Login Item — say yes.
4. You'll be walked through a brief setup.

Anchor lives in your menu bar (look for the dark anchor icon top
right). Press the shortcut whenever you walk away from your Mac.
EOF

echo "==> Creating .dmg"
rm -f "${DMG}"

# hdiutil create — produces an APFS-formatted compressed disk image.
# Note: macOS 11+ prefers UDZO for compatibility across Intel + ARM.
/usr/bin/hdiutil create \
    -volname "Anchor" \
    -srcfolder "${STAGING}" \
    -ov \
    -format UDZO \
    "${DMG}" >/dev/null

echo "==> Cleaning up staging"
rm -rf "${STAGING}"

# Sign the .dmg itself with the same Developer ID. Optional but
# improves Gatekeeper UX on download.
if command -v codesign >/dev/null 2>&1 && [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    echo "==> Signing .dmg"
    codesign --sign "${DEVELOPER_ID_APPLICATION}" --timestamp "${DMG}" >/dev/null
elif [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    # Try to auto-detect (same approach as sign.sh).
    DEV_ID="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
    if [[ -n "${DEV_ID}" ]]; then
        echo "==> Signing .dmg (auto-detected identity: ${DEV_ID})"
        codesign --sign "${DEV_ID}" --timestamp "${DMG}" >/dev/null
    fi
fi

echo ""
echo "✅ Wrote ${DMG} ($(du -h "${DMG}" | cut -f1))"
echo ""
echo "Share this file by AirDrop, Slack, Dropbox, or upload to your"
echo "website. To install, the recipient double-clicks the .dmg and"
echo "drags Anchor into Applications."
echo ""
echo "Want to also notarise the .dmg itself (some download paths"
echo "trigger an extra Gatekeeper pass on the .dmg)? Run:"
echo "    xcrun notarytool submit \"${DMG}\" \\"
echo "        --keychain-profile anchor-notarytool --wait"
echo "    xcrun stapler staple \"${DMG}\""
