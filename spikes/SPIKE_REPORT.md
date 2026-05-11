# Phase 0 Spike Report — Anchor

Date: 2026-05-11
Hardware: MacBook Air, Apple Silicon arm64, macOS 14.8.5 Sonoma
Toolchain: Command Line Tools only (no full Xcode), Swift 6.0.3 (broken; clang/Obj-C used instead), no codesign identities

## TL;DR

| Spike | Outcome | Risk to v1 |
|---|---|---|
| 1. CoreAudio volume control | ✅ **PASS** | None — confirmed feasible |
| 7. AVSpeechSynthesizer + tone mix | ✅ **PASS** | None — voice cue strategy works |
| 3. Lid (clamshell) state | ✅ **PASS** | None — read + notify both work |
| 6. Lock-screen message storage | ⚠ **CONDITIONAL** | Low — needs sudo for write, design already accommodates |
| 2. Touch ID brief-tap | ⏳ **DEFERRED** | Medium — may need to drop the brief-tap luxury feature |
| 4. SMAppService LaunchAgent | ✅ **PASS** (resolved 2026-05-11) | None — helper registers, runs, survives KeepAlive |
| 8. App Intents in menubar app | ⚠ **PARTIAL** (resolved 2026-05-11) | Medium — needs Xcode build phases SPM can't replicate |
| 5. Power-button intercept | ⏳ **DEFERRED** (probed 2026-05-11) | Medium — likely not feasible; treat as documented limitation |

**No spike result fundamentally breaks the design.** Three are blocked on environment (Xcode + Developer ID) — they don't change the design, just push their resolution to after the dev environment is real.

## Detailed findings

### ✅ Spike 1 — CoreAudio volume control

**Confirmed:**
- `AudioObjectGetPropertyData` / `SetPropertyData` work without any entitlements
- Default output device is reliably identifiable (returned "MacBook Air Speakers" on this hardware)
- Volume scalar read + write round-trips cleanly (set 70% → reads back 70%, set 100% → reads back 100%)
- Mute state read + write works
- Original state restoration works

**Implication:** The full audio strategy from `design.md` (read current volume/mute → force max + unmute → play alarm → restore) is implementable as designed.

