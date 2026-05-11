# Tasks: Anchor v1 → v1.5 → v2

Phased plan. Each phase ships and earns revenue before the next begins.

## Phase 0 — Spikes

**Pre-build spikes (CLI-testable) — DONE 2026-05-11**

- [x] **Audio loudness spike.** ✅ CoreAudio volume + mute control works without entitlements. See `spikes/01-audio/`.
- [x] **External-display clamshell / lid state spike.** ✅ `AppleClamshellState` readable + IOServiceAddInterestNotification registers cleanly. See `spikes/03-clamshell/`.
- [x] **Lock-screen message storage spike.** ✅ Resolved — modern path is `/Library/Preferences/com.apple.loginwindow`, not nvram. See `spikes/06-nvram/` (notes inside SPIKE_REPORT.md).
- [x] **AVSpeechSynthesizer + AVAudioEngine mixing spike.** ✅ Concurrent TTS + tone playback works cleanly. See `spikes/07-audio-mix/`.
- [~] **Touch ID brief-tap spike.** ⏳ Deferred — needs HID-level sensor observation via signed app (no public LAContext path). See `spikes/02-touchid/NOTES.md`. Plan: ship v1 without brief-tap unless this resolves cleanly in Phase 1 week 1.

**Environment-blocked spikes — DEFERRED to Phase 1 week 1**

- [ ] **`SMAppService` LaunchAgent spike.** Needs Xcode + signed app.
- [ ] **Power-button intercept spike.** Needs Xcode + Accessibility-granted signed app.
- [ ] **App Intents in menubar/LaunchAgent spike.** Needs Xcode app target.

## Phase 0.5 — Environment setup (user-driven, ~30 min)

Required before Phase 1 build can start.

- [ ] Install full **Xcode** from the Mac App Store (~15 GB)
- [ ] Enroll in **Apple Developer Program** ($99/year)
- [ ] Generate **Developer ID Application** certificate in Apple Developer portal
- [ ] Set up notarization credentials (app-specific password or App Store Connect API key)

## Phase 1 — v1 build (8–10 weeks)

### Foundation (week 1)

- [ ] Apple Developer account ($99) registered
- [ ] Xcode project: Anchor.app (menubar) + com.anchor.helper (LaunchAgent)
- [ ] XPC interface between app and helper
- [ ] Code signing + notarization pipeline (CI optional, manual OK for v1)

### Core state machine (week 2)

- [ ] State enum: Unarmed, Armed, Grace, Alarm
- [ ] Transition handler with side-effect dispatcher
- [ ] Event log writer (`~/Library/Application Support/Anchor/events/`)
- [ ] In-app event log viewer (last 30 events with photos)

### Signal sources (week 3)

- [ ] Global hotkey via `CGEventTap` (default `⌘⌃⌥L`, customizable)
- [ ] Lid state via `IOPMrootDomain` notifications
- [ ] Power state via `IOPowerSources` callbacks
- [ ] Bluetooth peer presence via `CoreBluetooth` with RSSI threshold
- [ ] Multi-peer BT trust group (1–10 peers, "any present = dampen, all absent = leave event")
- [ ] Power-button intercept (if spike result positive) — brief press → grace; `IOPMAssertion` suppresses sleep during grace

### Audio + photo (week 4)

- [ ] Pre-render alarm sample (brickwall-limited sine sweep)
- [ ] CoreAudio: read/restore user volume, force max, force unmute, force internal speakers
- [ ] AVFoundation: photo capture controller with mode-aware cadence (Normal: 3 frames; Travel/Library: burst then sustained)
- [ ] Soft chirp library: arm tone, grace chirps, disarm tone
- [ ] **Voice cue alarm**: AVSpeechSynthesizer integration; localized default phrases (en, nl, de, fr, es, pt, it, ja, ko, zh); user-customizable phrase in Settings; mixed with siren via AVAudioEngine and routed through forced internal speakers

### Touch ID disarm (week 4)

- [ ] LAContext-based full unlock as disarm
- [ ] Brief-tap detection (or fallback if spike result negative)
- [ ] Lock screen interactions confirmed across macOS 14/15/16

### Onboarding (week 5)

- [ ] Welcome screen with combo animation
- [ ] Shortcut customization picker
- [ ] Per-permission cards with annotated screenshots (one set per macOS version)
- [ ] TCC polling auto-advance
- [ ] Bluetooth peer pairing
- [ ] Demo arm walkthrough
- [ ] Alarm sample preview
- [ ] "If found" lock-screen message configuration

### Settings + menubar (week 6)

- [ ] Menubar: outlined shield (unarmed) / filled (armed) / pulse (grace) / spinning (alarm)
- [ ] Menubar menu: Arm now, Mode picker (Normal/Travel/Library/Loaner), Settings, Quit (blocked while armed)
- [ ] Settings panes: General, Shortcut, Bluetooth (multi-peer), Sound (incl. voice cue editor), Modes, Defenses (pre-flight), About
- [ ] Sparkle auto-update integration

### Modes + Loaner (week 6.5)

- [ ] Mode enum + per-mode grace duration / audible flag / camera cadence
- [ ] Mode-switch UI in menubar dropdown
- [ ] Loaner mode: trust-window picker (1h / 2h / 4h)
- [ ] Persistent menubar countdown during Loaner trust window
- [ ] Auto-rearm at window expiry + user notification

