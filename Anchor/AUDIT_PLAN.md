# Vakter — Audit Plan

Vakter is an anti-theft security app. It runs with privileged
permissions, talks to a root daemon, captures photos, and can ship
evidence off-Mac via iMessage. Quality and trust are non-negotiable.

This document defines **four recurring audits** that should run on a
calendar cadence, plus the one-time **pre-release audit** before every
DMG goes out.

Each audit lists:
- **What** is being checked
- **How** to check it (commands, agent prompts)
- **Pass criteria** — what "green" looks like
- **Escalation** — what to do if a check fails

The audits are designed so a future contributor (or future Jonathan)
can run them without remembering the back-story.

---

## 1. Pre-release audit — every DMG, every time (~2 h)

Runs immediately before `./Scripts/notarize.sh` + `./Scripts/make-dmg.sh`.

| # | Check | How | Pass |
|---|---|---|---|
| 1.1 | All tests green | `swift test 2>&1 \| tail -3` | "0 failures" line |
| 1.2 | Daemon-XPC clean (no password prompt) | `./.build/.../AnchorHelperPoke arm; tail /tmp/vakter-privileged.err.log` | Log shows `accepted connection from validated peer` + `pmset disablesleep 1 — OK` |
| 1.3 | Defenses checklist produces 20 items | `python3 -c "import json; print(len(json.load(open('~/Library/Application Support/Vakter/defenses-checklist.json'))['items']))"` | ≥ 20 |
| 1.4 | Helper has `NSLocationUsageDescription` | `plutil -extract NSLocationUsageDescription raw Sources/AnchorHelper/Resources/Info.plist` | Non-empty |
| 1.5 | App has `LSApplicationCategoryType` + `NSHumanReadableCopyright` | `plutil -p Sources/AnchorApp/Resources/Info.plist \| grep -E "LSApplicationCategoryType\|HumanReadable"` | Both present |
| 1.6 | Version in all 3 Info.plists matches | `grep -A1 "CFBundleShortVersionString" Sources/AnchorApp/Resources/Info.plist Sources/AnchorHelper/Resources/Info.plist Sources/AnchorPrivilegedDaemon/Resources/Info.plist` | All identical |
| 1.7 | Notarisation acceptance | `xcrun notarytool history --keychain-profile anchor-notarytool \| head -10` | Latest `Accepted` |
| 1.8 | DMG stapled + spctl clean | `xcrun stapler validate build/Vakter.dmg && spctl --assess --type open build/Vakter.dmg` | Both pass |
| 1.9 | All three Mach-Os in the bundle stapled | `xcrun stapler validate /Applications/Vakter.app/Contents/MacOS/{Vakter,VakterHelper,VakterPrivilegedDaemon}` | All "validate action worked" |

**Escalation**: any FAIL blocks the release. Re-build → re-sign →
re-notarize. Do not ship without a clean 9-of-9.

---

## 2. Quarterly security audit (~half day, every 3 months)

Run on the **last Friday of each quarter**.

| # | Check | How | Pass |
|---|---|---|---|
| 2.1 | All probes still work on current macOS | `./.build/.../AnchorHelperPoke arm` on a fresh macOS install | No new `REFUSING connection` lines |
| 2.2 | Daemon's `SMAuthorizedClients` still matches build-script Team-ID substitution | `strings /Applications/Vakter.app/Contents/MacOS/VakterPrivilegedDaemon \| grep -A1 SMAuthorizedClients` | Active team OU substituted |
| 2.3 | Audit-token PID-path validation still accepts our helper | `tail /tmp/vakter-privileged.err.log` after arm | `accepted connection from validated peer` |
| 2.4 | No new TCC prompts on launch | Install on a fresh macOS VM | Only the 3 expected prompts (Camera, Bluetooth, Login Items) |
| 2.5 | `xcrun altool` API version unchanged | `xcrun notarytool --version` | Matches Apple's current support window |
| 2.6 | All Apple framework deprecations addressed | `swift build 2>&1 \| grep deprecat` | 0 |

**Escalation**: file an issue per failure with severity tag. Critical
(2.1, 2.3) blocks the next release; others triage normally.

---

## 3. Quarterly UX audit (~half day, every 3 months)

The screenshot-based one. Should be run on **both light and dark mode**
on a Mac with the standard notch profile.

Procedure:

1. Wipe `~/Library/Application Support/Vakter/` so you experience
   first-launch state.
2. Install the latest DMG via the standard drag-to-Applications flow.
3. Walk every flow below, screenshot each surface, note frictions.

