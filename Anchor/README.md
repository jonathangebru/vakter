# Vakter

> _Norwegian for "the night-watchmen on a sailing ship" — the crew who stand guard at anchor so the rest of the ship can sleep._

Calm anti-theft for Apple Silicon Macs. One shortcut to arm; the lid, power adapter, and trusted Bluetooth devices become your watch crew; Touch ID disarms in one tap. No subscription, no cloud account, no bloat.

macOS 14+. Apple Silicon (M1+) only.

## What makes Vakter different

| | Vakter | Most other Mac anti-theft alarms |
|---|---|---|
| Closed-lid alarm on Apple Silicon | ✅ via `pmset disablesleep` | ❌ lid often *stops* the alarm |
| Audio routes to internal speakers on alarm | ✅ CoreAudio override | ❌ alarm goes silent into headphones |
| Touch ID disarm at lock screen | ✅ | ❌ |
| Configurable grace window (3–30 s) | ✅ | ❌ fixed |
| Bluetooth trusted-device awareness (informational; never triggers alarm) | ✅ up to 10 peers | ❌ |
| Custom global hotkey | ✅ Carbon `RegisterEventHotKey` | ❌ |
| Defenses audit (FileVault, Find My, Firewall, Gatekeeper, SIP, Touch ID, Login Items, screen lock delay, login-window message, macOS updates, AirDrop, AirPlay receiver, file/media/printer sharing, Remote Login, Remote Management, boot security policy, etc.) | ✅ **20 checks across 5 categories** in the menubar | ❌ |
| Event log with inline photo thumbnails, audio playback, MapKit pin | ✅ | ❌ |
| Tamper-evident Merkle hash chain (SHA-256, CryptoKit) | ✅ every event signed | ❌ |
| Police-ready PDF export (serial, photos, audio paths, chain verification) | ✅ one click | ❌ |
| 10 s ambient audio capture (AAC) on alarm | ✅ | ❌ |
| User-owned cloud evidence backup (Backblaze B2 or pre-signed URL) | ✅ survives wipe | ❌ |
| Email evidence delivery in addition to iMessage | ✅ | ❌ |
| 9 alarm sounds including locale-specific (Japanese two-tone, European nee-naw) | ✅ | ❌ |
| Voice cue in 10 locales (en, nl, no, de, fr, es, it, ja, ko, zh) | ✅ | ❌ |
| Find My token watcher — high-confidence theft signal, skips grace | ✅ | ❌ |
| Apple ID change watcher — high-confidence theft signal, skips grace | ✅ | ❌ |
| Auto-arm engine (geofence, Wi-Fi SSID, idle timer, daily schedule) | ✅ | ❌ |
| Stealth lock-screen takeover ("STOLEN — please call…") on alarm | ✅ v1.4.3 | ❌ |
| macOS Shortcuts integration (`ArmVakterIntent`, `SetVakterModeIntent`) | ✅ v1.4.2 | ❌ |
| iOS + Apple Watch companion (CloudKit-backed) | ⏳ source complete; provisioning in progress | ❌ |
| Sparkle 2 auto-update | ⏳ rolling out with v1.5 | varies |
| Silent one-time approval (no per-arm prompt) | ✅ `SMAppService.daemon` | ❌ |
| Notarised .dmg that just works | ✅ | ⚠️ several competitors are open-source-only |
| Price | **$29 one-time** | $11.99/yr or worse |

## Repository layout

```
Vakter/
├── Package.swift              SwiftPM root — 5 targets
├── Sources/
│   ├── AnchorShared/          Types + XPC protocols + persistent stores
│   │                          (internal Swift identifiers keep the
│   │                          `Anchor` prefix — refactor deferred for
│   │                          a follow-up pure-rename commit)
│   ├── AnchorApp/             Menubar app (SwiftUI + AppKit)
│   │   └── Resources/         Info.plist (CFBundleName=Vakter), entitlements
│   ├── AnchorHelper/          Background helper (state machine + observers)
│   │   └── Resources/         Info.plist + LaunchAgent.plist (Vakter labels)
│   ├── AnchorHelperPoke/      Dev-only XPC poker CLI
│   ├── AnchorPrivilegedExec/  Tiny C bridge for AuthorizationServices fallback
│   └── AnchorPrivilegedDaemon/Root LaunchDaemon — toggles pmset disablesleep
│       └── Resources/         Info.plist + LaunchDaemon.plist (Vakter labels)
└── Scripts/
    ├── build-app.sh           → build/Vakter.app
    ├── sign.sh                Codesign inside-out
    ├── notarize.sh            Submit + staple
    └── make-dmg.sh            → build/Vakter.dmg (signed, stapled)
```

