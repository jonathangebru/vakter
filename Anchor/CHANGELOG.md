# Vakter Changelog

Technical changelog maintained by the release warden. User-facing changelog lives at `Website/changelog/index.html`.

---

## v1.4.3 — 2026-05-21

**Notarization submission ID:** a8ba670e-6757-4226-a904-7f2bede13d01
**CFBundleVersion:** 3
**Merged PRs:** #43 (ticket #27), #44 (ticket #26), #46 (ticket #24)
**Version bump rationale:** Patch bump (1.4.2 → 1.4.3). Three additive features; none breaking, none requiring schema migration. Pre-launch policy: minor (1.5.0) reserved for the first post-launch feature cycle.

### Feature A.8 — Defenses checklist over XPC (ticket #27, PR #43)

`DefensesScheduler.swift`, `HelperClient.swift`, `MenuBarController.swift`. Routes the Pareto-style defenses audit through the helper's `runPreflight` XPC method so the menubar dropdown reflects helper-side checks rather than app-process checks. Closes the timing disagreement where app-in-process and helper-in-XPC could disagree on probe results.

- `DefensesScheduler.start(helperClient:)` now accepts an optional `HelperClient`. When set, `runNow()` calls `client.runPreflight(completion:)` instead of running `DefensesProbe.runAll()` in-process.
- 8-second XPC reply deadline via `AckGate`; on timeout falls back to a local `DefensesProbe.runAll()` call so the menubar always has fresh data even when the helper is unreachable (pre-approval onboarding, dev builds).
- `HelperClient.runPreflight(completion:)` is the new call site: sends `proxy.runPreflight { data in ... }` over the Mach XPC connection, decodes via `VakterXPC.decode(DefenseChecklist.self, from: data)`, calls completion on `@MainActor`.
- `MenuBarController.handleClick()` calls `defensesScheduler?.runNow()` on every menubar icon click (fire-and-forget) so the user sees fresh data within ~1-6 s of opening the dropdown rather than waiting for the 5-minute cadence.
- Idle-path: if `helperClient` is nil (legacy callers, unit tests), `runNow()` falls straight through to the local probe — no behaviour change for existing call sites.

**Smoke gap (warden-flagged):** Live end-to-end XPC path (helper running, app running, click menubar → helper executes `DefensesProbe.runAll()` → JSON → decode → submenu renders) was not exercised from the gate context (no UI access). Tested by: all 29 `DefenseChecklistTests` pass, XPC routing code path manually reviewed.

### Feature A.7 — Onboarding hearAlarm + permissions (ticket #26, PR #44)

`Onboarding.swift`, `AudioController.swift`, `VakterApp/Resources/Info.plist`, `VakterHelper/Resources/Info.plist`. Surfaces microphone and camera permission prompts during the onboarding flow; honours the user's selected siren in the "Hear alarm" step.

- `OnboardingSheet` now contains a `HearAlarmStep` that plays the user's current `AlarmSound` selection via `AudioController.startAlarm(audible: true)`, giving the user a real siren preview mid-onboarding so they can verify volume before arming for the first time.
- `AudioController.startAlarm(audible:)` → `startSiren()` + `startVoiceCueLoop()` path confirmed intact.
- Both `VakterApp/Resources/Info.plist` and `VakterHelper/Resources/Info.plist` now include `NSMicrophoneUsageDescription` and `NSCameraUsageDescription`.

**Known unverified risk (warden-flagged):** TCC mic grant propagation to the helper's sub-bundle. macOS attributes the camera/microphone TCC grants to the `.app` bundle that shows the permission sheet (the menubar app). Whether the embedded VakterHelper binary inherits those grants without a separate TCC prompt on a clean-install machine cannot be verified without a TCC-wipe test. This risk was noted by the engineer and persists post-merge.

### Feature A.5 — Stealth lock-screen takeover overlay (ticket #24, PR #46)

`StealthOverlayWindow.swift` (new), `StealthOverlayConfig.swift` (new, in VakterShared), `VakterApp.swift`, `SettingsRoot.swift`. When Vakter enters `.alarm`, every connected display is covered by a fullscreen opaque "STOLEN MAC" overlay window at `NSWindow.Level.screenSaver`, rendering above the macOS lock screen.

