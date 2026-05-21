# Feature audit and pre-launch roadmap — what we have, what we lie about, what we should build

**Date:** 2026-05-21
**Mode:** directed
**Confidence:** high (on what we ship), medium (on competitor parity claims), high (on GO/NO-GO call)
**Estimated effort:** memo only; resulting epics measured under §11
**Estimated leverage:** Top of funnel. Every $29 sale is a function of (a) the demo showing a feature the buyer values, (b) the website not lying about what we ship, and (c) us not getting roasted on Show HN for a claim we can't back. This memo makes (b) and (c) tractable, and proposes the 1-2 features that meaningfully change (a).

---

## 1. Executive frame

Two things matter for launch:

1. **What we actually ship.** v1.4.1 is materially richer than `STRATEGY.md §1` describes. The strategy doc is stale — it still references v1.2 production state — but the code has moved through v1.3 and v1.4 features that were previously listed as "deferred." Big chunks of `STRATEGY.md §10`'s aspirational v1.3–v1.5 roadmap are *already implemented*. We don't have a feature-gap problem; we have a documentation, marketing-truth, and *one specific UX-gap* problem.

2. **What competitors ship that we don't.** After teardown of Prey, Unplug Alarm, HiddenApp, Pareto, OverSight, and Find My, there are exactly **three** customer-facing capabilities we lack at launch that would meaningfully change buyer behavior. Each is small. None require new architecture.

The pre-launch question isn't *"what should we build?"* It's *"can the marketing copy accurately describe the product, and are the 3 small gaps worth filling before Show HN?"*

---

## 2. What Vakter ships today — feature-by-feature, sourced from code

Listed by user-visible category. Citations to source files. Items marked **[Stale STRATEGY]** are features that are implemented in code but not credited in `STRATEGY.md §1`.

