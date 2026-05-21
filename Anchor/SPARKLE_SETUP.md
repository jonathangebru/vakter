# Sparkle Integration — Setup Guide

In-app auto-update for Vakter via [Sparkle 2](https://sparkle-project.org).
Same library Bartender, CleanShot X, Tot, and most reputable Mac indie
utilities ship. EdDSA-signed appcast, no central server, no telemetry.

## Why this needs a separate setup step

The Sparkle SwiftPM dependency requires a one-time external fetch from
`github.com/sparkle-project/Sparkle.git`, which the build sandbox blocks
without explicit approval. The four steps below add the dep, generate
the signing key, wire the updater controller, and stand up an appcast.

## 1. Add the SwiftPM dependency

Edit `Package.swift` — add to the top-level `Package(...)` initialiser:

```swift
let package = Package(
    name: "Vakter",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle.git",
            from: "2.6.0"
        ),
    ],
    products: [ ... ],
    targets: [ ... ]
)
```

Then update the `VakterApp` target's deps:

```swift
.executableTarget(
    name: "VakterApp",
    dependencies: [
        "VakterShared",
        .product(name: "Sparkle", package: "Sparkle"),
    ],
    ...
)
```

Resolve: `swift package resolve` (will need network).

## 2. Generate the EdDSA key pair

Sparkle 2 uses EdDSA (Ed25519) signatures for update authenticity. The
private key never leaves your dev machine; the public key ships in the
app and verifies every downloaded update.

```bash
# Build Sparkle's `generate_keys` tool from the resolved checkout
xcrun --find swift  # ensure xcode-select is set
cd .build/checkouts/Sparkle/bin
./generate_keys
```

This writes the private key to your login keychain under
`https://sparkle-project.org` (item name `ed25519`). Copy the printed
**public** key — you'll embed it in Info.plist below.

## 3. Wire `UpdaterController.swift` into VakterApp

Create `Sources/VakterApp/UpdaterController.swift`:

```swift
import SwiftUI
import Sparkle

/// Manages the Sparkle updater lifecycle. Add as an
/// `@StateObject` on the AppDelegate or as a singleton on the
/// menubar controller — needs to live for the app's lifetime.
final class UpdaterController: NSObject {
    let controller: SPUStandardUpdaterController

    override init() {
        // `startingUpdater: true` kicks off the first feed check
        // after Sparkle's polite delay (a few minutes post-launch).
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    /// User explicitly asked "check now". Menubar → "Check for updates…"
    @objc func checkForUpdates(_ sender: Any?) {
        controller.updater.checkForUpdates()
    }
}
```

In `MenuBarController.swift`, add a "Check for Updates…" menu item that
calls `updaterController.checkForUpdates(_:)`.

## 4. Info.plist additions

Add to `Sources/VakterApp/Resources/Info.plist`:

```xml
<key>SUFeedURL</key>
<string>https://vakter.app/appcast.xml</string>

<key>SUPublicEDKey</key>
<string>PASTE_PUBLIC_KEY_FROM_STEP_2_HERE</string>

<key>SUEnableAutomaticChecks</key>
<true/>

<key>SUScheduledCheckInterval</key>
<integer>86400</integer>  <!-- 24h -->

<key>SUAllowsAutomaticUpdates</key>
<true/>
```

## 5. Host the appcast.xml

When you publish a release, you'll generate a signed `appcast.xml` from
the DMG and host it at the SUFeedURL above. The signing step:

```bash
# After building + signing + notarising vakter-1.3.0.dmg:
.build/checkouts/Sparkle/bin/sign_update \
    build/Vakter-1.3.0.dmg \
    > build/sparkle-signature.txt
```

The signature goes into the `<sparkle:edSignature>` attribute of the
appcast entry. Minimal appcast:

```xml
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Vakter</title>
    <item>
      <title>Version 1.3.0</title>
      <pubDate>Mon, 19 May 2026 12:00:00 +0000</pubDate>
      <sparkle:version>1.3.0</sparkle:version>
      <sparkle:shortVersionString>1.3.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>Recovery-grade evidence</h2>
        <ul>
          <li>10s ambient audio capture on alarm</li>
          <li>Tamper-evident event log (SHA-256 Merkle chain)</li>
          <li>Police-ready PDF report</li>
          <li>XPC peer code-sig verification</li>
        </ul>
      ]]></description>
      <enclosure
        url="https://vakter.app/releases/Vakter-1.3.0.dmg"
        sparkle:edSignature="PASTE_SIGNATURE_HERE"
        length="5000000"
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

Upload this XML to `vakter.app/appcast.xml` on every release.

## Release workflow (post-Sparkle)

```bash
# 1. Bump CFBundleShortVersionString + CFBundleVersion in Info.plist
# 2. Build, sign, notarise:
./Scripts/build-app.sh release
./Scripts/sign.sh
./Scripts/notarize.sh
./Scripts/make-dmg.sh
# 3. Sign the update:
.build/checkouts/Sparkle/bin/sign_update build/Vakter-1.3.0.dmg
# 4. Append a new <item> block to appcast.xml with the signature
# 5. Upload Vakter-1.3.0.dmg + appcast.xml to vakter.app
# 6. Existing v1.2 users get the update prompt within 24h
```

## What we didn't do

- **In-app delta updates** (Sparkle 2 supports binary deltas via
  `BinaryDelta`). Worth wiring once we have multiple versions. Saves
  users ~70% download size per update.
- **`SPUUserDriverDelegate` for custom in-app UI**. Default Sparkle
  prompt is fine for v1.3; revisit if we want the update prompt to
  match the Vakter design system.