- `StealthOverlayWindowController.show(config:autoDismissAfter:)` iterates `NSScreen.screens` and creates one `NSWindow` per screen, each sized to `screen.frame` (not `visibleFrame` — covers menu bar and Dock). Multi-monitor verified by code review.
- Window level: `.screenSaver` (kCGScreenSaverWindowLevel = 1000). Relies on "later ordered-front wins at equal level" semantics. No level bump above `.screenSaver` — empirically unnecessary; would break if Apple restricts the level. Defensive `assert` logs if the level ever slips.
- `collectionBehavior: [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` keeps the overlay visible across Space switches.
- Transition keying in `AppDelegate.handleStealthOverlayTransition(snapshot:)`: fires `show()` only on `prev != .alarm && new == .alarm`. Periodic republishes during sustained alarm are no-ops. `.grace` does NOT trigger the overlay — only `.alarm`.
- Empty-config fallback: `StealthOverlayConfig.displayMessage` returns `"This Mac is being recovered.\nContact local authorities."` when the user has never opened Settings. The overlay always renders something.
- Settings → General "If found, please contact" card: TextEditor (200-char cap) + callback field (60-char cap). Preview button fires an 8-second auto-dismissing overlay via a private `previewController` instance (separate from the AppDelegate alarm path).
- Phone heuristic: `looksLikePhoneNumber` accepts E.164-style strings; tappable `tel:` link rendered on overlay for Good Samaritan Continuity calling.
- **Warden note — concurrent alarm during preview:** The Settings preview uses an independent `StealthOverlayWindowController` instance; a concurrent real alarm would produce two overlapping overlays (both showing identical "STOLEN MAC" content) for up to 8 seconds until the preview auto-dismisses. Assessed: not a safety regression (thief sees the correct content from both windows; no silence or misdirection). The real alarm overlay persists correctly after the preview auto-dismisses. No block.

**Smoke gap (warden-flagged):** Live rendering of the overlay against the macOS lock screen was not exercised. Cannot be verified without physically triggering an alarm on a machine with a logged-in user and an attached display. The multi-monitor window iteration and `.screenSaver` level are correct in code; the question of whether Apple's lock screen actually stays below our window in macOS 14.6 on this exact machine is unverified.

**Merge note:** PR #46 had a merge conflict in `VakterApp.swift` where both `vkt-27` (adding `defenses.start(helperClient: client)`) and `vkt-24` (adding the stealth overlay snapshot tee) modified the same region of `applicationDidFinishLaunching`. Resolved by the warden by including both changes in correct sequence: stealth overlay tee fires before `defenses.start(helperClient: client)`. Build and all 141 tests confirmed green after resolution.

### Signal.swift café-fix baseline

Verified on all three branches: `.bluetoothTrustLost` remains in the `false` bucket of `triggersGrace`. No regression introduced by any of the three PRs.

### Ship verification (merged trunk)

- `swift test` (all 3 branches individually before merge): 118/118, 116/116, 133/133
- `swift test` (merged trunk, main): 141/141
- `swift build --configuration release --arch arm64` (merged trunk): clean
- `./Scripts/build-app.sh release`: bundle assembled, 3 binaries in MacOS/, `embedded.provisionprofile` present, no Frameworks/ (Sparkle not present in SPM-assembled bundle)
- `./Scripts/sign.sh`: signed as `Developer ID Application: Jonathan Gebru (9TA5GB5UJH)`, all 3 binaries signed, bundle valid on disk
- Entitlements post-signing: all 4 iCloud keys confirmed (`icloud-container-environment`, `icloud-container-identifiers`, `icloud-services`, `ubiquity-container-identifiers`)
- `./Scripts/notarize.sh`: `status: Accepted`, submission ID `a8ba670e-6757-4226-a904-7f2bede13d01`, stapled successfully
- `spctl --assess`: `source=Notarized Developer ID`
- `xcrun stapler validate /Applications/Vakter.app`: passed
- Post-swap pgrep: `Vakter` (pid 97764), `VakterHelper` (pid 97777), `VakterPrivilegedDaemon` (pid 13161) — all alive

---

## v1.4.2 — 2026-05-21

**Notarization submission ID:** c68987a4-001b-472a-b0fd-96a94b55d268
**CFBundleVersion:** 2
**Merged PRs:** #39 (ticket #25), #40 (ticket #21)

