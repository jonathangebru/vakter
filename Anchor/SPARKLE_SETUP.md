# Sparkle Integration — Setup Guide

In-app auto-update for Vakter via [Sparkle 2](https://sparkle-project.org).
Same library Bartender, CleanShot X, Tot, and most reputable Mac indie
utilities ship. EdDSA-signed appcast, no central server, no telemetry.

## Successfully wired (vkt-22, May 2026)

Sparkle 2 is wired into the app. What landed:

- **SwiftPM dep**: `Sparkle ~> 2.6.0`, resolves to **2.9.2** at lock-file
  pin time. Defined in `Package.swift` at the top-level `dependencies:`
  array; linked into the `VakterApp` target only (the helper + privileged
  daemon do NOT link Sparkle — keeps their codesign envelopes minimal).
- **Updater wiring**: `Sources/VakterApp/UpdaterController.swift` owns a
  `SPUStandardUpdaterController` with `startingUpdater: true`.
  Instantiated in `AppDelegate.applicationDidFinishLaunching` after the
  helper handshake. The same instance is injected into the Settings
  window via `UpdaterControllerBox` (an `ObservableObject` adapter so
  the SwiftUI Toggle / Button bind cleanly).
- **Settings UI**: Settings → General → "Software updates" card.
  Contains a "Automatically check for updates" toggle, a "Check now…"
  button, the current version + build, the last-checked relative time,
  and the live feed URL.
- **Info.plist keys**: `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomatic-
  Checks`, `SUScheduledCheckInterval` (86400s = 24h), `SUEnableDownload-
  edReleaseNotes`, `SUEnableAutomaticUpdates` (NO — user must click).
- **Codesign**: `Scripts/sign.sh` now signs the Sparkle XPC sub-bundles
  (`Downloader.xpc`, `Installer.xpc`), `Updater.app`, and `Autoupdate`,
  then the framework wrapper, then the outer .app — strictly inside-
  out per Apple's nested-bundle rules.
- **Bundle copy**: `Scripts/build-app.sh` copies `Sparkle.framework`
  from SwiftPM's build output into `Vakter.app/Contents/Frameworks/`
  and adds `@executable_path/../Frameworks` to the binary's LC_RPATH.
- **Appcast**: `Website/appcast.xml` exists with a seed entry for
  v1.4.2. The seed entry has a `PLACEHOLDER_…` `sparkle:edSignature`
  so Sparkle rejects it until the human signs the first real release
  (see "Release workflow" below).

### One human-only step still required: generate the EdDSA key pair

The `Info.plist` key `SUPublicEDKey` currently holds the literal string
`PLACEHOLDER_PUBLIC_KEY_RUN_GENERATE_KEYS_FIRST`. The first developer to
prep a real release must:

```bash
# Resolve the dep if you haven't already.
swift package resolve

# Run Sparkle's keygen tool. This writes the PRIVATE key to your
# login keychain under sparkle-project.org / ed25519 and PRINTS the
# PUBLIC key (base64). The private key never leaves the keychain.
.build/artifacts/sparkle/Sparkle/bin/generate_keys

# Sample output (yours will differ):
#   Public key (base64): aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789abcdefghij=
#   (Stored in keychain under "https://sparkle-project.org" / ed25519.)
```

Then paste the printed public key into
`Sources/VakterApp/Resources/Info.plist`, replacing the placeholder
string. Commit + ship.

**Do this exactly once.** Rotating the key invalidates every previously-
signed release and forces every existing user to do a manual reinstall.
Treat the keychain entry like a code-signing certificate.

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

The appcast file lives at `Website/appcast.xml` so it ships with the
static site through the same Cloudflare Pages deploy as the marketing
pages — no separate hosting step.

When you publish a release, you'll generate a signed appcast entry from
the DMG. The signing step (Sparkle 2.9.x):

```bash
# After building + signing + notarising Vakter-X.Y.Z.dmg:
.build/artifacts/sparkle/Sparkle/bin/sign_update \
    build/Vakter-X.Y.Z.dmg
# Output is a single line:
#   sparkle:edSignature="AbCd…" length="4823104"
# Paste both attributes verbatim into the new <enclosure …/> in
# Website/appcast.xml.
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

Commit + push `Website/appcast.xml`; Cloudflare Pages auto-deploys it
to `https://vakter.app/appcast.xml`.

## Release workflow (post-Sparkle)

```bash
# 1. Bump CFBundleShortVersionString + CFBundleVersion in
#    Sources/VakterApp/Resources/Info.plist
# 2. Build, sign, notarise, package:
./Scripts/build-app.sh release
./Scripts/sign.sh
./Scripts/notarize.sh
./Scripts/make-dmg.sh
# 3. Sign the update with Sparkle's EdDSA tool:
.build/artifacts/sparkle/Sparkle/bin/sign_update build/Vakter-X.Y.Z.dmg
# 4. PREPEND a new <item> block to Website/appcast.xml — newest first.
#    Sparkle reads in document order; the top entry is what users see.
#    Update `url=`, `sparkle:shortVersionString=`, `sparkle:version=`
#    (monotonic build counter), `sparkle:edSignature=`, `length=`,
#    and the human <description>.
# 5. Commit + push. Cloudflare Pages redeploys.
# 6. Existing users get the update prompt on their next Sparkle
#    check — within 24h, or immediately if they hit "Check now"
#    in Settings → General → Software updates.
```

### How to verify a signature locally

After running `sign_update`, you can re-verify the output against the
public key by passing the signature back through Sparkle's verifier:

```bash
.build/artifacts/sparkle/Sparkle/bin/sign_update --verify \
    build/Vakter-X.Y.Z.dmg "AbCd…the_signature…=="
# exits 0 if valid, non-zero otherwise.
```

This is the same check Sparkle performs on the user's machine before
unpacking — running it locally catches mistakes (wrong file path,
truncated signature, wrong key in keychain) before they ship.

## What we didn't do

- **In-app delta updates** (Sparkle 2 supports binary deltas via
  `BinaryDelta`). Worth wiring once we have multiple versions. Saves
  users ~70% download size per update.
- **`SPUUserDriverDelegate` for custom in-app UI**. Default Sparkle
  prompt is fine for v1.3; revisit if we want the update prompt to
  match the Vakter design system.
