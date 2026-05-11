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
| 4. SMAppService LaunchAgent | ⛔ **BLOCKED** | Needs Xcode |
| 5. Power-button intercept | ⛔ **BLOCKED** | Needs signed app + Accessibility |
| 8. App Intents in menubar app | ⛔ **BLOCKED** | Needs Xcode |

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

### ⛔ Spike 4 — SMAppService LaunchAgent — BLOCKED on Xcode

**Why blocked:** `SMAppService` requires a proper `.app` bundle with a registered LaunchAgent plist embedded in `Contents/Library/LaunchAgents/`. We can't build this without Xcode and code signing.

**What we already know from Apple docs:**
- `SMAppService.agent(plistName: ...)` is the modern API
- First registration triggers a user-approval prompt in System Settings → Login Items
- Approval is reversible by the user from System Settings
- Works for unsigned apps in development with Developer ID

**Recommendation:** Resolve this spike during week 1 of v1 build once Xcode is installed and Developer ID is in hand.

---

### ⛔ Spike 5 — Power-button intercept — BLOCKED on Accessibility / signing

**Why blocked:**
- `CGEventTap` requires the **Accessibility** TCC grant
- Accessibility grants are tied to the app's code signature
- An unsigned CLI binary requesting Accessibility creates a new TCC entry on every rebuild and is treated as untrusted

**Also uncertain:**
- Whether the power button on Apple Silicon emits an observable event in the CGEvent stream at all (the button is wired through the SMC/Secure Enclave on M-series, separate from the standard keyboard event path). Likely it doesn't, but verifying needs a real signed app.

**Recommendation:** Move this spike to week 1 of v1 build. Plan for the realistic outcome that the power button is NOT interceptable, and treat that as an honest documented limitation rather than a feature regression.

---

### ⛔ Spike 8 — App Intents discovery — BLOCKED on Xcode

**Why blocked:** App Intents discovery (the way Shortcuts finds your app's intents) is driven by Xcode-generated metadata baked into the `.app` bundle. We can't test this without a proper app target.

**What we already know:**
- App Intents framework works on macOS 14+
- A menubar/`LSUIElement` app can expose intents
- A LaunchAgent helper alone (no app bundle) cannot expose intents — the host needs to be a regular app target

**Recommendation:** Resolve during v1 build week 2-3 alongside the helper architecture work.

## Environment gap

To unblock the four remaining spikes and start v1 build, the project needs:

1. **Install full Xcode** (App Store, ~15GB, free)
2. **Apple Developer Program enrollment** ($99/year)
3. **Generate a Developer ID Application certificate** in Apple Developer portal
4. **Set up notarization credentials** (app-specific password or App Store Connect API key)

None of these can be done programmatically — they require an Apple ID, payment, and a few clicks in Apple's portals. Estimated time: ~30 minutes of user-driven setup + Xcode download.

## Updates needed to OpenSpec artifacts

Based on these findings:

1. **`design.md` — Lock-screen message section**: drop the nvram path. State that we write to `/Library/Preferences/com.apple.loginwindow` via privileged helper.
2. **`design.md` — Open spikes**: mark spikes 1, 3, 6, 7 as resolved; rephrase spike 2 to focus on HID-level Touch ID sensor; leave 4, 5, 8 as pending until Xcode is set up.
3. **`spec.md` — Touch ID brief-tap requirement**: mark contingent (same treatment as power-button intercept).
4. **`tasks.md` — Phase 0**: collapse the 8-spike list to the 4 remaining items; document the 4 done.

I'll apply these next.