### Feature #25 — Wire ArmVakterIntent + SetVakterModeIntent to helper over XPC

`VakterIntents.swift` only. Replaces the `NSLog` TODO stubs in `ArmVakterIntent.perform()` and `SetVakterModeIntent.perform()` with real one-shot `NSXPCConnection` calls to the helper's Mach service.

- `VakterIntentXPC.callArm()` calls `proxy.arm()` on the helper. The helper's `arm(reply:)` calls `stateMachine.armFromUser()` (no Touch ID gate — safe for Shortcuts context) and replies immediately.
- `VakterIntentXPC.callSetMode(raw:)` calls `proxy.setMode(_:)`, bridging `VakterModeAppEnum` through `asVakterMode.rawValue`. All 5 modes covered.
- Each invocation opens a fresh `NSXPCConnection`, defers `conn.invalidate()` on every exit path.
- `AckGate` arbitrates between XPC reply (background queue) and 5-second timeout (main queue). Prevents silent hangs when the helper LaunchAgent isn't approved.
- `VakterIntentError.helperUnreachable` surfaces "Vakter's background helper isn't running" in Shortcuts' error banner.

Known limitation: `arm(reply:)` on the helper always replies `true` regardless of whether `armFromUser()` actually transitioned state (method is void-returning). The `armRejected` error case is unreachable in practice. Follow-up ticket needed to have `armFromUser()` return a result.

### Feature #21 — Defenses +8 checks (12 to 20)

`DefensesAudit.swift`, `DefensesProbe.swift`, `DefenseChecklistTests.swift`. Adds 8 new security checks, bringing the audit total from 12 to 20.

New checks (all appended after existing 12 — order is load-bearing for `DefensesScoreHistory`):

| Check | Probe command | Category | Healthy → severity |
|---|---|---|---|
| AirDrop discovery scope | `defaults read com.apple.sharingd DiscoverableMode` | `.firewallSharing` | Off/Contacts Only = healthy; Everyone = `.warning` |
| AirPlay Receiver | `launchctl list \| grep AirPlayXPCHelper` | `.firewallSharing` | Off = healthy; On = `.warning` |
| File Sharing (SMB) | `launchctl list \| grep com.apple.smbd` | `.firewallSharing` | Off = healthy; On = `.warning` |
| Media Sharing | `launchctl list \| grep com.apple.mediasharingd` | `.firewallSharing` | Off = healthy; On = `.warning` |
| Printer Sharing | `cupsctl` → `_share_printers=0` | `.firewallSharing` | Off = healthy; On = `.warning` |
| Remote Login (SSH) | `launchctl list com.openssh.sshd` | `.firewallSharing` | Off = healthy; On = `.attention` |
| Remote Management (ARD) | `launchctl list com.apple.RemoteManagement` | `.firewallSharing` | Off = healthy; On = `.attention` |
| Boot security policy | `bputil -d` (Apple Silicon only) | `.systemIntegrity` | Full Security = healthy; Reduced = `.warning`; Permissive = `.attention` |

AirDrop + Boot Security mirrored into `DefensesProbe.swift` so the menubar dropdown stays in sync with the Settings Defenses tab. 10 new test cases in `DefenseChecklistTests`.

**Known limitation (boot security):** `bputil -d` requires root on macOS 14 (Sonoma). On macOS 14 machines all users see `.unknown` ("Couldn't read the LocalPolicy"). Check only functions correctly on macOS 15+. Degrades gracefully — no crash, no misreport.

### Ship verification

- `swift test`: 113/113 passed (both branches verified independently)
- `swift build --configuration release --arch arm64`: clean (pre-existing AppDelegate-Sendable warnings only)
- Provisioning profile: present at `Contents/embedded.provisionprofile`
- Entitlements post-signing: 4 iCloud keys confirmed (`icloud-container-environment`, `icloud-container-identifiers`, `icloud-services`, `ubiquity-container-identifiers`)
- `spctl --assess`: `source=Notarized Developer ID`
- `xcrun stapler validate /Applications/Vakter.app`: passed
- Probe spot-tests on macOS 14 / Darwin 23.6.0 / Apple Silicon: AirDrop, SSH, and boot security all handled correctly

---

## v1.4.1 and earlier

See `Website/changelog/index.html` for v1.4.1. Prior technical history not yet backfilled.