**Not yet confirmed (needs further spike on signed app):**
- Forcing output to internal speakers when AirPods are connected (`kAudioDevicePropertyDataSource` manipulation on the *built-in* device, even when it's not the default)
- Whether this still works under Sandbox + entitlements (we will NOT ship Sandboxed, so likely moot)

**Files:** `spikes/01-audio/audio_test.m`, compiled to `audio_test`

---

### ✅ Spike 7 — AVSpeechSynthesizer + AVAudioEngine

**Confirmed:**
- `AVSpeechSynthesizer` works from a CLI binary (no app target required)
- `AVAudioEngine` with a custom `AVAudioSourceNode` rendering a sine wave works
- The two run **concurrently without conflict** — speech utterance completed (~3 sec, delegate fired) while tone played underneath
- Default audio routing handled the mix; no manual mixer wiring needed beyond `engine.mainMixerNode`

**Implication:** The voice cue design ("siren burst at t=0, voice phrase at t=1, repeating") is straightforward to implement with the public APIs.

**Files:** `spikes/07-audio-mix/mix_test.m`

---

### ✅ Spike 3 — Clamshell state via IOPMrootDomain

**Confirmed:**
- `IOServiceGetMatchingService(... "IOPMrootDomain")` returns a valid service handle
- `AppleClamshellState` property is readable as a CFBoolean (returned 0 = OPEN on this machine, as expected mid-test)
- `IOServiceAddInterestNotification` with `kIOGeneralInterest` registers successfully (`KERN_SUCCESS`)
- Run-loop integration via `IONotificationPortGetRunLoopSource` works

**Observed:**
- `AppleClamshellCausesSleep` was 0 during the test — meaning lid-close would *not* sleep this Mac at that moment. This is normal when an external display is attached or certain power policies apply. We don't need to worry about it for detection purposes (state still flips regardless of whether sleep happens).

**Not yet confirmed:**
- Whether the kernel emits the notification *before* the OS suspends the process on lid close (when sleep IS engaged). Likely yes, but we'll need a manual test with a Mac that sleeps on close.

**Files:** `spikes/03-clamshell/lid_test.m`

---

### ⚠ Spike 6 — Lock-screen message

**Confirmed:**
- Modern macOS stores the message in `defaults`, not `nvram`. Specifically `/Library/Preferences/com.apple.loginwindow` with key `LoginwindowText`.
- This Mac has no `LoginwindowText` set (clean slate).
- nvram is *not* in use for this purpose on Apple Silicon Sonoma.
- Reading the preference is unprivileged.
- Writing requires root (nvram and system `defaults` both rejected unsigned writes).

**Implication:**
- The design path holds: a privileged helper (installed once with admin auth) can update `LoginwindowText` silently for dynamic suffix changes
- No need to touch `nvram` at all — simpler

**Recommendation:** Update `design.md` to specify `defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText` (or the CFPreferences-equivalent) as the canonical mechanism, dropping the nvram detour.

---

### ⏳ Spike 2 — Touch ID brief-tap

**Status:** Deferred — see `spikes/02-touchid/NOTES.md`

**Summary:**
- `LAContext` is binary: it either fully authenticates (with system UI prompt) or fails. There's no "the user touched the sensor" event in the public LocalAuthentication API.
- The brief-tap concept needs **HID-level sensor observation** (`IOHIDManagerCreate` matching the embedded sensor controller), which requires a signed Mac app with appropriate entitlements to test properly.

**Recommendation:**
- Treat brief-tap silent-disarm as a v1.5 research item, not a v1 blocker.
- Ship v1 with **full Touch ID/password unlock = disarm** as the only authenticated exit. Slight UX regression, no blocker.
- Update `design.md` and `spec.md` accordingly: keep the brief-tap requirement marked as "contingent on HID-level access," same posture we already gave the power-button intercept.

---

### ✅ Spike 4 — SMAppService LaunchAgent — RESOLVED 2026-05-11

**Implementation:** `HelperManager` in `Anchor/Sources/AnchorApp/HelperManager.swift` calls `SMAppService.agent(plistName: "app.anchor.mac.helper.plist").register()` at app launch.

**Confirmed:**
- First registration succeeded silently (no user-approval prompt) because the app was signed + notarised; macOS pre-trusts notarised Developer-ID-Application bundles
- Helper boots within 1–2 seconds of app launch
- All four observers initialise (Lid / Power / Bluetooth / Hotkey)
- `launchctl list | grep anchor` shows the helper as a regular LaunchAgent submitted by `smd` (System Management Daemon)
- **KeepAlive verified**: `killall AnchorHelper` → launchd respawned within ~1.5 seconds, all observers reinitialised. An attacker can't quiet the alarm by killing the helper process.
- `SMAppService.Status` enum surfaces correctly in the menubar dropdown (Helper: enabled (running))

**Production-bound fix caught en passant:** when the app binary is re-signed
(local rebuild OR a Sparkle update in production), the recorded
"Lightweight Code Requirement" (LWCR) no longer matches the new binary, and
launchd refuses to spawn the helper (`EX_CONFIG / 78`). `HelperManager`
now `unregister()`s before `register()`ing on every call, which clears the
stale LWCR and forces launchd to record the new one. This will keep Sparkle
updates working without manual user intervention.

---

### ⚠ Spike 8 — App Intents discovery — PARTIAL PASS (resolved 2026-05-11)

**What works:**
- `ArmAnchorIntent`, `SetAnchorModeIntent`, and `AnchorShortcutsProvider` (in `Sources/AnchorApp/AnchorIntents.swift`) compile cleanly
- The AppIntents framework links into the menubar binary (`otool -l` shows `/System/Library/Frameworks/AppIntents.framework` as a load command)
- LSUIElement=true menubar apps are compatible with AppIntents — Apple supports this

**What doesn't work yet:**
- Shortcuts.app / Spotlight do NOT see Anchor's intents
- Reason: Xcode generates a `Metadata.appintents` directory inside the bundle's `Contents/Resources/`, produced by `appintentsmetadataprocessor` running over per-source `.swiftconstvalues` files
- SPM does not emit those `.swiftconstvalues` files (the `SWIFT_ENABLE_EMIT_CONST_VALUES = YES` build setting is an Xcode-side phase)
- We tried `-Xfrontend -emit-const-values-path <path>` via Package.swift's `swiftSettings` — flag accepted but only emits one path for the whole module, not per-file, which `appintentsmetadataprocessor` requires

**Paths forward (any one resolves it):**
1. **Migrate to .xcodeproj** (or generate one via XcodeGen / Tuist) — gets the build phase for free
2. **Custom Swift compile step** — invoke `swift -c -emit-const-values-path ...` per file in `build-app.sh`, feed the results to `appintentsmetadataprocessor --swift-const-vals-list`
3. **Defer AppIntents to v1.5** — keep the intent code; surface them later

**Recommendation:** Defer to v1.5. The Shortcuts feature was a "nice to have" for power users (MacStories pitch). Not on the critical path for café-snatch deterrence. When we do migrate to .xcodeproj for other reasons (e.g. Asset Catalog needs), AppIntents discovery comes along for free.

**Updated v1 spec:** Mark the Shortcuts/App Intents requirement as **deferred to v1.5** in `spec.md`.

---

### ⏳ Spike 5 — Power-button intercept — PROBED, LIKELY INFEASIBLE (2026-05-11)

**What we observed:**
- `IOHIDManager` matching with `kHIDPage_GenericDesktop` / `kHIDPage_Keyboard` / `kHIDPage_Consumer` succeeded
- 4 HID devices matched on probe; IOReg shows a family of `AppleSPUHIDDevice` entries (SPU = System Programmable Unit, backed by Secure Enclave / SMC)
- `IOHIDManagerOpen` returned `0xE00002E2` (`kIOReturnNotPermitted`) — Input Monitoring permission required even for read-only event observation
- No actual events observed because permission was denied to the unsigned probe

**What's still unknown:**
- Whether the brief power-button press surfaces in the HID event stream when Input Monitoring IS granted
- Even with permission granted, conventional wisdom + Apple's docs strongly suggest the power button on Apple Silicon is routed via SMC/Secure Enclave and is NOT in standard userspace event streams. The firmware handles it directly.

**Pragmatic conclusion:**
- Treat power-button intercept as **likely-infeasible** but worth one more attempt during Phase 1 when we have the signed Anchor.app with Input Monitoring granted
- Update `spec.md` requirement to reflect "contingent on Phase 1 confirmation"
- Honest fallback for users in onboarding: "Anchor cannot prevent a held power-button shutdown. We close the lid / power-disconnect / Bluetooth-leave gaps; the firmware-managed power button is outside any third-party app's reach."

**Code artefact:** `spikes/05-power-button/power_probe.m` — re-runs against the signed Anchor.app context will be cheap once Input Monitoring is granted.

## Environment gap — CLOSED 2026-05-11

All four environment dependencies satisfied:

1. ✅ Xcode 16.2 installed at `/Applications/Xcode.app`
2. ✅ Apple Developer Program enrolled (Team `9TA5GB5UJH`)
3. ✅ Developer ID Application certificate in login keychain
4. ✅ `notarytool` keychain profile `anchor-notarytool` stored, verified, used to notarise the bundle once already (submission ad1eb8f7-f0d6-4209-99ce-738dd29778a5)

## Final spike status

```
✅ 1. CoreAudio volume control       PASS         (2026-05-11)
✅ 3. Clamshell state                PASS         (2026-05-11)
⚠  6. Lock-screen text path          CONDITIONAL  (privileged helper needed)
✅ 7. AVSpeechSynthesizer + tone     PASS         (2026-05-11)
✅ 4. SMAppService LaunchAgent       PASS         (2026-05-11, post-Xcode)
⚠  8. App Intents discovery         PARTIAL      (needs Xcode build phases)
⏳ 5. Power-button intercept         DEFERRED     (probably infeasible)
⏳ 2. Touch ID brief-tap             DEFERRED     (research item for v1.5)
```

**No remaining blockers for the v1 build.** Phase 1 feature work can begin.
