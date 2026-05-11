# Bootstrap: Anchor

> Watch over your MacBook. One shortcut, no subscriptions, no bloat.

## Why

People who work from cafés, libraries, airports, and coworking spaces have a recurring small anxiety: *I want to use the bathroom, but I can't leave my $3,000 MacBook with strangers.* Apple's Find My Mac is great after a theft — useless during one. The existing market for "during-theft" deterrent apps is small but proven: Unplug Alarm and Clyde have shipped commercially viable products on weak feature sets (lid + power signals only, no thoughtful arming logic, dated branding).

The wedge is **a calmer, smarter product**. One intentional shortcut (`⌘⌃⌥L`) both locks the Mac and arms the alarm. Touch ID disarms. No auto-arming, no settings panels, no false-positive nightmares. The product fits on a billboard.

## Who it's for

- Digital nomads working from cafés
- Students in libraries / lecture halls
- Travelers in hotels and airports
- Anyone whose MacBook routinely sits in semi-public space

Not for: enterprise fleets (Prey's market), theft recovery focus (Undercover's market), or users who want background magic and never have to think about it.

## What we're building

A native macOS menubar app for Apple Silicon Macs that:

1. Listens for a global keyboard shortcut. When pressed, it locks the screen and enters **armed** state.
2. While armed, watches three signals: lid close, power disconnect, trusted Bluetooth peer leaving.
3. On any signal, enters a **grace period** (5–10 seconds, gentle escalating chirp). Touch ID brief-tap silently disarms. Full unlock disarms.
4. On grace timeout, fires a **very loud alarm** and captures a photo from the FaceTime camera. Alarm continues until Mac is unlocked.
5. Onboards via a designed flow that pre-sells each macOS permission and ends with a hands-on demo arm + alarm preview.

## Differentiation

| | Anchor | Unplug Alarm | Clyde | MacGuard | Prey |
|---|---|---|---|---|---|
| Manual key-combo arming | ✅ | ❌ | ❌ | ❌ | ❌ |
| Lid + power + BT signals | ✅ | ✅ (no BT) | lid only | ✅ | ❌ |
| Multiple trusted BT peers | ✅ | ❌ | ❌ | up to 10 | ❌ |
| Touch ID brief-tap silence | ✅ | ❌ | ❌ | ❌ | ❌ |
| Voice cue alarm (TTS) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Power-button intercept | ✅ | ❌ | ❌ | ❌ | ❌ |
| Modes (Normal/Travel/Library/Loaner) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Pre-flight security checklist | ✅ | ❌ | ❌ | ❌ | ❌ |
| Shortcuts / Focus integration | ✅ | ❌ | ❌ | ❌ | ❌ |
| Lock-screen last-alarm summary | ✅ | ❌ | ❌ | ❌ | ❌ |
| Calm-protector brand | ✅ | ❌ (loud red) | ❌ | n/a OSS | ❌ enterprise |
| One-time price, no sub | ✅ | partial | partial | free | freemium |
| Apple Silicon native | ✅ | ✅ | ✅ | ✅ | ✅ |

## Scope

### In scope (v1)

**Core loop**
- Apple Silicon Macs only (M1 and later)
- macOS 14 (Sonoma) and later
- Single-device, local-only operation
- Customizable global hotkey (default `⌘⌃⌥L`)
- Lid / power / Bluetooth peer signals
- Multiple trusted Bluetooth peers (not just one)
- Camera photo on alarm (stored locally)
- Designed onboarding flow with permission pre-sell

**Deterrent surface**
- Voice cue alarm: spoken phrase repeats between siren tones via AVSpeechSynthesizer (user-customizable, localized to system language)
- Power-button intercept while armed: brief press during Armed enters Grace instead of triggering sleep
- Lock-screen "if found" message — owner-configurable
- Last-alarm summary embedded in lock-screen message ("Last alarm: 11 May 2026, 14:32") to amplify perceived surveillance

**Modes**
- Four preset modes selectable from menubar: Normal, Travel, Library, Loaner
- Each mode adjusts: grace duration, audible vs haptic-only alarm, trust window

**Defense posture**
- Pre-flight security checklist screen: FileVault, Find My, password, screen auto-lock, login-window message, firmware password
- One-click navigation to System Settings for each unmet item

**Apple-pro integrations**
- App Intents / Shortcuts: "Arm Anchor", "Set Anchor mode" exposed as Shortcuts actions
- Focus mode triggers: any Shortcut can fire Anchor (e.g., enable "Café" Focus → arm)

**Business**
- Direct-download distribution via website (notarized .dmg)
- $19 one-time purchase, 14-day full-feature trial

### Out of scope (v1) — sequenced for later

**v1.5 — iPhone companion (BLE only, no backend)**
- iPhone haptic during grace period (the biggest UX win)
- Continuity Camera as 2nd-angle photo capture during alarm
- Apple Watch on-wrist inference (via BT peer state)
- On-device iPhone push when alarm fires
- Stronger custom-paired BLE proximity (replaces generic BT peer for pairing users)

**v2 — cloud tier ($4/mo or $36/yr add-on)**
- HomeKit alarm trigger when at home (HomePod sirens, lights flash)
- Off-device photo backup
- Remote arm/disarm from anywhere
- Last-known location
- Multi-device family / fleet view
- Push via APNs (requires thin backend)

**Cut entirely**
- Auto-arming heuristics (WiFi geofence, lid-open-and-locked rules) — user-rejected for false-positive risk and complexity
- Pre-Apple-Silicon Macs
- Mac App Store distribution (sandbox blocks required APIs)
- Stranger-face detection — breaks calm-protector brand
- "Plan B" simulated-hardware-failure trick — feels manipulative
- Continuous keystroke logging post-theft — privacy cost too high
- Theft recovery as a focus (Find My Mac handles this; we deter, not recover)

## Success criteria

- Trial → paid conversion ≥ 8%
- Time from install to first successful arm < 3 minutes (90th percentile)
- < 1% alarm-fire false-positive rate per active user per month
- First-month: 200 paid users, $4k MRR-equivalent
- Six-month: $5–10k MRR-equivalent, one viral TikTok hero clip (≥1M views)

## Pricing

- **One-time:** $19 USD (Lemon Squeezy or Paddle)
- **Trial:** 14 days, full features, no card required
- **No free tier** (positions premium, avoids dilution)
- **v2 cloud add-on (future):** $4/mo or $36/yr — adds iPhone push, remote arm/disarm, location, off-device photo backup

## Brand

- Working name: **Anchor** (alternates: Heron, Vigil)
- Tagline: *"Anchor your Mac. Walk away in peace."*
- Visual: ivory + deep navy, single accent, generous whitespace, monochrome icon
- Copy tone: reassuring, never alarmist
- Sound: warm thermostat-tap chirp for arm; pure sine-sweep alarm (loud, not police-siren tacky)

## Risks

- **Apple bundles this in macOS 17.** Mitigation: ship fast, build brand before Apple notices the wedge.
- **Permissions friction kills install→active rate.** Mitigation: onboarding is a designed feature, not an afterthought.
- **TAM ceiling is modest** (~$30–80k/year as indie). Founder must accept this as a lifestyle business, not a venture trajectory.
- **Hardware-loud audio may be constrained** on Apple Silicon. Mitigation: investigate AVAudioEngine gain ceiling and pre-rendered loudness-maximized samples before committing to alarm UX.
