# Design: Anchor v1

## Core design principle

**Intentional action, intentional consequences.** The user arms via a deliberate key press. The user disarms via Touch ID or password. No magic, no auto-arming, no false-positive engineering. The product's defensibility is the *quality* of this one loop, not feature breadth.

## State machine

```
                  ┌─────────────────────────┐
                  │       UNARMED 🟢        │
                  │   Menubar: outlined     │
                  │   shield                │
                  └────────────┬────────────┘
                               │  ⌘⌃⌥L  (or menubar click)
                               │  → Mac locks AND arms
                               ▼
                  ┌─────────────────────────┐
                  │       ARMED 🛡          │
                  │   Menubar: filled       │
                  │   shield                │
                  │   Watching: lid, power, │
                  │   trusted BT peer       │
                  └────────────┬────────────┘
                               │
                  ┌────────────┼────────────┐
                  │            │            │
           lid closes    power off    BT peer leaves (>10m)
                  │            │            │
                  └────────────┼────────────┘
                               ▼
                  ┌─────────────────────────┐
                  │   GRACE  ⏱  (5–10s)     │
                  │   Soft chirp, escalating│
                  │                         │
                  │   Touch ID brief tap →  │
                  │     silent disarm       │
                  │   Full unlock →         │
                  │     disarm              │
                  └────────────┬────────────┘
                               │ timeout
                               ▼
                  ┌─────────────────────────┐
                  │       ALARM 🚨          │
                  │   Full-volume siren     │
                  │   Camera photo (local)  │
                  │   Continues until:      │
                  │     Touch ID / password │
                  └─────────────────────────┘
```

### State transitions (complete)

| From | Event | To | Side effects |
|---|---|---|---|
| UNARMED | Global hotkey pressed | ARMED | Lock screen, play arm chirp, fill menubar shield |
| UNARMED | Menubar "Arm now" click | ARMED | Same as above (skip lock if already locked) |
| UNARMED | Shortcuts "Arm Anchor" intent | ARMED | Same as above |
| ARMED | Lid closes | GRACE | Start grace timer, play soft chirp |
| ARMED | Power adapter disconnect | GRACE | Start grace timer, play soft chirp |
| ARMED | Any trusted BT peer leaves range | GRACE | Start grace timer, play soft chirp |
| ARMED | Brief power-button press | GRACE | Start grace timer, play soft chirp, suppress sleep |
| ARMED | Touch ID full unlock | UNARMED | Play disarm tone, clear shield |
| GRACE | Touch ID brief tap | UNARMED (silent) | Cancel timer, no sound |
| GRACE | Touch ID / password full unlock | UNARMED | Cancel timer, play disarm tone |
| GRACE | Timer expires (mode-dependent) | ALARM | Start siren + voice cue, capture photo burst, write event log |
| ALARM | Touch ID full unlock | UNARMED | Stop siren, save photo burst, update last-alarm summary |
| ALARM | Password unlock | UNARMED | Same as above |
| any | App quit attempt while armed | (blocked) | Require unlock first |
| Loaner | Trust window expires | ARMED | Silent transition; user notified |

**Multiple trusted BT peers:** the user pairs 1–10 peers (phone, AirPods, Watch, Tile, etc.). Any *one* peer being in range dampens BT signal-loss as a trigger; only when *all* paired peers are out of range does BT count as a leave-event. Single-peer setups behave identically to v1's original single-peer design.

## Signals — detection details

### Lid sensor

- Source: `IOPMrootDomain` notifications for `kIOPMMessageClamshellStateChange` (or modern equivalent on Apple Silicon)
- Reliability: very high
- Latency: instant
- Edge case: external display "clamshell mode" — lid is closed but Mac is awake. Treat as lid-close trigger; user can manually disarm before stowing.

### Power state

- Source: `IOPowerSources` framework, `IOPSGetProvidingPowerSourceType()`
- Trigger condition: AC → Battery transition while armed
- Reliability: very high (if originally plugged in)
- Latency: instant
- Edge case: user wasn't plugged in. Signal simply doesn't exist for them; lid and BT carry the load.

### Bluetooth peer (trusted)

- Source: `CoreBluetooth` / `IOBluetooth`
- User pairs a "trusted device" during onboarding (any BT peer: phone, AirPods, Watch, even Tile/AirTag)
- Trigger condition: RSSI drops below threshold for ≥3 consecutive seconds AND device was visible in the last 30s
- Reliability: medium (BT is noisy)
- Latency: 5–30 seconds
- Critical: this is **dampening + signal both**. Presence during ARMED is a soft confirmation of owner nearby; absence is a trigger.