User-visible identity is **Vakter** everywhere:

- Bundle name in `/Applications/Vakter.app`
- `CFBundleName` / `CFBundleDisplayName` = "Vakter"
- Bundle IDs: `app.vakter.mac` / `.helper` / `.privileged-helper`
- Mach service names: `app.vakter.mac.helper.xpc` / `.privileged-helper.xpc`
- All UI copy + NSLog tags + macOS permission dialogs

The internal Swift type names (`AnchorState`, `AnchorMode`, `AnchorDesign`, etc.) still carry the `Anchor` prefix — they are referenced nowhere a user can see and renaming them is mechanical work without user benefit. Tracked for a follow-up commit.

## Open in Xcode

```bash
cd Vakter
open Package.swift            # Xcode 15+ opens SwiftPM projects natively
```

Schemes: `AnchorApp`, `AnchorHelper`, `AnchorHelperPoke`, `AnchorPrivilegedDaemon`. Hit ▶ on `AnchorApp` to run the menubar app.

`AnchorHelperPoke` is a dev-only CLI that exercises the helper's XPC protocol end-to-end:

```bash
swift build && "$(swift build --show-bin-path)/AnchorHelperPoke"
```

## Build, sign, ship

```bash
./Scripts/build-app.sh        # → build/Vakter.app
./Scripts/sign.sh             # codesign inside-out, hardened runtime
./Scripts/notarize.sh         # submit to Apple, wait, staple the .app
./Scripts/make-dmg.sh         # → build/Vakter.dmg (signed, attempts staple)
```

### Important: install to `/Applications` for daemon approval

`SMAppService.daemon` (which installs the root LaunchDaemon for the closed-lid alarm path) **only registers when the host app is located in `/Applications`**. From any other location it silently fails with "Operation not permitted." The LaunchAgent helper works fine outside `/Applications`; only the daemon has this rule.

For dev iteration:

```bash
./Scripts/build-app.sh
./Scripts/sign.sh
rm -rf /Applications/Vakter.app
cp -R build/Vakter.app /Applications/Vakter.app
open /Applications/Vakter.app
```

The first launch will open **System Settings → General → Login Items & Extensions**. Toggle "Vakter" on under "Allow in the Background." After that, arming silently disables sleep through the daemon — no per-arm Touch ID prompt.

## Notarisation setup

Signing identity is **auto-detected** from your keychain — no env vars needed if you have one "Developer ID Application" cert installed.

Notarisation credentials live in your login keychain under the profile name `vakter-notarytool`:

```bash
xcrun notarytool store-credentials vakter-notarytool \
  --apple-id "<email tied to your Developer Program>" \
  --team-id  "<10-char team ID — find via security find-identity -v -p codesigning>" \
  --password "<app-specific password from appleid.apple.com>"
```

`make-dmg.sh` reuses the same profile when stapling the DMG.

## Migration from Anchor (pre-rebrand)

If you ran an Anchor-era build of this app, your settings + event log live at `~/Library/Application Support/Anchor/`. On the first launch of a Vakter build, `AnchorConstants.supportDirectoryURL` migrates that directory in place to `~/Library/Application Support/Vakter/`. The migration is one-shot and idempotent.

The previous Login Items approvals (helper + privileged daemon) registered under the old `app.anchor.mac.*` bundle IDs are still listed in System Settings. You can leave them or remove them; Vakter's `PrivilegedDaemonManager` registers the new `app.vakter.mac.*` daemon on first launch and surfaces the approval prompt.