### 2.1 Arming + state machine
- **5 modes** (Normal, Travel, Library, Loaner, Cafe) with per-mode `graceSeconds`, `audible`, `photoCadence`, `alarmCapSeconds`, default alarm sound. `Sources/VakterShared/Mode.swift:15-130`.
- **Global hotkey arm**, user-customisable via `KeyRecorder`. Carbon `RegisterEventHotKey`. `Sources/VakterApp/KeyRecorder.swift` + `Sources/VakterShared/HotkeyStore.swift`.
- **Touch ID disarm** via screen-unlock signal — natural macOS auth path, no second prompt. `Signal.swift:36-37, 73-75`.
- **Loaner-mode auto-rearm** with 1h / 2h / 4h trust windows. `StateMachine.swift:314-322` + `Mode.swift:144-156`.
- **Three-phase lockless arm** (auth dialog can't soft-deadlock the helper). `StateMachine.swift:202-296`. Architecturally distinctive — competitors have none of this rigor.
- **Run Arm Demo** menubar item — arms without locking screen, then synthesises lid-close so user can hear chirp→grace→alarm. `StateMachine.swift:340-363`. **Unique to Vakter** as far as I can verify.

### 2.2 Triggers (signals observed while armed)
- Lid close (`LidObserver`)
- Power disconnect (`PowerObserver`)
- Bluetooth peer departure (informational only — see Anti-feature note below)
- Power button brief press (`PollingObserver`)
- Hotkey arm (`HotkeyObserver`)
- **Find My token cleared** — high-confidence theft signal, skips grace → straight to alarm. `Signal.swift:21-27`, `FindMyTokenWatcher.swift`. **[Stale STRATEGY: this was implemented as part of v1.x]**
- **Apple ID changed** — same high-confidence path. `Signal.swift:29-31`, `AppleIDChangeWatcher.swift`. **[Stale STRATEGY]**
- **Screen unlock** (the disarm path). `ScreenLockObserver.swift`.
- **System wake** — belt-and-braces alarm-on-wake if SleepGuard was ignored by Apple Silicon clamshell firmware. `WakeObserver.swift` + `Signal.swift:40-44`. **[Stale STRATEGY: this is a real distinctive defense, but unmentioned]**

### 2.3 Bluetooth proximity
- Up to 10 trusted peers (phone, AirPods, Watch). `TrustedPeerStore.maxCount` enforced.
- **Deliberate anti-feature**: trust loss is **informational only**, never auto-arms. The reasoning is in `Signal.swift:60-67`: pairing a phone and walking 15m to the coffee counter would otherwise false-positive. *We should ship this as a feature in the marketing copy, not an absence.* (See §6 improvements.)
- Pairing sheet with live RSSI bars + signal strength viz. `SettingsRoot.swift:1051-1200`.

### 2.4 Alarm output
- **9 alarm sounds**: 6 synthesised (classicSiren, sweepKlaxon, dualTone, calmChime, japaneseTwoTone, europeanNeeNaw) + 3 sample-backed (pulseAlarm, rhythmicKlaxon, urgentBeacon — Sonniss GDC). `AlarmSound.swift`.
- **Voice cue in 7+ locales** (the LocalePhrases module). Plays between siren tones.
- **Audio routes to internal speakers on alarm** via CoreAudio override — survives headphones being plugged in. (README claim, verified in `AudioController` design.)
- **Per-mode alarm cap** — Cafe mode tops out at 30 s so it doesn't become a community noise complaint. `Mode.swift:113-119`.
- **Test alarm** (3 s preview) in Diagnostics submenu.

### 2.5 Evidence capture
- **Photo burst** with `.normal` (3 frames at t=0, 2, 5) or `.burst` (frame at 0, then 5s for 60s, then 30s indefinitely) cadence. `Mode.swift:133-139`, `PhotoCapture.swift`.
- **10s ambient audio capture** as AAC, attached to alarm event. `AudioCapture.swift`. **[Stale STRATEGY: listed as v1.3 deliverable, already shipping]**
- **Location attachment** via CoreLocation probe with 10s timeout, cached fallback. `LocationProbe.swift`.
- **Apple Maps URL** embedded in iMessage. `EvidenceBundleBuilder.swift`.

### 2.6 Evidence delivery (off-Mac)
- **iMessage** via Messages.app + AppleScript (`iMessageEvidenceDelivery`).
- **Email** via Mail.app + AppleScript (`EmailEvidenceDelivery`). **[Stale STRATEGY: multi-channel delivery listed as v1.5 deferred, already shipping]**
- Fire-and-forget — never blocks alarm path. `EvidenceBundleBuilder.swift:36-46`.

### 2.7 Cloud-evidence backup (user-owned bucket)
- **Backblaze B2 native API** OR **presigned URL** (S3/R2/GCS/anything). `CloudEvidenceUpload.swift`.
- Credentials in Keychain, never on disk.
- Survives wipe — evidence is off-device before the thief authenticates. **[Stale STRATEGY: listed as v1.4 deferred, fully implemented]**

### 2.8 Event log + forensics
- **Tamper-evident Merkle hash chain.** Every event signs the previous event's hash; deletion breaks chain visibly. SHA-256, CryptoKit. `EventChain.swift`, `SECURITY.md §4`. **[Stale STRATEGY: listed as v1.3 deferred, fully implemented]**
- **Police-ready PDF export.** Single-page, includes device serial, photos, audio paths, chain verification, signed/sealed. `EvidenceReport.swift`, accessible from menubar dropdown ("Export incident report (PDF)…"). **[Stale STRATEGY: v1.3 deferred, fully implemented]**
- Event Log UI in Settings with filter chips (All/Armed/Grace/Alarm/Photos/Audio/Location), search, inline photo grid, audio player, MapKit pin, expandable details. `EventLogView.swift`.
- **Last-event preview row** in menubar dropdown (SwiftUI hosted). `MenuBarController.swift:608-711`.

### 2.9 Defenses checklist
- **12 checks** (not 20 as the README claims — see §3 Misleading Claims):
  1. FileVault
  2. Find My Mac (3-method probe — NVRAM dump → specific lookup → MobileMeAccounts plist; resilient across macOS versions)
  3. Application Firewall
  4. Firewall stealth mode
  5. Gatekeeper
  6. SIP (handles "partially enabled" correctly)
  7. Touch ID enrolment (handles macOS naming shift "Touch ID" → "Biometrics")
  8. Automatic login
  9. Screen-lock password + delay (checks both `askForPassword` and `askForPasswordDelay`)
  10. Lock-screen "if found" message
  11. macOS software updates (reads cache; doesn't hit Apple servers)
  12. Vakter in Login Items
- Categorised into 5 buckets, runs every 4 hours via `DefensesScheduler`.
- 30-day score history with sparkline trend card.
- Each check has a deep-link to System Settings.

### 2.10 Auto-arm engine
- **4 trigger types**:
  - Geofence exit (CoreLocation `CLCircularRegion`)
  - Wi-Fi disconnect (CoreWLAN, named SSIDs)
  - Idle for N seconds (CGEventSource)
  - Daily at HH:MM
- Per-rule cooldown to prevent re-fire chatter. `AutoArmEngine.swift` + `AutoArmRule.swift`. **[Stale STRATEGY: listed as v1.5 deferred, fully implemented]**

### 2.11 iOS companion app (source-only, unprovisioned)
- 4 tabs: Status, Events, Map, Settings. SwiftUI. `iOS/VakterCompanion/`.
- CloudKit-backed (user's private DB; zero server cost; E2E encrypted in transit).
- Remote arm/disarm via `VakterCommand` CloudKit records.
- **[Stale STRATEGY: listed as v1.4 epic / 2 weeks; source exists, blocked on Apple Developer Portal provisioning per `iOS/SETUP.md`]**

### 2.12 Apple Watch companion (source-only)
- Single-screen arm/disarm tile via WatchConnectivity → iPhone → CloudKit. `WatchOS/VakterWatch/`.
- **[Stale STRATEGY: listed as v1.4 epic, source exists, same provisioning blocker]**

### 2.13 Distribution + integrity
- **Notarised .dmg** with Hardened Runtime, Developer ID signed under Team ID 9TA5GB5UJH.
- **XPC peer code-signing requirement** pinned to our Team ID. Closes the "any process can call helper.arm()" hole. `XPCPeerVerification.swift` + `SECURITY.md §3`.
- **Three-binary process model** clearly documented: app (UI only), helper (user-level always-running), daemon (root, one method).
- **macOS-native crash report harvesting** (no PLCrashReporter, no telemetry — uses Apple's `~/Library/Logs/DiagnosticReports/`). `CrashReportCollector.swift`. User decides per-export.

### 2.14 macOS Shortcuts integration
- `VakterIntents.swift` defines `ArmVakterIntent` + `SetVakterModeIntent`.
- **CAVEAT**: `perform()` currently just `NSLog`s — there's a `TODO(week-3): once the menubar app talks XPC to the helper, this intent should dispatch to the helper's arm pathway.` See `VakterIntents.swift:19-26`. **This is a real gap; the Shortcut shell exists but doesn't actually arm.** Worth fixing pre-launch (small).

### 2.15 Branding + UX
- Lighthouse glyph + animated wordmark, calm-protector design language.
- 11-tab settings (General, Shortcut, Modes, Sound, Trusted Devices, Defenses, Auto-arm & Cloud, Notifications, Privacy, Event Log, About) — **note: BACKLOG #6 calls for consolidating 10→6.** Currently 11.
- Menubar appearance switcher: Lighthouse / Fake Battery / Hidden. `MenubarAppearance.swift`.
- VoiceOver labels on every NSStatusItem, sidebar row, sound row, mode card.
- 5-step onboarding sheet. `Onboarding.swift`.
- Arming overlay ("On watch") that renders before screen lock takes over.
- Dedicated About Window with hero LighthouseHeroMark.

### 2.16 Privacy + trust posture
- Zero telemetry. Zero accounts. Zero analytics.
- Single outbound network path: Sparkle appcast (not yet wired — see §3) and user-configured B2/email/iMessage destinations.
- 200-word `PRIVACY.md`.
- Real `SECURITY.md` with architecture diagram, threat model, "things we explicitly chose not to ship" section.
- security@vakter.app inbox + 90-day disclosure commitment.

**Total inventoried features: ~58 distinct user-facing capabilities or behaviors.**

---

## 3. Verifying the README competitor table (the 9 differentiator claims)

The table in `README.md:11-23` is the canonical public-facing claim grid. Each row scrutinised:

| Claim | Verdict | Evidence |
|---|---|---|
| **1. Closed-lid alarm on Apple Silicon via `pmset disablesleep`** | **TRUE** | `SleepGuard.swift` + root daemon shells `pmset disablesleep 1`. WakeObserver is the belt-and-braces fallback. Genuinely differentiated — Unplug Alarm doesn't survive lid-close on Apple Silicon according to its own description. |
| **2. Audio routes to internal speakers on alarm via CoreAudio override** | **PROBABLY TRUE** but unverified at code-line level — `AudioController.swift` mentions speaker override. Worth a dedicated test before shipping the marketing claim. **Action:** PO should file a release-warden verification feature. |
| **3. Touch ID disarm at lock screen** | **TRUE** via screen-unlock signal. The marketing line is honest. |
| **4. Configurable grace window (3–30 s)** | **TRUE** with caveat — `GraceSettings.minSeconds...maxSeconds` is the actual range; need to confirm those are 3 and 30. Visible in `SettingsRoot.swift:469-512` with presets 3/5/8/12/20s. Range is correct. |
| **5. Bluetooth proximity disarm (trusted devices)** | **MISLEADING.** The trusted-peers list exists, but trust loss is *informational only*. The README implies a "trusted-devices disarm" workflow that doesn't exist — there's no "your phone is nearby, no need to authenticate" path. The README oversells this. **Action:** Either rewrite the row to "Bluetooth trusted-device awareness (informational)" or build the feature (small — see §5). |
| **6. Custom global hotkey via Carbon RegisterEventHotKey** | **TRUE.** `KeyRecorder.swift`. |
| **7. Defenses audit: 20 checks across 5 categories** | **FALSE.** Code ships 12 checks. The 5 categories number is right. The 20 number is wrong. **Action:** Update README to "12 checks across 5 categories" OR build 8 additional checks (see §5 improvement #2). Pareto Security ships 32 Mac checks; we should be aiming higher than 12 anyway. |
| **8. Event log with inline photo thumbnails** | **TRUE.** `EventLogView.swift` renders photo grids inline. Audio playback + MapKit pin also there but uncredited. |
| **9. Silent one-time approval (no per-arm prompt)** | **TRUE.** SMAppService.daemon registration + the lockless arm flow. |
| **10. Notarised .dmg that just works** | **TRUE.** Scripts/notarize.sh + scripts/make-dmg.sh + staple. |
| **11. Price: $29 one-time** | **TRUE** as committed strategy. No backend wired yet — no payment processor — so the claim is aspirational. **Action:** website + DMG download flow must reconcile this with reality before any DMG link goes live with a price. |

**Summary: 8 true, 2 misleading (Bluetooth disarm, 20-checks), 1 false (12 vs 20 checks).**

**Critically missing claims that ARE backed by code** but aren't in the table:
- Tamper-evident Merkle hash chain
- Police-ready PDF export
- 10s ambient audio capture
- Cloud evidence backup (user-owned bucket)
- iMessage + photo burst + Maps URL
- Email evidence delivery fallback
- Auto-arm engine (4 trigger types)
- iOS companion + Apple Watch companion (in code, blocked on provisioning)
- 9 alarm sounds incl. locale-specific (Japanese two-tone, European nee-naw)
- 7-locale neural TTS voice cue
- Find My token clearing / Apple ID change detection (high-confidence theft signals)

The README undersells Vakter substantially. **This is a bigger problem than missing features** — we're not telling the buyer about half of what they're paying for.

---

## 4. Feature gaps vs. competitors (what they ship that we don't)

After teardown of Prey, Unplug Alarm, HiddenApp, Pareto Security, OverSight, Find My, the things they ship that we lack:

| Competitor | Their feature | Our gap | Severity |
|---|---|---|---|
| **Prey** | Remote screen lock from web dashboard | We have CloudKit-backed remote arm/disarm but lack a *web dashboard* (only iOS app, currently unprovisioned). | **MEDIUM** — the in-progress web evidence dashboard is a `STRATEGY §10` v1.4 item, partly buildable on the user-bucket. |
| **Prey** | Remote data wipe | We don't ship this. Apple's Find My already does it; we deliberately don't compete. | **LOW** — deliberate non-feature, defensible in marketing as "use Find My for wipe; we do the deterrent." |
| **Prey** | Dark-web credential monitoring | We don't ship this. Different product. | **NONE** — adjacent, not our wedge. |
| **Prey** | Full factory reset (remote) | We don't ship. Find My territory. | **NONE** — same as above. |
| **Unplug Alarm** | Push notifications via companion mobile app (separate from iMessage) | We have iMessage + email, no native push. iOS companion is built but unprovisioned. Apple's iMessage *is* effectively a push but isn't framed that way. | **LOW** — iMessage is functionally equivalent for our audience, but push framing matters in marketing. |
| **HiddenApp** | Screenshot capture during incident | Deliberately not shipped — falls in our "explicitly chose not to" list (creepy). | **NONE** — defensible non-feature. |
| **HiddenApp** | Warning message overlay (fullscreen "if found, contact…") | We have a `LoginwindowText` defenses check that *encourages* this, but we don't *display our own* takeover screen during alarm. | **MEDIUM-HIGH** — see §5 improvement #4. Cinematic in demo video. Low effort. |
| **Pareto Security** | 32 macOS security checks (vs our 12) | Real gap. We can shoot for ~20 in pre-launch (see §5 improvement #2). | **MEDIUM** — material to the "Defenses" pitch. |
| **OverSight** | Real-time alerts when *any* app accesses camera/mic | Not our category. Different threat model. | **NONE** — but worth crediting OverSight as "complementary" in the website, the same way we credit Find My. |
| **Find My** | Activation Lock (Apple-only capability) | Not ours to ship. | **NONE** |
| **Find My** | Locate after wipe (Apple-only) | Not ours to ship. | **NONE** |

**Adjacent things target customers (café workers, journalists, conference-goers) want that we don't address:**

1. **"Don't notify me when I just got up to refill my coffee."** Real café usability concern. We have grace + Cafe mode, but no *passive grace extension* when a trusted phone is nearby. The Bluetooth trust signal is right there, doing nothing. (See §5 improvement #3.)
2. **"I need to give the police something they'll actually take."** We solve this — PDF export — but the website doesn't talk about it. (See §6 improvement.)
3. **"What if the thief just opens the lid back up before grace expires?"** Lid-reopen during grace = currently does *not* cancel grace (the signal is ignored by default per `Signal.swift:62`). This is correct, but undiscoverable.
4. **"I left my Mac in a hotel room — can it arm itself when I leave?"** Yes — auto-arm engine. But auto-arm is buried in Settings → Auto-arm & Cloud and is unmentioned on the website.
5. **"Can I disarm with my Apple Watch instead of authenticating?"** No (Watch companion ships state, not biometric handoff). The hardware boundary makes this hard — and Touch ID at lock screen is already 1-tap — but it's a buyer-perception ask.

---

## 5. Proposed new features (bold-mode brainstorm)

Each item rated: one-line, why interesting, effort, risk, ship-when.

### NEW FEATURE 1 — Stealth lock-screen takeover ("STOLEN — please call XXX")
- **Description:** On alarm, render a fullscreen overlay (separate from macOS's lock screen) with user-configured "if found" text and a callback number. Survives the immediate screen lock — kicks in as soon as the helper detects the alarm.
- **Why interesting:** This is the single most *cinematic* feature for the launch demo video. It's what HiddenApp does well. Right now a thief grabbing a Vakter-armed Mac sees the normal macOS lock screen — generic, identical to every other Mac. The "STOLEN" overlay communicates back to them: "we know this is stolen, here's how to return it." Same psychological logic as a car-alarm flashing light. Cheap dramaturgy, high ROI.
- **Effort:** small (1-2 days). One NSWindow at .screenSaver level, SwiftUI content, dismiss on disarm.
- **Risk if shipped wrong:** false-positive renders a "STOLEN" overlay during a benign trigger. Mitigation: only renders during `.alarm`, not `.grace`. Add a Test Alarm preview flow.
- **Recommendation:** **SHIP BEFORE LAUNCH.** Highest cinematic-leverage feature.

### NEW FEATURE 2 — Audible "test it now" mode for buyers without an alarm reason
- **Description:** A 30-second "demo me a full incident from start to finish" button in the menubar, separate from the existing "Run arm demo." Produces a full lifecycle: arm chirp → simulated grace → simulated alarm → simulated photo burst → fake iMessage preview (not actually sent) → simulated disarm. With voiceover/captions narrating.
- **Why interesting:** Buyers who haven't been stolen-from yet have no way to internalise what they're paying for. The Snazzy Labs / 9to5Mac reviewer demo problem is: "I bought it, I armed it, nothing happened, was I scammed?" Existing "Run arm demo" is a developer-flavored thing; this is the buyer-flavored thing.
- **Effort:** medium (3-5 days, mostly choreography + copy).
- **Risk:** uncanny-valley if poorly scripted. Mitigation: have brand-keeper write the narration; record once.
- **Recommendation:** **SHIP IN 1.5.** Not blocking launch — `Run arm demo` is enough for v1 reviewers if we point them at it explicitly.

### NEW FEATURE 3 — "Calm Cafe" presence-aware grace extension
- **Description:** When Cafe mode is active AND a Bluetooth-trusted phone is in range AND grace fires, *extend* grace by 50% (e.g. 12s → 18s). The Bluetooth trust signal currently does nothing — wire it as a grace softener, not as a trigger.
- **Why interesting:** Solves the #1 Cafe-mode false-positive ("I got up to refill, lid-close from leaning my bag, alarm fires while I'm 4 feet away"). It's also a genuine product story: "Vakter knows you're nearby — it's still watchful, but it's not jumpy." The brand voice is the feature.
- **Effort:** small (1 day). Logic lives in `StateMachine.transition(to: .grace)`; read BT trust state from the BluetoothObserver, multiply graceSeconds.
- **Risk:** Power user complaint that "I wanted strict grace, Vakter is being too forgiving." Mitigation: opt-in toggle in Cafe-mode settings, default off in v1.5 then default on in v1.6 after data.
- **Recommendation:** **SHIP IN 1.5.** Strong differentiator vs Unplug Alarm.

### NEW FEATURE 4 — Defenses audit weekly digest (local notification)
- **Description:** Every Monday morning at user-set time, Vakter posts a macOS notification: "Defenses score: 87 (down 5 from last week). 2 things to fix: FileVault re-encryption needed, software updates pending." Tap-through opens the Defenses tab.
- **Why interesting:** Defenses score history is already collected (30-day sparkline) but only visible if the user opens the Defenses tab. A nudge surfaces it. Pareto Security has nothing like this; their cloud product does, but their free Mac app doesn't. Word-of-mouth: "Vakter told me I'd forgotten to re-enable FileVault."
- **Effort:** small (1 day). UNUserNotificationCenter + a once-a-week timer keyed to Calendar.weekday.
- **Risk:** notification fatigue if too noisy. Mitigation: weekly only, user can disable.
- **Recommendation:** **SHIP IN 1.5.** Sticky retention feature.

### NEW FEATURE 5 — "Custom" mode (sixth mode, all parameters configurable)
- **Description:** Adds a `VakterMode.custom` case. User picks grace seconds, audible bool, photo cadence, alarm cap, default sound — all editable in Settings → Modes. Persists alongside the other 5 modes.
- **Why interesting:** Powerusers + reviewers always ask "can I tweak the timing?" Right now grace is global, but everything else (audible, cap, cadence) is fixed per mode. Custom mode lets the buyer answer their own questions without us shipping more presets.
- **Effort:** small-medium (2 days). New mode enum case, new persistence file, new Settings UI block in `ModesTab`.
- **Risk:** "Why are there 6 modes?" decision paralysis. Mitigation: place Custom at the end of the spectrum, label "Advanced," small visual tweak.
- **Recommendation:** **SHIP IN 1.5.** Power-user feature; not launch-blocking.

### NEW FEATURE 6 — Wi-Fi-adaptive Cafe grace
- **Description:** If Vakter is in Cafe mode AND connected to a Wi-Fi SSID listed in user's "trusted networks" (Home, Office), use Library-mode grace (longer) and silent siren. If on an unrecognised SSID (a real cafe), use the strict Cafe parameters.
- **Why interesting:** Listed in BACKLOG.md #26 ("Smarter cafe mode adapts grace based on Wi-Fi SSID"). The plumbing is there (CoreWLAN already used by AutoArmEngine). Cheap to ship.
- **Effort:** small (1 day).
- **Risk:** minor.
- **Recommendation:** **SHIP IN 2.0+.** Auto-arm rules already do most of this — adaptive mode-within-mode is sugar on top, not urgent.

### NEW FEATURE 7 — YubiKey / hardware-key disarm (for the paranoid pro segment)
- **Description:** As BACKLOG.md #29. User pairs a YubiKey; presence (via WebAuthn or U2F over USB-C) is an additional disarm path alongside Touch ID.
- **Why interesting:** Real differentiator for journalists, infosec people, lawyers — the exact buyer profile that lurks in r/macapps and Show HN. Vakter becomes "the one anti-theft tool that infosec people respect."
- **Effort:** medium (2-3 days). LibFIDO2 or CoreFoundation USB enumeration.
- **Risk:** edge-case auth flow; YubiKey APIs evolving.
- **Recommendation:** **SHIP IN 2.0+.** Not v1.5 — let the launch audience speak first.

### NEW FEATURE 8 — Stealth-snitch mode (silent alarm, iMessage-only)
- **Description:** BACKLOG.md #30. User toggles "Stealth-snitch" — alarm fires silently (no siren, no voice), all evidence captured + delivered, no public embarrassment. For users worried about a false-positive in a public setting.
- **Why interesting:** Cafe mode is the cousin (silent in *Cafe* mode by default), but Stealth-snitch is mode-orthogonal — applies in Travel too.
- **Effort:** small-medium (1-2 days). New global toggle, audio.startAlarm(audible:) already supports the silent path.
- **Risk:** weakens deterrence claim ("Vakter screams") for people who turn it on — but it's opt-in.
- **Recommendation:** **SHIP IN 1.5.** Privacy-conscious users will love it.

### NEW FEATURE 9 — Apple Shortcuts: real arm/disarm wiring (close the existing TODO)
- **Description:** Wire `ArmVakterIntent.perform()` to actually call the helper's arm path via XPC. Currently it just `NSLog`s. The intent surface exists but is decorative.
- **Why interesting:** Power users on r/macapps love Shortcuts integration. "Arm Vakter when I activate Café focus" is a great word-of-mouth pitch. Adds zero new product surface — just wires what's there.
- **Effort:** small (4-6 hours). Plumbing through `HelperClient`.
- **Risk:** low. The XPC path is well-tested.
- **Recommendation:** **SHIP BEFORE LAUNCH.** Free differentiator. (See `VakterIntents.swift:19-26` for the existing TODO.)

### NEW FEATURE 10 — "If found, please contact…" QR code on alarm overlay
- **Description:** Extends Feature 1 (stealth lock-screen takeover). Adds a QR code that resolves to a unique vakter.app/found/<id> page where the finder can leave a reply for the owner.
- **Why interesting:** Mac is in a coffee shop, you left it, a kind stranger wants to return it but doesn't want to call a stranger from their phone. QR → "tell me where you are, I'll send the owner a message." Adds the "good Samaritan recovery" path.
- **Effort:** medium (3-5 days). Needs server endpoint at vakter.app — first time we ship anything server-side. Risk multiplier on "no cloud" positioning.
- **Risk:** **HIGH.** This violates the "no cloud, no servers" three-line brand positioning. Even if the relay is dead-simple, every security-paranoid buyer would call us out. Mitigation: the QR could resolve to a mailto: with prefilled text instead. Or the user can opt into a vakter.app relay. Or skip entirely.
- **Recommendation:** **SHIP IN 2.0+** with strong opt-in framing. Not pre-launch — too risky.

### NEW FEATURE 11 — "Insurance-ready" PDF report variants (US/EU/UK templates)
- **Description:** Extends EvidenceReport.swift. Adds region-aware templates that fit standard insurance-claim formats — e.g. UK police-report annexure layout, US homeowner's-insurance claim form, EU GDPR-compliant DSR format. Same data, region-specific structuring.
- **Why interesting:** "Hand to your insurance adjuster" is the killer line. Different countries have different expectations of what a "police report annexure" looks like. Easy win.
- **Effort:** medium (2-3 days). PDFKit work plus three template designs.
- **Risk:** low. We're not making legal claims; the PDF is informational.
- **Recommendation:** **SHIP IN 1.5** if we get an insurance-industry insider review of the templates first. Otherwise **2.0+**.

### NEW FEATURE 12 — Auto-pause when on calls (Zoom / FaceTime / Teams)
- **Description:** When a videoconference is active, soften grace 1.5x and silence the audible siren default. Restores on call end.
- **Why interesting:** Conference call false-positives are a real complaint cluster. Mac on cafe table, lid kicked accidentally during a video call, alarm fires during the meeting. Detect via `NSWorkspace.shared.runningApplications` or audio-session presence.
- **Effort:** small-medium (1-2 days).
- **Risk:** detection is brittle (each app's quirks).
- **Recommendation:** **SHIP IN 2.0+.** Validate first.

### NEW FEATURE 13 — Tamper-evident hash chain online verifier
- **Description:** vakter.app/verify — paste a PDF, see the chain-verification result with the SHA-256 chain visualized. Browser-side, no upload. Builds trust + serves as a Show-HN-able artifact.
- **Why interesting:** Cryptographic provenance for an anti-theft tool is rare. Show-HN-ready story: "We Merkle-chain our evidence log; here's the verifier so you don't have to trust us."
- **Effort:** medium (3-4 days). Client-side JS, WebCrypto API, no server.
- **Risk:** low.
- **Recommendation:** **SHIP IN 1.5.** Brand-keeper builds the page once the audit feature stabilises.

### NEW FEATURE 14 — Defenses checklist auto-fix (one-click toggles where macOS allows)
- **Description:** For checks where macOS supports programmatic toggle (Firewall on, Stealth on, Login Items toggle), add a "Fix" button. Pareto Security does this for some checks. Today every Vakter check is "Fix in Settings →" which deeplinks but requires manual click in System Settings.
- **Why interesting:** Reduces friction on the most common Defenses warnings. Converts the Defenses tab from "guilt trip" to "concierge." `STRATEGY §10 v1.5 item 2` already lists this.
- **Effort:** medium (3-5 days) per check; small per click. Limited by which checks Apple lets us toggle without sudo.
- **Risk:** macOS deprecations / privilege requirements; ship gating may be tight.
- **Recommendation:** **SHIP IN 1.5.** Strong second-release headline.

### NEW FEATURE 15 — Snazzy / launch-week pre-recorded "incident" tutorial video, in-app
- **Description:** A 60-second video bundled with the app, accessible from Help → "See it in action." Plays inside an in-app sheet. No internet needed.
- **Why interesting:** Buyers who can't try the live demo (e.g. they're at a cafe and don't want to fake-alarm) can still see what they're paying for. Reviewers can reference it.
- **Effort:** small (the video is a brand-keeper task; in-app player is 1-2h).
- **Risk:** the video has to be *good*. Brand-keeper deliverable.
- **Recommendation:** **SHIP BEFORE LAUNCH.** Brand-keeper has this on the backlog already (BACKLOG #2).

---

## 6. Existing-feature improvements (sharpening what we already have)

### IMPROVEMENT 1 — Defenses audit: add 8 checks to reach 20 (back the README claim)
- **What:** Add the gap-checks. Candidates (sourced from Pareto's list + macOS surface):
  1. AirDrop discovery scope (Everyone vs Contacts Only)
  2. AirPlay receiver (off when not in use)
  3. File sharing off
  4. Media sharing off
  5. Printer sharing off
  6. Remote Login (SSH) off
  7. Remote Management (ARD) off
  8. Boot security level (Full Security on Apple Silicon)
- **Why:** README claims 20; we ship 12. Either we ship the 8 checks or we update the README. Shipping the checks is the better story.
- **Effort:** medium (1 day per 4 checks = 2 days). Each is a shell-out + status mapping, modeled on existing checks.
- **Recommendation:** **SHIP BEFORE LAUNCH.**

### IMPROVEMENT 2 — Defenses checklist over XPC (close `XPCService.swift:127` per `STRATEGY §1`)
- **What:** Per the staleness note in STRATEGY §1, the defenses checklist only works in-app, not surfaced via the helper. Wire it.
- **Why:** Listed as an explicit TODO in `STRATEGY.md §1`. Pre-launch hygiene.
- **Effort:** small (1 day).
- **Recommendation:** **SHIP BEFORE LAUNCH.**

### IMPROVEMENT 3 — Bluetooth trust signal: actually act on it (grace softening, not informational)
- **What:** Today BT trust loss is logged but does nothing. Make trust *gain* extend grace by N seconds (per §5 NEW FEATURE 3) and trust *loss* shorten it during Travel mode.
- **Why:** It's a wasted signal. The README copy hints at functionality we don't deliver.
- **Effort:** small.
- **Recommendation:** **SHIP IN 1.5.**

### IMPROVEMENT 4 — Settings tab consolidation 11→6 (BACKLOG #6)
- **What:** Currently 11 tabs. Brand-keeper sees this; backlog calls for 10→6 (the backlog is one tab behind reality — we shipped Auto-arm & Cloud since then). Updated target: **6 tabs**: General (+ Shortcut + Sound), Modes, Trusted Devices, Defenses, Notifications (+ Privacy + Auto-arm & Cloud), Event Log (+ About).
- **Why:** First-launch impression. 11 tabs reads bloated. Power-utility apps (Bartender, Tot, CleanShot) all stay ≤7.
- **Effort:** small-medium (1-2 days).
- **Recommendation:** **SHIP BEFORE LAUNCH.** Marketing screenshots will use the consolidated layout.

### IMPROVEMENT 5 — Wire Sparkle for auto-updates (`SPARKLE_SETUP.md` exists, never executed)
- **What:** Follow `SPARKLE_SETUP.md`. Generate EdDSA key, host appcast.xml at vakter.app/appcast.xml, wire `SPUStandardUpdaterController` into the app.
- **Why:** Without Sparkle, every user is a manual-update liability. STRATEGY §9 item 4. Launch blocker — the moment we ship v1.4.1 to a few buyers, we lose control of the update flow until Sparkle is live.
- **Effort:** small (1 day per setup doc) + small website work (host appcast).
- **Recommendation:** **SHIP BEFORE LAUNCH.** Linked to the deployed website (#9 epic).

### IMPROVEMENT 6 — iOS + Watch companion: get them provisioned + into TestFlight beta
- **What:** Code exists at `iOS/VakterCompanion/` and `WatchOS/VakterWatch/`. Both are unprovisioned. Get into Apple Developer Portal, create CloudKit container, set up TestFlight.
- **Why:** Source-built companions earn the "two-device protects each other" launch story (STRATEGY §10 v1.4). Without TestFlight, the iOS app is invisible to buyers at launch.
- **Effort:** medium — primarily human time in Apple's portals. Code work is small (Info.plist + entitlements + signing). 1-3 days wall-clock, much of it Apple review.
- **Risk:** Apple TestFlight review delay (2-7 days typical). Start now if intended for launch.
- **Recommendation:** **SHIP BEFORE LAUNCH IF POSSIBLE.** If TestFlight is too slow, slip to v1.5 and pre-announce "iOS companion in beta now, GA in 4 weeks."

### IMPROVEMENT 7 — README + website: tell the truth about what ships
- **What:** Update README.md comparison table and website to reflect *actual* shipping features. Add: hash chain, PDF export, audio capture, cloud backup, email delivery, 9 sirens, voice cue, auto-arm engine, Find My token watcher, Apple ID change watcher. Correct: 12 checks (not 20), Bluetooth proximity is informational only.
- **Why:** We're underselling by ~40%. Honest, complete claims convert better than padded ones — and roasted on Show HN for the 20-claim is the kind of thing that kills a launch.
- **Effort:** small (4-6 h for brand-keeper).
- **Recommendation:** **SHIP BEFORE LAUNCH. Critical.**

### IMPROVEMENT 8 — Police PDF export: link from Event Log alarm rows, not just menubar
- **What:** Currently "Export incident report (PDF)" is only in the menubar dropdown. Add a per-alarm "Export this alarm as PDF" inline in the Event Log row.
- **Why:** Buyer expectation. When you click an alarm event, the "give to police" action should be inline.
- **Effort:** small (3-4 h).
- **Recommendation:** **SHIP IN 1.5.**

### IMPROVEMENT 9 — Onboarding: include a real "test the alarm" step as Step 4 ("Hear the alarm")
- **What:** `Onboarding.swift` already has a `hearAlarm` step. Verify it does the full test (siren + voice cue + photo permission prompt). If not, expand it.
- **Why:** First-launch trust. The user should hear the siren during onboarding so they internalise what they're buying.
- **Effort:** small (verify + tweak, ~2-4 h).
- **Recommendation:** **SHIP BEFORE LAUNCH.**

### IMPROVEMENT 10 — Trusted-peers Bluetooth: surface peer last-seen time in the row
- **What:** Today the row shows display name + UUID prefix. Add "Last seen: 3 min ago" so the user knows whether the BT scan is working.
- **Why:** UX friction reduction — the #1 question about trusted peers is "is it working?"
- **Effort:** small (3-4 h).
- **Recommendation:** **SHIP IN 1.5.**

---

## 7. The pre-launch GO / NO-GO call

**Recommendation: GO with v1.4.1 as launch product, subject to ~5-day pre-launch fix list.**

### Why GO:

1. **Vakter's feature surface is materially richer than any direct competitor.** Unplug Alarm has ~5 features; we have ~58. Prey is enterprise-flavored; we own the indie consumer slot they vacated. The "category leadership at indie pricing" pitch is real.
2. **Architecture is sound.** Three-binary process model, XPC peer pinning, Merkle event chain, three-phase lockless arm — these are *engineering* differentiators that earn power-user trust in r/macapps and Show HN. Worth more than another 5 product features.
3. **The wedge is uncontested.** Apple Find My (free, passive) + enterprise B2B (Prey, Absolute) + dead indies (Undercover, GadgetTrak, iAlertU) + 1 living solo competitor at $9.99/yr (Unplug Alarm) = the consumer middle is empty. We show up in a vacuum.
4. **The brand voice is consistent and shippable.** Calm-when-nearby, fierce-when-stolen; no cloud, no telemetry, no accounts. Three-line opening on the homepage closes ~40% of the "but-can-I-trust-it" gap on its own (STRATEGY §5).

### Why NO-GO would be tempting (but wrong):

- *"We have only 12 defenses checks, claim 20."* — Fix in 1-2 days, see Improvement 1.
- *"Sparkle isn't wired."* — Fix in 1 day, see Improvement 5.
- *"iOS companion not provisioned."* — Begin Apple submission *now*; if TestFlight isn't ready by launch week, soft-announce as "in beta, GA in 4 weeks" — not a blocker.
- *"Bluetooth trust is informational only."* — Either rewrite the README row OR ship Improvement 3 + NEW FEATURE 3.

None of those individually justify pushing the launch back a quarter. **Each is a multi-hour fix, not a multi-week one.**

### Why GO is risky to ignore:

- Show HN audience is in **early summer** mode through July, then declines through August. Every week of slip lowers ceiling. We're already inside the 6-week launch sequence window (STRATEGY §8 puts us at Week -6 right now).
- Sparkle setup, payment processor wiring, MacPaw / Setapp application — these are *also* multi-week serial dependencies. If we don't start them now we slip the whole launch.

### The 5-day pre-launch fix list (deliverable as one PO epic):

1. **README + website honesty pass** — accurate feature matrix, all current claims sourced. (small, 4-6 h, brand-keeper)
2. **Defenses: 8 new checks to reach ~20 to back the claim.** (medium, 2 days, mac-engineer)
3. **Wire Sparkle for auto-update** per `SPARKLE_SETUP.md`. (small, 1 day, mac-engineer)
4. **Settings tab consolidation 11→6.** (small-medium, 1-2 days, mac-engineer)
5. **Stealth lock-screen takeover ("STOLEN — call X")** for the cinematic demo. (small, 1-2 days, mac-engineer)
6. **Wire `ArmVakterIntent.perform()` to actually arm via XPC** — closes the existing TODO. (small, 4-6 h, mac-engineer)
7. **Verify onboarding hearAlarm step plays the actual siren + voice cue.** (small, 2-4 h, mac-engineer + release-warden)
8. **Close `XPCService.swift:127`** — defenses checklist over XPC. (small, 1 day, mac-engineer)

Plus in parallel (no engineering cost):

9. **Start iOS/Watch provisioning + TestFlight** — week of Apple lead time. (human + mac-engineer)
10. **Brand-keeper: rerecord the in-app demo video** featuring the new stealth lock-screen overlay. (medium, 2-3 days)

Total agent effort: ~9 working days of mac-engineer time, ~3 working days of brand-keeper, ~2 days of release-warden verification. **In parallel with the existing #9 deploy-vakter.app epic, this lands in ~7-9 calendar days.**

---

## 8. The 1.5 release (4-6 weeks post-launch)

The features we *don't* ship at launch, sequenced for the first post-launch release:

1. **"Calm Cafe" presence-aware grace extension** (NEW FEATURE 3) — wires the dormant Bluetooth trust signal.
2. **Defenses auto-fix buttons** for the checks macOS allows (IMPROVEMENT/STRATEGY §10 v1.5 item 2).
3. **Defenses weekly digest notification** (NEW FEATURE 4).
4. **Stealth-snitch silent-alarm mode** (NEW FEATURE 8).
5. **Custom mode** (NEW FEATURE 5).
6. **"Insurance-ready" PDF report variants** (NEW FEATURE 11) — if insurance industry feedback validates.
7. **Tamper-evident hash chain online verifier** (NEW FEATURE 13) — Show-HN-able artifact for a second-wave post.
8. **Audible "test it now" buyer demo flow** (NEW FEATURE 2).
9. **Wi-Fi-adaptive Cafe grace** (NEW FEATURE 6).

These are the "calm follow-up release" — no new architecture, builds on what's there. Lays groundwork for 2.0 (web dashboard, YubiKey, video-call detection, QR found-me page).

---

## 9. Risks and what we're betting against

- **Risk: thieves get smarter and learn to cover the camera in second 2.** Audio capture mitigates. Continuous burst (STRATEGY §10 v1.3) — already shipping — extends the capture window.
- **Risk: macOS Sequoia .x update breaks `pmset disablesleep` semantics.** SECURITY.md commits to a third-party audit at $50k MRR; that's the long-term defense. Short-term: release-warden has the smoke test.
- **Risk: payment processor (Stripe / Paddle) takes longer than expected.** Outside this memo. Tracked separately.
- **Risk: Show HN crowd notices the "20 checks" claim is wrong.** Eliminated by Improvement 1 (ship 8 more checks) OR Improvement 7 (update claim to 12).
- **Risk: Apple announces their own anti-theft feature at WWDC 2026.** Low probability (Find My is Apple's answer; deepening it would cannibalise; Apple historically doesn't ship deterrents). If they do, Vakter's product story shifts to "we did it first + we keep the alarm working when Find My is wiped." Survivable.
- **Risk: Bluetooth-trust signal "actually act on it" creates false-negatives** (you walked away with your phone in your pocket, Vakter softened grace, thief walked off with the Mac). Mitigation: only applies in *Cafe* + *Library* modes, never Travel.

---

## 10. Out of scope for this memo

- Payment processor selection (Stripe vs Paddle vs Gumroad vs LemonSqueezy).
- Setapp application timing.
- MacPaw direct submission timing.
- DMG-on-CDN epic (Phase 2 of #9 deploy-vakter.app).
- Pricing experiments / coupon strategy.
- Localisation beyond the 7 locales that already have voice phrases.
- Linux / Windows / web app — never.
- Mac App Store sandboxable version — defer (STRATEGY §10 explicitly cuts).
- Hidden post-wipe tracking — never (deliberate omission per SECURITY.md §10).
- Real password swap / Adversary mode — defer to v1.6+ with onboarding redesign.

---

## 11. Directive

Linked file: `.claude/inbox/po/0003-feature-roadmap.md`

The PO directive proposes **two epics**:

1. **Epic A — Pre-launch reality check + 5-day fix list.** The 8 items from §7. p1, ships in 7-9 calendar days. **Highest priority.**
2. **Epic B — Post-launch v1.5 backlog (consolidate plan).** The 9 items from §8 — file as a tracked epic but don't dispatch until launch is done. p2.

PO breaks each into features and labels with the appropriate `agent:` ownership.

---

## 12. The one-paragraph summary

Vakter v1.4.1 is shipping-grade. The feature surface is materially richer than STRATEGY.md credits, materially richer than any indie competitor, and in a category vacuum at the consumer slice. The pre-launch problem is (a) the README and STRATEGY documents undersell what we ship by ~40%, (b) one specific claim (20 defenses checks) is false, (c) Sparkle isn't wired, (d) the iOS/Watch companions are unprovisioned, and (e) the Bluetooth trust signal is dormant. Fix (a)-(c) and (e) in a 5-day pre-launch sprint; start (d) Apple paperwork in parallel; ship. Hold for nothing else.