| # | Surface | What to look for |
|---|---|---|
| 3.1 | DMG layout | Two icons + readme. Drag-to-Applications obvious. No quarantine prompt. |
| 3.2 | First launch — Welcome step | Lighthouse mark visible, copy reads cleanly, wordmark + eyebrow + tagline all aligned |
| 3.3 | First launch — Permissions step | Cards render in correct order, status pills accurate, "Open Privacy & Security" / "Open Login Items" buttons open the right pane |
| 3.4 | First launch — Hotkey step | Default `⌃⌥⌘L` shown big & beautiful, KeyRecorder lets you rebind, no colliding combo accepted (try `⌘L` — should be rejected) |
| 3.5 | First launch — Hear-alarm step | Big speaker circle, waveform pulses, sound plays at full volume on internal speakers, restores prior volume on stop |
| 3.6 | First launch — Done step | Pills accurate, dismisses cleanly |
| 3.7 | Menubar icon — light mode | Lighthouse visible on white menubar, lantern dot lights amber when armed |
| 3.8 | Menubar icon — **dark mode** | Lighthouse still visible (uses `AnchorDesign.anchorAdaptive`, not the fixed navy `.anchor`) |
| 3.9 | Menubar dropdown | All 10 items render, "Run Checks ⌘R" shortcut works, "Show captured photos" opens the right folder |
| 3.10 | Defenses submenu — each of 5 categories | Submenu icon tinted by worst-status (green/amber/red), rows hover-able, click on a failing row opens the right Settings pane |
| 3.11 | Settings → each of 10 tabs | All render, all controls functional, no SwiftUI runtime warnings in console |
| 3.12 | Settings → Sound → Preview button | Plays selected siren for 3 seconds, button label changes during playback |
| 3.13 | Settings → Notifications → Send test | Triggers Automation TCC consent dialog (first time only), test iMessage arrives on phone |
| 3.14 | Settings → Privacy → cycle 3 appearances | Menubar visually changes (lighthouse / battery / hidden) |
| 3.15 | Arming overlay | Fades in 0.18s, holds 0.24s, fades out 0.18s, "On watch" caption in italic serif, lantern beam visible |
| 3.16 | Event Log — empty state | Friendly placeholder, no JSON visible |
| 3.17 | Event Log — populated state | Photos render as 60×60 thumbnails, click opens Preview, transition strings are HUMAN ("Alarm fired", not "armed → grace") |

**Escalation**: each friction gets a row in BACKLOG.md with a severity
tag. Critical = ship-blocker for the next release.

---

## 4. Accessibility audit (~half day, every 6 months)

| # | Check | How | Pass |
|---|---|---|---|
| 4.1 | VoiceOver labels on every interactive element | Cmd-F5 (VoiceOver), tab through Settings + Onboarding | Every focusable element announces meaningfully |
| 4.2 | Dynamic Type respected | System Settings → Display → Larger Text. Reopen Vakter. | No truncation, no overflow |
| 4.3 | Reduced Motion respected | System Settings → Accessibility → Display → Reduce Motion | Arming overlay + menubar shield breath are subdued |
| 4.4 | Contrast ratios | Use macOS's "Show contrast" tool on every brand-coloured element | All ≥ 4.5:1 against their background |
| 4.5 | Keyboard-only navigation | Tab through every screen with no trackpad | All flows completable |

**Escalation**: A11y issues block submission to Apple-curated stores
but not direct sale. Triage individually.

---

## 5. Annual external security audit (1-2 days, every 12 months)

Open the daemon source + signing flow to an independent reviewer.
Pay them. Don't argue with the findings.

Scope:

- `Sources/AnchorPrivilegedDaemon/ListenerDelegate.swift` — peer code requirement
- `Sources/AnchorPrivilegedExec/AnchorPrivilegedExec.c` — fallback admin auth
- `Sources/AnchorHelper/SleepDisabler.swift` — XPC handshake
- `Scripts/build-app.sh` — Team-ID templating, secret-handling
- `Scripts/sign.sh` — entitlements + identity flow
- `Sources/AnchorShared/EvidenceDelivery.swift` — iMessage script escaping

Report goes into `SECURITY_AUDIT_YYYY.md`. Re-audit after any major
release that changes XPC, signing, or evidence-delivery paths.

---

## 6. Cadence summary

| Audit | When | Effort |
|---|---|---|
| 1. Pre-release | Every DMG | ~2 h |
| 2. Security | Quarterly | ~½ day |
| 3. UX | Quarterly | ~½ day |
| 4. Accessibility | Bi-annually | ~½ day |
| 5. External security | Yearly | 1–2 days |

Total annual audit budget: ~5 person-days for an indie team of one,
~3 person-days if a contractor handles audit 5.

If you can't make these happen on time, you've outgrown an indie audit
cadence and need a part-time QA contractor — at which point the
quarterly audits should become monthly.
