# Anchor

> Watch over your Mac. One shortcut, no subscriptions, no bloat.

A native macOS menubar app that locks your MacBook and arms a deterrent alarm
in a single intentional action. Built for Apple Silicon (M1+), macOS 14+.

The full product spec, design, and roadmap live in
`../openspec/changes/bootstrap-anchor/`.

## Project layout

```
Anchor/
├── Package.swift              SwiftPM root — two executables + shared lib
├── Sources/
│   ├── AnchorShared/          Types + XPC protocol used by both targets
│   ├── AnchorApp/             Menubar app (SwiftUI + AppKit NSStatusItem)
│   │   └── Resources/         Info.plist, entitlements
│   └── AnchorHelper/          Background daemon (state machine + observers)
│       └── Resources/         Info.plist, entitlements, LaunchAgent.plist
└── Scripts/
    ├── build-app.sh           Build both targets + assemble Anchor.app
    ├── sign.sh                Codesign the bundle inside-out
    └── notarize.sh            Submit to Apple, wait, staple ticket
```

## Open in Xcode

```bash
cd Anchor
open Package.swift            # Xcode 15+ opens SwiftPM projects natively
```

You'll see two schemes in Xcode: `AnchorApp` and `AnchorHelper`. Hit ▶ to
run AnchorApp — it'll show up in the menu bar.

## Build the .app bundle

The SPM project produces two raw Mach-O executables. The `.app` bundle is
assembled by a script that copies them + the resources + plists into a
proper bundle structure.

```bash
./Scripts/build-app.sh        # → build/Anchor.app
```

## Sign and notarize

The signing identity is **auto-detected** from your keychain — no env vars
needed if you have exactly one "Developer ID Application" cert installed.

Notarisation credentials live in your login keychain under the profile name
`anchor-notarytool`. Create the profile once with:

```bash
xcrun notarytool store-credentials anchor-notarytool \
  --apple-id "<the email tied to your Developer Program>" \
  --team-id  "<your 10-char team ID — find via 'security find-identity -v -p codesigning'>" \
  --password "<app-specific password from appleid.apple.com>"
```

Then every release just runs:

```bash
./Scripts/build-app.sh
./Scripts/sign.sh
./Scripts/notarize.sh
```

After `notarize.sh` succeeds, `build/Anchor.app` is ready to distribute on
your website. The notarisation ticket is stapled into the bundle, so users
can launch the app without an internet connection.

## Day-zero state

Most of the code in this repo is currently **scaffolding stubs**, not
production. Concretely:

| File | State |
|---|---|
| `AnchorShared/*` | Real — types are final |
| `AnchorHelper/main.swift` | Real entry point |
| `AnchorHelper/StateMachine.swift` | Real reducer |
| `AnchorHelper/LidObserver.swift` | Real (ported from spike 3) |
| `AnchorHelper/PowerObserver.swift` | Real (polling) |
| `AnchorHelper/HotkeyObserver.swift` | Real (Carbon HotKey) |
| `AnchorHelper/AudioController.swift` | Real audio path; chirp samples TODO |
| `AnchorHelper/PhotoCapture.swift` | **STUB** — needs week-4 implementation |
| `AnchorHelper/BluetoothObserver.swift` | **STUB** — needs week-3 implementation |
| `AnchorApp/AnchorApp.swift` | Real entry point |
| `AnchorApp/MenuBarController.swift` | Real menubar; XPC wiring TODO |
| `AnchorApp/SettingsRoot.swift` | Shell — tabs render, contents are placeholders |
| Onboarding | Not started — week 5 |
| XPC layer | Not started — week 3 |

Refer to the OpenSpec `tasks.md` for the week-by-week build plan.

## Phase 0 spike record

The CLI-testable spikes that validated the core technical bets are in
`../spikes/`. The full writeup is `../spikes/SPIKE_REPORT.md`:

- ✅ CoreAudio volume + mute control
- ✅ AVSpeechSynthesizer + AVAudioEngine mixing
- ✅ Clamshell state via IORegistry
- ✅ Login-window text storage path (defaults, not nvram)
- ⏳ Touch ID brief-tap detection — deferred to v1.5

Three remaining spikes (SMAppService LaunchAgent, power-button intercept,
App Intents discovery) require this Xcode project to run; they'll be
resolved as part of week-1 of the build.
