# Vakter Changelog

Technical changelog maintained by the release warden. User-facing changelog lives at `Website/changelog/index.html`.

---

## Unreleased (v1.5-dev) — in flight as of 2026-05-28

These entries are merged to main as Wave 1 of the Watch Pivot (Epic #52). They are NOT a release. No version bump, no sign/notarize/ship cycle. They ride with v1.5 when that release is gated.

**PRs merged this cycle:** #81 (ticket #53), #82 (ticket #54), #83 (ticket #57)
**Remaining before v1.5:** #55 (security/changelog page), #56 (Stripe webhook — needs-human), #58 (blog post)

### Website hero now leads with the lid-close audio-override moat (#53, PR #81)

`Anchor/Website/index.html` only. Net diff: 1 file. Squash of commits b730614 + c08670f (revert of stray contamination).

- Hero body paragraph (`.hero-sub`) now opens: "When the lid closes, Vakter keeps the speakers live and fires the alarm anyway. Every other Mac anti-theft tool goes quiet with the lid. This one doesn't — a daemon-level audio override that no competitor has solved."
- The lid-close moat is sentence 1 of the hero body, sentence 1 of the meta description, and sentence 1 of the OG description. Not buried.
- v1.5 features framed as forward-looking throughout: "In v1.5, the watch expands", "Coming in v1.5 — early 2026" callout block. No false-shipping claims.
- Pricing: "€29 one-time" in meta and CTA. Old "€12/year" subscription language removed. "One licence. Every v1.x release included. No subscription." added to pricing note.
- "macOS 14+ · AI features require 15.1+" added to hero-meta row (requirements disclosure, not a false claim).
- Banned words: 0.

### Roadmap page added at vakter.app/roadmap/ (#54, PR #82)

`Anchor/Website/roadmap/index.html` (new, 863 lines) + `Anchor/Website/index.html` (footer link). Net diff: 2 files.

- 8 sections: §01 Today (v1.4.4), §02 v1.5, §03 v1.6 Mail Watch, §04 v1.7 Messages Watch, §05 v1.8 Web Watch + Mac Watch, §06 v2.0 Behavioral Baselining + B2B, §07 The contract that never changes, §08 Roadmap honesty.
- Matches openspec/changes/vakter-watch-pivot/tasks.md milestone ordering.
- 8 "never ship" bullets: No cloud LLM, No telemetry, No accounts, No remote wipe, No hidden post-wipe tracking, No background screen recording, No user-submitted threat reports, No subscription on existing features.
- All v1.6+ sections carry explicit future-dated labels (Q3/Q4 2026). No false-shipping claims.
- Pricing throughout: "€29 lifetime purchase", "No subscription added later", "€29/Mac one-time" for B2B bulk.
- Footer link `<a href="./roadmap/">Roadmap</a>` added to Trust column of Website/index.html.
- Banned words: 0.

### LicenseManager scaffolding added; activation flow inert until #56 Stripe wires the webhook (#57, PR #83)

`Anchor/Sources/VakterShared/LicenseManager.swift` (new), `Anchor/Sources/VakterApp/MenuBarController.swift`, `Anchor/Sources/VakterApp/SettingsRoot.swift`, `Anchor/Tests/VakterSharedTests/LicenseManagerTests.swift` (new, 23 cases).

**Security properties verified by gate:**
- Storage: Keychain only (`app.vakter.mac.license` / `kSecClassGenericPassword`). No UserDefaults, no plist, no disk file.
- Accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — launch-at-login compatible, never iCloud-synced.
- No network calls: `URLSession`, `NSURLConnection`, `dataTask`, `URLRequest` — all 0 matches in LicenseManager.swift.
- No key logging: `NSLog` at activate writes only `tier.rawValue`, never the key. Write-failure log contains no key material.
- No clipboard exposure: no `NSPasteboard` writes anywhere in the license path.
- Dev keys `VAKTER-DEV-FREE` / `-ESSENTIAL` / `-BUSINESS` are intentionally hardcoded with `VAKTER-DEV-` prefix so `strings` audits find them immediately. Not secrets; documented debug affordances.
- Production key format `VKT-XXXX-XXXX-XXXX-XXXX` accepted as structurally valid (Essential tier) at v1.5. Cryptographic signature check deferred to #56.

**Upgrade menubar item:**
- `if !LicenseManager.isPaid()` gate at MenuBarController.swift:325 — item is built only for free-tier users, never shown to paid users.
- Clicking opens `https://vakter.app/upgrade` in the default browser via `NSWorkspace.shared.open(url)`. No payment UI inside the app.

**Activate panel (Settings → General):**
- `ActivateVakterSection` embedded at bottom of `GeneralTab`.
- Free-tier layout: TextField + Activate button (disabled when input empty). Button clears the field on success so the key doesn't linger in `@State`.
- Paid-tier layout: confirmation pill only (`checkmark.seal.fill` + tier label + "active" status pill). No editable field — key cannot be copied or viewed.
- `resultRow(_:)` shows green checkmark + tier name on `.activated`, red X on `.rejectedUnrecognised` or `.rejectedMalformed`.

**Minor documentation inaccuracy (non-blocking):** Comment at SettingsRoot.swift:796 says "The field even uses `.textSelection(.disabled)` for the success state" but the paid layout has no text field at all — the comment is inaccurate but the security behavior is correct (no field to select from). Flagged for engineer cleanup in a follow-up commit; does not warrant rejection.

**Café-fix baseline verified:** `Signal.swift:triggersGrace` — `.bluetoothTrustLost` remains in the `false` bucket. PR #83 does not touch Signal.swift.

**Test results:**
- `swift test` (PR #83 branch, pre-merge): 164/164 pass (includes 23 new LicenseManagerTests, pre-existing 29 DefenseChecklistTests)
- `swift build --configuration release --arch arm64`: clean (pre-existing AppDelegate-Sendable warnings only)

---

## v1.4.4 — 2026-05-21

**Notarization submission ID:** 27fc4e6a-721b-4054-b32f-a67fc8b2688f
**CFBundleVersion:** 4
**Merged PRs:** #48 (ticket #23)
**Version bump rationale:** Patch bump (1.4.3 → 1.4.4). Settings tab consolidation is a pure UI restructuring; all backing stores unchanged, no API-level breaks, no schema migration.

### Feature A.4 — Settings tab consolidation 11→6 (ticket #23, PR #48)

`SettingsRoot.swift`, `AutoArmAndCloudTab.swift`, `SettingsTabs_Notifications_Privacy.swift`, `MenuBarController.swift`, `LocalAlarmPreview.swift`.

Collapses the Settings window from 11 tabs to 6 composite tabs following the System Settings design language. Each new tab owns a page header + embedded section views; all backing data stores are unchanged.

New Section enum (SettingsRoot.swift:51-58):

| Old tabs absorbed | New tab |
|---|---|
| Shortcut + Sound + Grace + MenubarAppearance + StealthOverlay + LaunchAtLogin | General |
| Modes (unchanged) | Modes |
| Bluetooth (unchanged) | Trusted Devices |
| Defenses (unchanged) | Defenses |
| Notifications + Privacy/Diagnostics + AutoArm + Cloud | Alerts & Cloud |
| Event Log (unchanged) | Event Log |
| About | REMOVED — opens as NSPanel from "About Vakter" menu item (unchanged) |

Implementation notes:
- `GeneralTab` at SettingsRoot.swift:462 embeds ShortcutSection, SoundSection, GraceSection, MenubarAppearanceSection, StealthOverlayContactCard, LaunchAtLoginSection.
- `AlertsAndCloudTab` at SettingsRoot.swift:1890 embeds NotificationsSection, AutoArmAndCloudTab (composite section), DiagnosticsSection.
- `AutoArmAndCloudTab.swift` retained as a named type for blame-history continuity; rendered as a section rather than a top-level tab.
- `MenuBarController.swift`: stale breadcrumb "Settings → About → Send diagnostics" updated to "Settings → Alerts & Cloud → Send diagnostics" (commit 4765e31).
- `LocalAlarmPreview.swift`: doc-comment "Settings → Sound" updated to "Settings → General → Sound" (commit 4765e31).
- No hardcoded tab indices (selectedTab =, tabIndex ==, selection =) anywhere in Sources/.
- `AboutWindowController` path unchanged: MenuBarController.swift:309 wires "About Vakter" menu item to openAboutWindow() at :418.

### Adversarial gate checks (all green)

1. Section enum: exactly 6 cases, zero stale references to removed cases (shortcut, sound, notifications, privacy, autoArmAndCloud, about).
2. Hardcoded tab indices: none found.
3. About window wiring: MenuBarController.swift:309 → openAboutWindow() at :418 → AboutWindowController (AboutWindow.swift:16).
4. Persistence: GraceSettingsStore, AlarmSoundStore, AutoArmRuleStore, CloudEvidenceConfig all save/load through new tab structure. Spot-checked GraceSection (SettingsRoot.swift:497,532,540) and AlertsAndCloudTab (AutoArmAndCloudTab.swift:225,245,253,266).
5. StealthOverlayContactCard: reachable at GeneralTab body (SettingsRoot.swift:471). From-#24 feature accessible.
6. Onboarding stale refs: Onboarding.swift clean; 4765e31 breadcrumb commits confirmed; grep for "Settings → About" and "Settings → Sound" returns 0 lines.
7. Café-fix baseline: Signal.swift:52 — `.bluetoothTrustLost` in the false bucket of triggersGrace. Signal.swift not touched by this PR.

### Signal.swift café-fix baseline

Verified: `.bluetoothTrustLost` remains in the `false` bucket of `triggersGrace` (Signal.swift:52). Signal.swift not modified by PR #48.

### Ship verification (merged trunk)

- `swift test` (branch before merge): 141/141
- `swift build --configuration release --arch arm64` (branch): clean (pre-existing AppDelegate-Sendable warnings only)
- `./Scripts/build-app.sh release`: bundle assembled, 3 binaries in MacOS/, `embedded.provisionprofile` present
- `./Scripts/sign.sh`: signed as `Developer ID Application: Jonathan Gebru (9TA5GB5UJH)`, daemon → helper → app signed inside-out, bundle valid on disk
- Entitlements post-signing: all 4 iCloud keys confirmed (`icloud-container-environment`, `icloud-container-identifiers`, `icloud-services`, `ubiquity-container-identifiers`)
- `./Scripts/notarize.sh`: `status: Accepted`, submission ID `27fc4e6a-721b-4054-b32f-a67fc8b2688f`, stapled successfully
- `spctl --assess`: `source=Notarized Developer ID`
- `xcrun stapler validate /Applications/Vakter.app`: passed
- Post-swap pgrep: `Vakter` (pid 97764), `VakterPrivilegedDaemon` (pid 13161) alive; VakterHelper not yet spawned (on-demand LaunchAgent, normal at cold launch)

**Smoke gap (warden-flagged):** The new 6-tab Settings window was not opened on the running app to visually confirm correct tab order, correct section rendering, correct StealthOverlayContactCard positioning, or correct AlarmSound picker behavior. All of these are verified by code reading and test coverage, but live visual smoke test was not performed from the gate context (no UI access). Risk: a layout regression visible only at runtime could be present.

### PR #47 (ticket #20) — REJECTED this cycle

"README + website honesty pass" branch `vkt-20-readme-website-honesty` at HEAD 080970d still contains "in beta" at 4 locations (README.md:33, Website/index.html:1994, Website/index.html:2160, Website/changelog/index.html:551) and "provisioning and TestFlight in progress" at STRATEGY.md:87. Both greps required to return 0 lines by acceptance criteria. Returned to brand-keeper / engineer for fix. Comment posted on PR #47.

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