### Defense posture / pre-flight checklist (week 6.5)

- [ ] Read FileVault status (`fdesetup status` invoked via Process)
- [ ] Read Find My Mac state
- [ ] Read login-password presence, screen auto-lock, automatic-login flag
- [ ] Read firmware password status (`firmwarepasswd -check`)
- [ ] Read existing `LoginwindowText`
- [ ] Score calculator (0–10)
- [ ] Defenses pane UI with per-item CTAs (each opens System Settings deep link or guided walkthrough)
- [ ] Weekly auto-re-check; cache results

### Lock-screen message + last-alarm summary (week 6.5)

- [ ] In-app editor for "if found" message (up to 250 char combined)
- [ ] Write to `LoginwindowText` via privileged helper (admin auth on first set)
- [ ] Auto-append last-alarm suffix on every ALARM → UNARMED transition
- [ ] Toggle to disable dynamic suffix
- [ ] Truncation logic to keep combined message within Login Window display limit

### Shortcuts / App Intents (week 7)

- [ ] App Intents target in Xcode project
- [ ] `ArmAnchorIntent`, `DisarmAnchorIntent`, `SetAnchorModeIntent`, `SetAnchorLoanerWindowIntent`, `RunPreflightCheckIntent`
- [ ] Sample Shortcuts gallery (in-app) with one-tap install for "Café Focus → Arm" automation

### Polish + QA (week 8)

- [ ] All-hands false-positive testing in real venues (5 cafés, 2 libraries)
- [ ] Battery drain measurement during 4-hour armed session
- [ ] Memory/CPU profiling
- [ ] Accessibility pass (VoiceOver labels on menubar/settings)
- [ ] Crash reporter wiring (Bugsnag/Sentry, opt-in)
- [ ] End-to-end test of each mode in realistic conditions
- [ ] Voice cue test across all bundled localizations
- [ ] Pre-flight checklist verified across macOS 14, 15, 16

### Distribution + launch (week 9–10)

- [ ] anchor.app landing page (Framer or Webflow)
- [ ] Lemon Squeezy product, $19 one-time + 14-day trial license issuance
- [ ] License gate in app (offline-capable, simple HMAC)
- [ ] Notarized .dmg with custom DMG background
- [ ] Press kit page
- [ ] First 10 cold pitches to Mac press
- [ ] Product Hunt + Hacker News submissions queued

## Phase 2 — Marketing engine (parallel from week 6)

Builds in parallel with QA/launch — content needs to exist on launch day.

- [ ] Film 5 hero clips (1 staged café-snatch, 1 alarm-volume test, 1 day-in-life, 1 macro-combo, 1 onboarding walkthrough)
- [ ] Hire part-time editor (Upwork, $1000–2000/mo)
- [ ] Sign up for OpusClip or Repurpose.io (cross-posting)
- [ ] Stand up email list (ConvertKit or Beehiiv)
- [ ] First 10 cold DMs to Tier 1 influencers (free copies pre-launch)
- [ ] First SEO blog post: "How I leave my MacBook at cafes" (long-tail)
- [ ] List Anchor on AlternativeTo, MacUpdate, Setapp application

## Phase 3 — v1.5 iPhone companion (4–6 weeks, starts month 3)

- [ ] iOS App Store developer setup
- [ ] iOS app skeleton (SwiftUI, deployment iOS 17+)
- [ ] BLE pairing flow with Mac (QR-code initial pairing)
- [ ] Background CoreBluetooth central with state restoration
- [ ] **iPhone haptic on grace** — Mac sends BLE characteristic write the moment Grace starts; iPhone fires haptic feedback (local notification + UIImpactFeedback equivalent)
- [ ] **Continuity Camera integration** — Mac side: enumerate paired iPhone as additional `AVCaptureDevice` during alarm; capture frames from both cameras
- [ ] **Apple Watch on-wrist inference** — read watch BT advertisement state via the paired iPhone (Mac can't see watch directly)
- [ ] **Library mode haptic-only alarm** — when this companion is paired, Library mode replaces audible siren with sustained haptic + repeated photo burst
- [ ] On-device notifications when alarm fires (local push, no APNs)
- [ ] Remote disarm via BLE proximity
- [ ] App Store submission + review

## Phase 4 — v2 cloud (8 weeks, starts month 6)

Only begin if v1 + v1.5 are clearly working ($5k+ MRR-equivalent or strong adoption signals).

- [ ] Lightweight backend (Hetzner + Caddy + Postgres, or Cloudflare Workers)
- [ ] APNs push integration
- [ ] Remote arm/disarm endpoint (auth via device pairing)
- [ ] Off-device photo upload (S3-compatible)
- [ ] Location reporting on alarm
- [ ] **HomeKit integration**: when at home and armed-alarm fires, trigger HomePod sirens, flash smart lights, optionally engage smart locks; requires HomeKit accessory pairing in Settings
- [ ] Multi-device family / fleet view
- [ ] $4/mo or $36/yr subscription tier in Lemon Squeezy
- [ ] iOS app: cloud features unlocked by subscription
