# Vakter iOS Companion + Apple Watch — Setup Guide

The Mac app, iPhone app, and Apple Watch app talk through the user's
own private CloudKit database. No Vakter server. The setup below
covers the entitlements, container provisioning, and one-time CloudKit
schema deployment.

## Prerequisites

- Active Apple Developer account (the same one that signs the Mac app —
  Team ID `9TA5GB5UJH`)
- macOS with Xcode 15+
- `brew install xcodegen` (one-time)

## 1. Generate the Xcode project

```bash
cd iOS
xcodegen generate
open VakterCompanion.xcodeproj
```

`project.yml` declares two targets:
- `VakterCompanion` — iOS app, deployment target 17.0
- `VakterWatch` — watchOS app, deployment target 10.0, embedded in
  the iOS bundle

## 2. CloudKit container — one-time provisioning

In [Apple Developer → Identifiers → iCloud Containers](https://developer.apple.com/account/resources/identifiers/list/cloudContainer):

1. Click "+" to add a new container.
2. Description: `Vakter Shared`
3. Identifier: `iCloud.app.vakter.shared` (exactly — must match the
   `containerID` constant in `CloudKitConstants` in
   `Sources/VakterShared/CloudKitEventRecord.swift`).
4. Save.

Then attach it to **all three** bundle identifiers:

| Target | Bundle ID | Capability |
|---|---|---|
| Mac app | `app.vakter.mac` | iCloud → CloudKit, container `iCloud.app.vakter.shared` |
| iOS app | `app.vakter.companion` | iCloud → CloudKit, container `iCloud.app.vakter.shared` |
| Watch app | `app.vakter.companion.watchkitapp` | (inherits via WatchConnectivity, no separate iCloud capability needed) |

In Developer Portal → Identifiers → App IDs, for each of the three:
- Enable "iCloud" capability
- Click "Configure" and tick the `iCloud.app.vakter.shared` container

## 3. Deploy the CloudKit schema

CloudKit needs to know about our record types. Xcode handles this
auto-magically on first save in dev — but you can be explicit:

1. In Xcode, open `VakterCompanion`, build & run on the iOS simulator
   while signed into iCloud.
2. Use the app to issue a "sendArm" command. Xcode will create the
   `VakterCommand` record type on first write.
3. Visit [CloudKit Console](https://icloud.developer.apple.com) →
   `iCloud.app.vakter.shared` → Development environment → Schema.
4. Confirm three record types exist (Xcode auto-creates them):
   - `VakterSnapshot` — fields: state, mode, deviceName, updatedAt,
     loanerExpiresAt
   - `VakterEvent` — fields: timestamp, fromState, toState, mode,
     trigger, deviceName, photoFilenames, audioFilenames, locationLat,
     locationLon, eventHash, previousEventHash
   - `VakterCommand` — fields: action, issuedAt, origin
5. Add an index on `VakterSnapshot.updatedAt` and `VakterEvent.timestamp`
   (both `Queryable + Sortable`). The iOS app's queries depend on these.
6. When ready to ship, click "Deploy Schema Changes…" to promote
   Development → Production.

## 4. Mac-side entitlement

Edit `Sources/VakterApp/Resources/Vakter.entitlements` to add:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.app.vakter.shared</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
```

Rebuild + re-sign + re-notarize the Mac app. `CloudKitPublisher` will
start publishing on first launch after the entitlement is live.

## 5. Push notifications (silent push for live updates)

CloudKit subscriptions deliver silent pushes to keep the iOS app's
state fresh. Already covered by the `aps-environment: development`
entitlement in `project.yml`. For production builds change to
`production`.

## 6. App Store provisioning

Status as of v1.4.4 (issue #28 wire-up):

- Apple Developer Portal: App IDs `app.vakter.companion` (iCloud + Push
  Notifications + App Groups) and `app.vakter.companion.watchkitapp`
  are **registered**.
- CloudKit container `iCloud.app.vakter.shared` is **attached** to the
  iOS App ID (pre-existing from Mac-side v1.4.2 work).
- App Store Connect record is **created**.
- TestFlight internal-tester group `Vakter Core Testers` is **set up**.
- Provisioning Profile: `CODE_SIGN_STYLE = Automatic` in `project.yml`.
  Xcode pulls a matching profile on archive — no manual download needed
  for first-party Apple-ID flows. Release-warden handles archive +
  upload from a machine with the keychain identity.

## 7. Generating + building the Xcode project (Mac engineer)

```bash
brew install xcodegen   # one-time
cd iOS
xcodegen generate       # rebuilds .xcodeproj from project.yml
xcodebuild \
    -project VakterCompanion.xcodeproj \
    -scheme VakterCompanion \
    -configuration Debug \
    -destination 'generic/platform=iOS' \
    -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO \
    build
```

**Why `generic/platform=iOS` and not the Simulator destination?** The
embedded Watch app forces xcodebuild to pair iOS + watchOS destinations;
building for `iOS Simulator` fails unless the watchOS Simulator runtime
is also installed (~3 GB download). The `generic/platform=iOS` device
destination uses the watchOS SDK directly, which is included in stock
Xcode without a separate runtime install. This is the same path
`xcodebuild archive` takes — verifying the build here gives confidence
the archive will succeed on release-warden's machine.

**Generated files** (`Info.plist`, `*.entitlements`, `.xcodeproj/`) are
git-ignored. `project.yml` is the single source of truth; xcodegen
materialises the rest on every `xcodegen generate`.

## 8. Archive + TestFlight upload (Release warden)

This step happens on release-warden's machine where the Apple ID and
app-specific password are in the login keychain.

```bash
xcodebuild archive \
    -project iOS/VakterCompanion.xcodeproj \
    -scheme VakterCompanion \
    -archivePath build/VakterCompanion.xcarchive \
    -destination 'generic/platform=iOS'
xcodebuild -exportArchive \
    -archivePath build/VakterCompanion.xcarchive \
    -exportPath build/VakterCompanion-ipa \
    -exportOptionsPlist Scripts/ios-exportoptions.plist
xcrun altool --upload-app \
    --type ios \
    --file build/VakterCompanion-ipa/VakterCompanion.ipa \
    --username "$APPLE_ID" \
    --password "@keychain:AC_PASSWORD"
```

Release-warden will create the `ios-exportoptions.plist` once they have
the actual archive in hand — it specifies `app-store-connect` as method,
the team ID (`9TA5GB5UJH`), and `automatic` signing style. The file
holds no secrets and is safe to commit when it lands.

## Troubleshooting

- **iOS app shows "iCloud not signed in"** even when iCloud is active
  → check Settings → iCloud → iCloud Drive is on; "Vakter" app must
  be toggled on in Apps Using iCloud.
- **CloudKit `notAuthenticated` error** in console → container ID
  mismatch between Mac app and iOS app. Both must say
  `iCloud.app.vakter.shared` exactly.
- **`serverRecordChanged` errors on snapshot writes** → harmless; the
  Mac publisher already retries with the fresh change tag.
- **Watch app shows blank "—"** → make sure the iOS app has been
  launched at least once on the paired iPhone so the
  WatchConnectivity session has activated.

## What we explicitly do NOT need on the iPhone

- No Vakter account
- No password
- No Vakter server URL config
- No bucket credentials (those stay on the Mac for upload only)

The iCloud account is the only identity. Two-factor auth is the user's
existing Apple ID 2FA. That's the whole authentication surface.