## Grace period

- Default duration: **8 seconds** (user-configurable 5–15s per mode)
- Per-mode grace overrides defined in [Modes](#modes)
- Audio: single chirp at t=0, then escalating chirps at t=4 and t=7 (slightly louder each time)
- Visual: lock screen overlay shows "Anchor: disarming in 5… 4…" (only if lid still open)
- Exit conditions:
  - Touch ID brief tap (≥ 0.3s contact) → silent disarm
  - Full keyboard unlock → disarm
  - Timeout → ALARM

The grace exists to absorb the "I came back, I'm about to unlock" gap and the "I bumped the power cord" false trigger. 8 seconds is enough for the owner to act and short enough to deter a thief who realizes they're being detected.

## Modes

Four selectable modes change the system's posture without changing its mental model. Selectable from the menubar dropdown.

| Mode | Grace | Audible alarm | Trust window | Use case |
|---|---|---|---|---|
| **Normal** | 8s | full siren + voice cue | n/a | Default — café, library, daily use |
| **Travel** | 5s | full siren + voice cue + camera burst | n/a | Hotel rooms, airports, conferences |
| **Library** | 8s | silent (haptic + photo only — requires v1.5 iPhone) | n/a | Reading rooms, lectures, quiet zones |
| **Loaner** | 8s | full siren + voice cue | 1h / 2h / 4h | Lending Mac to a friend; auto-rearms after window |

**Loaner mode behavior:**
- User selects a trust window (1h / 2h / 4h) when entering Loaner
- During the window, the system is treated as Unarmed regardless of arming gestures
- A persistent menubar countdown shows remaining trust
- At window expiry, Anchor silently re-arms to the previously-selected mode and notifies the user
- The user can extend or cancel Loaner at any time

**Library mode in v1:**
- v1 ships Library mode with audible alarm replaced by a louder version of the grace chirp pattern, plus repeating camera burst — *no haptic until v1.5 iPhone companion exists.*
- Marketing makes this clear ("Library mode reaches its full potential when paired with the Anchor iPhone app, coming v1.5")

## Voice cue alarm

The alarm's audio is the deterrent. A spoken phrase amplifies psychological pressure beyond a sine sweep alone — a thief hearing a voice knows the system is specifically tracking them.

### Audio composition during ALARM state

```
t=0.0s   siren burst (sine sweep, ~1s)
t=1.0s   voice: "This MacBook is being tracked. Please put it down."
t=4.0s   siren burst
t=5.0s   voice (repeats)
…loops until disarmed
```

### Implementation

- `AVSpeechSynthesizer` with system-default voice for the user's `AVSpeechSynthesisVoice.currentLanguageCode()`
- Voice cue plays alongside siren via separate AVAudioPlayerNode → AVAudioEngine mixer
- Both routed through the forced-internal-speakers output
- User can replace the spoken phrase with their own text in Settings (limit: 120 characters, single phrase, validated for length only — no profanity filter, owner's call)

### Localization

- v1 ships with default phrases for: English, Dutch, German, French, Spanish, Portuguese, Italian, Japanese, Korean, Mandarin
- Fallback: English if user's system language is unsupported
- Custom message bypasses localization (user writes in any language they want)

## Power-button intercept

On Apple Silicon Macs, the power button is also the Touch ID sensor. While the Mac is in **Armed** state, a brief press is treated as a trigger event rather than a sleep request.

| Press type | Duration | Behavior while ARMED |
|---|---|---|
| Brief press | < 0.5s | Transition to GRACE state |
| Medium press | 0.5–3s | Transition to GRACE; suppress system sleep via `IOPMAssertion` for the grace window |
| Long press | ≥ 3s (force shutdown) | **Cannot be blocked** — firmware-level, accepted limitation |

### Implementation

- CGEventTap listening for `kCGEventOtherMouseUp` / system-defined keycodes
- macOS does not expose the power button directly via NSEvent; we rely on the global event monitor + private-detail timing inferred from the system response
- `IOPMAssertion` of type `kIOPMAssertionTypeNoIdleSleep` prevents the brief-press triggering a sleep transition during the grace window

### Limitation

- Firmware long-press shutdown is irrecoverable. We accept this gap (closes ~60–70% of shutdown bypass attempts) and document it transparently in onboarding ("Anchor cannot prevent a held power-button shutdown").

## Pre-flight security checklist

Anchor's value extends beyond alarming: it actively helps the user harden their Mac. The pre-flight check is a settings pane (and a launch-day banner card) that surfaces system-level security posture.

### Check items

| Item | Read source | Failure CTA |
|---|---|---|
| FileVault on | `fdesetup status` or `IOReg` | Open System Settings → Privacy & Security |
| Find My Mac on | `defaults read` MobileMe.framework / iCloud | Open System Settings → Apple ID → iCloud |
| Login password set | DirectoryServices query | Open System Settings → Users & Groups |
| Screen auto-lock ≤ immediate after sleep | `defaults read com.apple.screensaver` | Open System Settings → Lock Screen |
| Login-window message set | `nvram` or sysadmin file | Anchor configures it directly with user consent |
| Firmware password (optional) | `firmwarepasswd -check` | Walkthrough page (advanced users only) |
| Automatic login disabled | DirectoryServices | Open System Settings → Users & Groups |

### UI

```
┌──────────────────────────────────────────────────────────┐
│  Your Mac's defenses               Last checked: 2d ago  │
├──────────────────────────────────────────────────────────┤
│  ✅  FileVault encryption           on                   │
│  ✅  Find My Mac                    on                   │
│  ✅  Login password                 set                  │
│  ⚠   Screen auto-lock               5 min                │
│      [Change to immediate →]                             │
│  ⚠   Login-window message           not set              │
│      [Add "If found, please contact..." →]               │
│  ❌  Firmware password              not set              │
│      [Recommended for travelers — show me how →]         │
│  ✅  Automatic login                disabled             │
│                                                          │
│  Score: 7/10  ·  Run again [↻]                           │
└──────────────────────────────────────────────────────────┘
```

### Behavior

- Read-only — Anchor never *changes* system settings unannounced. Every CTA opens System Settings or shows a guided walkthrough
- Exception: login-window message can be set in-app (with explicit user input) since it's a simple `nvram` write
- Re-runs automatically on app launch and weekly; results cached
- Score visible in menubar dropdown ("Defenses: 7/10")

## Lock-screen message + last-alarm summary

When the Mac is locked, the standard Login Window displays a custom message owners configure during onboarding (or in Settings). Anchor extends this with a dynamic suffix containing the most recent alarm event.

### Composition

```
Static (user-written):
  "This MacBook is monitored by Anchor.
   If found, please contact +31 6 ... or jonathan@example.com."

Dynamic suffix (auto-appended by Anchor):
  "Last alarm: 11 May 2026, 14:32 — 3 photos captured."
```

### Implementation

- Storage: `/Library/Preferences/com.apple.loginwindow` key `LoginwindowText` (verified by Spike 6 on macOS 14.8.5 — modern macOS does *not* use the legacy nvram path; that one is empty even on freshly-imaged Apple Silicon)
- Static message: written by the privileged helper after one-time admin authorization (`SMJobBless`-installed or `xpc_set_event_stream_handler` based)
- Dynamic suffix: rewritten by the same helper on every ALARM→UNARMED transition, no further admin prompts after install
- User can disable dynamic suffix in Settings (defaults: on)
- Max combined length: 250 characters (Login Window truncates beyond this)

### Why this matters

A thief reading "we already photographed you" creates real psychological pressure even after the alarm has stopped. It's a passive, persistent deterrent that costs nothing to run.

## Shortcuts and Focus mode integration

Anchor exposes App Intents (the macOS Shortcuts API) so power users can integrate it into automation flows.

### Exposed intents

| Intent | Parameters | Behavior |
|---|---|---|
| `Arm Anchor` | (none) | Transitions to Armed using current mode |
| `Disarm Anchor` | (none) | Requires Touch ID to actually fire |
| `Set Anchor Mode` | mode: Normal / Travel / Library / Loaner | Switches mode; in Loaner, asks for trust window |
| `Set Anchor Loaner Window` | duration: 1h / 2h / 4h | For use with "Set Anchor Mode" |
| `Run Anchor Pre-flight Check` | (none) | Returns score + failing items as Shortcut output |

### Focus mode example

Users can build a Focus filter so that enabling a "Café" Focus auto-arms Anchor:

```
"Café" Focus turns on
  → Shortcut: Arm Anchor
  → Shortcut: Set Anchor Mode → Library
```

### Why this matters

Indie Mac power users live in Shortcuts. Exposing intents *for free* makes Anchor the obvious choice for the Federico Viticci tier and gets us reviewed organically on MacStories-type sites.

## Alarm

### Audio strategy

Apple Silicon constrains direct hardware volume override. The strategy is:

1. **Pre-render the alarm sample** at full-scale digital amplitude with brickwall limiting (sine sweep 800–1200Hz, ramp on/off envelopes, ~95% peak loudness without clipping). One ~2-second loop.
2. **Force system output volume to maximum** before playback. macOS lets us read/write `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` via `AudioHardwareServiceSetPropertyData`. Save user's prior volume; restore on disarm.
3. **Force unmute** if muted. Same API.
4. **Disable Do Not Disturb override.** Audio still plays in DnD if we use `kAudioSessionProperty_OverrideAudioRoute`-equivalent on macOS (or simply play via AudioToolbox; macOS doesn't silence non-system alerts in DnD by default).
5. **Force output to internal speakers** if headphones/AirPods are connected. A thief in headphones is a fail mode — explicit speaker selection via `kAudioDevicePropertyDataSource`.
6. **Loop continuously** until disarmed. No auto-stop. Battery drain is acceptable — this is the deterrent moment.

Open question for spike work: does forcing volume + speaker selection require Accessibility, or does CoreAudio suffice? If only CoreAudio: cleaner permissions story.

### Photo capture

- Source: `AVFoundation` `AVCaptureSession` with `AVCaptureDeviceTypeBuiltInWideAngleCamera`
- **Normal mode:** 3 frames at t=0, t=2s, t=5s after alarm start
- **Travel mode:** burst — 1 frame at t=0, then 1 frame every 5 seconds for the first minute (up to 13 frames), then 1 frame every 30 seconds until disarmed
- **Library mode:** same as Travel (the silent-alarm modes lean harder on photo evidence)
- **Loaner mode:** same as Normal
- Storage: `~/Library/Application Support/Anchor/events/<timestamp>/photo-N.jpg`
- Display: shown to user when they unlock (event log screen)
- No upload (local-only in v1)

### Lock screen behavior

- Mac stays locked during alarm — standard macOS lock screen
- Optional: custom lock-screen message ("If found, please contact me at …") configurable in Settings, uses `EFI` lock message or LoginWindow plist customization

## Onboarding flow

```
STEP 1 — Welcome (5s)
  "Anchor watches over your Mac."
  Tiny animation: combo press → shield fills
  [Continue]

STEP 2 — Pick your shortcut (10s)
  Visually big animated keys: ⌘ ⌃ ⌥ L
  [That works] [Choose a different combo]

STEP 3 — Permissions (one card each)
  ┌─────────────────────────────────────────────┐
  │ Accessibility                                │
  │ Lets Anchor see your shortcut press.         │
  │ Anchor never reads anything else you type.   │
  │ Inline annotated screenshot of System        │
  │ Settings panel (per-OS-version).             │
  │ [Open Settings →]   [Skip for now]           │
  └─────────────────────────────────────────────┘
  
  Each step polls TCC every 500ms, auto-advances on grant.
  Order: Accessibility → Camera → Bluetooth → Notifications → Login Item.
  Skip Accessibility = blocked (cannot complete onboarding).

STEP 4 — Trusted Bluetooth peer (optional)
  "Pick a device you keep with you. We'll dampen 
   false alarms when it's nearby."
  Picker shows currently-paired BT devices.
  [Skip] is a real option (BT is optional).

STEP 5 — Demo arm
  "Try it. Press ⌘⌃⌥L now."
  → Mac locks, shield fills.
  → Touch ID → "Nice. That's the whole product."

STEP 6 — Hear the alarm
  "This is what a thief hears."
  [▶ Play 2-second sample]
  Volume preview slider (purely cosmetic — actual alarm 
  is always max).
  Optional lock-screen "if found" message.
  [Done]
```

### Failure recovery

- If user denies Accessibility: blocked from completing onboarding with a friendly "Anchor needs this to work" screen and a [Try again] CTA that re-opens System Settings.
- If user skips Camera: alarm still works, no photo captured. Soft nag in menubar.
- If user skips Bluetooth: BT signal disabled, lid + power still active. No nag.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Anchor.app (menubar)                     │
│  - SwiftUI for Settings + Onboarding + Event Log            │
│  - AppKit NSStatusItem for menubar                          │
│  - Listens to XPC from helper                               │
└─────────────────────────────────────────────────────────────┘
                            ↕ XPC
┌─────────────────────────────────────────────────────────────┐
│         com.anchor.helper (LaunchAgent, background)         │
│  - Global hotkey via CGEventTap (needs Accessibility)        │
│  - Lid: IOPMrootDomain notifications                         │
│  - Power: IOPowerSources callbacks                           │
│  - BT: CoreBluetooth central, RSSI polling                   │
│  - Alarm: CoreAudio direct, speaker forcing                  │
│  - Camera: AVFoundation capture                              │
│  - State machine + event log writer                          │
└─────────────────────────────────────────────────────────────┘
```

**Why split?** The menubar app can crash/restart without losing armed state. The helper survives app updates. Standard pattern for serious Mac apps.

### Build & distribution

- **Language:** Swift 5.10+ / Swift 6
- **UI:** SwiftUI (settings, onboarding, event log), AppKit (menubar)
- **Min target:** macOS 14 (Sonoma)
- **Arch:** arm64 only — no Intel build
- **Signing:** Apple Developer ID ($99/yr)
- **Notarization:** required for Gatekeeper acceptance
- **Distribution:** direct .dmg from anchor.app; Sparkle for auto-updates
- **Not on Mac App Store** — sandbox blocks IOKit/CoreAudio device control

## Open spikes (resolve before code freeze)

> Spikes 1, 3, 6, 7 **resolved 2026-05-11** — see [spikes/SPIKE_REPORT.md](../../../spikes/SPIKE_REPORT.md).

### Resolved

1. ~~**Audio loudness ceiling on Apple Silicon.**~~ ✅ Resolved. CoreAudio volume + mute control works without entitlements (`spikes/01-audio/`).
3. ~~**External display clamshell-mode edge case.**~~ ✅ Resolved at the read/notify primitive level (`spikes/03-clamshell/`). UX choice for the external-display case stays open as a v1 design decision (default: treat as trigger; user can opt out per-mode).
6. ~~**`nvram LoginwindowText` write permissions.**~~ ✅ Resolved — modern macOS uses `/Library/Preferences/com.apple.loginwindow` instead of nvram. Privileged helper writes after one-time install admin auth, no further prompts (`spikes/06-nvram/` findings in SPIKE_REPORT.md).
7. ~~**AVSpeechSynthesizer routing.**~~ ✅ Resolved. AVSpeechSynthesizer + AVAudioEngine mix cleanly (`spikes/07-audio-mix/`).

### Open — blocked on Xcode + Developer ID

2. **Touch ID brief-tap detection.** `LAContext` is public-API-binary (auth or no auth). Brief-tap likely needs HID-level sensor observation via `IOHIDManager` — needs a signed app to test. **Plan:** mark the brief-tap silent-disarm requirement as contingent in `spec.md`; ship v1 with full-unlock disarm only if HID path doesn't pan out.
4. **`SMAppService` LaunchAgent.** Needs a proper `.app` bundle with embedded LaunchAgent plist. Resolve week 1 of build.
5. **Power-button intercept feasibility.** CGEventTap needs Accessibility, which is signature-bound. Power-button events on Apple Silicon may not even surface in CGEvent at all (the button is wired through the Secure Enclave, not the keyboard event path). Resolve week 1 of build; plan for the realistic case that this is documented as a limitation.
8. **App Intents discovery in a menubar app.** App Intents need an Xcode-built `.app` bundle. Resolve week 2-3 of build.

## Future versions (sketched)

### v1.5 — iPhone companion (4–6 weeks after v1)

- Custom-paired BLE companion app (App Store)
- **iPhone haptic during grace** — the single biggest UX win; phone vibrates the moment Grace starts, so the user can return and disarm before the alarm fires publicly
- **Continuity Camera as 2nd-angle capture** — iPhone camera shoots simultaneously with FaceTime camera at alarm time; two angles of the thief
- **Apple Watch on-wrist inference** — using paired-watch BT state, distinguish "Mac moved with owner present" from "Mac moved while owner left"
- Library mode reaches full potential — silent alarm + haptic-only feedback
- Strong proximity-based auto-disarm (replaces generic BT peer for users who pair the dedicated app)
- On-device push when alarm fires (BLE only, ~10m range)
- No backend required

### v2 — Cloud features ($4/mo add-on)

- **HomeKit alarm trigger when at home** — armed Mac + alarm + at-home detection → HomePod sirens, smart lights flash, smart locks engage; biggest domestic deterrent in the category
- Off-device photo backup
- Remote arm/disarm from anywhere
- Last-known location
- Multi-device family / fleet view (light enterprise lean)
- Push via APNs (requires thin backend)
