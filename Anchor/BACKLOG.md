# Vakter — Backlog

Everything not in this release but needed for full polish. Pulled from
the v1.0.0 MacPaw audit, the Jonathan user-feedback report, and the
designer UI critique.

Order = roughly priority × impact ÷ effort.

---

## Currently in flight (strategist-commissioned)

| Epic | Features | Memo | Status |
|---|---|---|---|
| [#9 Deploy vakter.app — pre-flight, host config, 30-min runbook](https://github.com/jonathangebru/vakter/issues/9) | [#10](https://github.com/jonathangebru/vakter/issues/10) [#11](https://github.com/jonathangebru/vakter/issues/11) [#12](https://github.com/jonathangebru/vakter/issues/12) [#13](https://github.com/jonathangebru/vakter/issues/13) [#14](https://github.com/jonathangebru/vakter/issues/14) [#15](https://github.com/jonathangebru/vakter/issues/15) [#16](https://github.com/jonathangebru/vakter/issues/16) | `.claude/strategy/2026-05-21-deploy-vakter-app-the-launch-linchpin.md` | Done — runbook complete; awaiting human deploy step |
| [#18 Epic A: v1.4.2 — Pre-launch reality check](https://github.com/jonathangebru/vakter/issues/18) | [#20](https://github.com/jonathangebru/vakter/issues/20) [#21](https://github.com/jonathangebru/vakter/issues/21) [#22](https://github.com/jonathangebru/vakter/issues/22) [#23](https://github.com/jonathangebru/vakter/issues/23) [#24](https://github.com/jonathangebru/vakter/issues/24) [#25](https://github.com/jonathangebru/vakter/issues/25) [#26](https://github.com/jonathangebru/vakter/issues/26) [#27](https://github.com/jonathangebru/vakter/issues/27) [#28](https://github.com/jonathangebru/vakter/issues/28) [#29](https://github.com/jonathangebru/vakter/issues/29) | `.claude/strategy/2026-05-21-feature-audit-and-roadmap.md` | In Progress — 10 features Ready to dispatch |
| [#19 Epic B: v1.5 — Calm follow-up](https://github.com/jonathangebru/vakter/issues/19) | [#30](https://github.com/jonathangebru/vakter/issues/30) [#31](https://github.com/jonathangebru/vakter/issues/31) [#32](https://github.com/jonathangebru/vakter/issues/32) [#33](https://github.com/jonathangebru/vakter/issues/33) [#34](https://github.com/jonathangebru/vakter/issues/34) [#35](https://github.com/jonathangebru/vakter/issues/35) [#36](https://github.com/jonathangebru/vakter/issues/36) [#37](https://github.com/jonathangebru/vakter/issues/37) [#38](https://github.com/jonathangebru/vakter/issues/38) | same memo | Backlog — dispatch-blocked until Epic #18 ships + post-launch retro filed |

Sequencing note: Epic A blocks launch. Begin in parallel with the
human-side deployment of #9. The five-day fix list inside Epic A
clears the credibility, polish, and one-cinematic-moment problems
identified in the feature-audit memo.

---

## What's already shipping (per the 2026-05-21 feature audit)

`STRATEGY.md §1` lists v1.2 state. **The code has moved well past that.**
Audit-confirmed (see `.claude/strategy/2026-05-21-feature-audit-and-roadmap.md`):

- 10s ambient audio capture on alarm (was "v1.3 deliverable")
- Tamper-evident SHA-256 Merkle event chain (was "v1.3 deliverable")
- Police-ready PDF export (was "v1.3 deliverable")
- Email evidence delivery as a multi-channel fallback (was "v1.5 deferred")
- User-owned cloud-evidence backup, B2 or presigned-URL (was "v1.4 deferred")
- CloudKit publisher + iOS + Apple Watch companion source (was "v1.4 epic")
- Auto-arm engine with 4 trigger types (was "v1.5 deferred")
- Find My token clearing + Apple ID change watchers (uncredited in §1)
- System-wake belt-and-braces alarm fallback (uncredited in §1)
- macOS-native crash report harvest (no PLCrashReporter needed)
- XPC peer code-sig verification under Team ID 9TA5GB5UJH

**Known shipping gaps** (close in Epic A pre-launch):
- README claims 20 defenses checks; actual is 12 — fix the count OR ship 8 more checks
- Bluetooth "trusted-device disarm" claim in README is misleading — trust is informational only
- Sparkle integration documented in SPARKLE_SETUP.md but not wired
- `Sources/VakterApp/VakterIntents.swift:19-26` has a `TODO(week-3)` for actually wiring intents to the helper — surface exists, doesn't act
- `Sources/VakterHelper/XPCService.swift:127` returns empty stub for defenses checklist
- Settings ships 11 tabs, BACKLOG #6 calls for ≤6

---

## Pre-MacPaw-submission (1-2 weeks)

These should land before the first paid release on MacPaw / Setapp.
Direct DMG sale on your own site can ship without them.

| # | Item | Effort | Source |
|---|---|---|---|
| **1** | **Sparkle integration** for in-app auto-updates. Required for direct-sale; Setapp manages its own. Build appcast.xml, sign the appcast feed, host it. | 1 day | MacPaw audit |
| **2** | **Marketing assets** — 6 screenshots (menubar, dropdown, Settings → Modes / Sound / Defenses / Notifications, About), 30-sec App Preview video (consider Veed / Final Cut), App Store-format description (75-char subtitle, 4000-char long, 100-char keywords) | 1 day | MacPaw audit |
| **3** | **Sandbox justification document** for the Setapp reviewer. One-pager explaining why Vakter can't sandbox (root daemon needed for `pmset disablesleep`, `nvram` reads, system-volume override), why each entitlement is minimal, and what the daemon CAN'T do (no network, no file IO outside its own working dir, etc). | 2-3 h | MacPaw audit |
| **4** | **Support contact infrastructure** — `support@vakter.app` mailbox (or a forwarder), a landing page at `vakter.app` with the privacy policy + EULA links + a release-notes feed, a contact form | 1 day | MacPaw audit |
| **5** | **Crash reporting** — wire PLCrashReporter or Sentry-self-hosted into the menubar app + helper. Daemon is small enough not to need it. Use anonymous-only IDs (no PII). | 1 day | MacPaw audit |

---

## UX polish (1 week, parallel)

| # | Item | Effort | Source |
|---|---|---|---|
| **6** | **Settings tab consolidation 10 → 6** — fold Sound under Modes, merge Notifications + Privacy, surface Defenses at top, hide Event Log behind a separate menubar entry | 4 h | UI review |
| **7** | **Humanise the menubar dropdown header** — currently "Vakter — armed (mode: cafe)" parses like log output. Try "On watch — Cafe mode" | 30 min | UI review |
| **8** | **PDF export of the Event Log** — for the "show police what happened" use case. Use `NSPrintOperation` with a SwiftUI-rendered view. | 2-3 h | Jonathan + UI |
| **9** | **Menubar status tooltip** — hover the lighthouse, get "Vakter is armed. Cafe mode. Last alarm: never." in a tooltip. One-line addition. | 1 h | Jonathan |
| **10** | **Re-use the existing `LighthouseHeroMark` icon** in the menubar status item for very-high-DPI displays. Right now it's the simplified menubar variant; on 6K displays it can afford more detail. | 2 h | UI review |
| **11** | **Fix arming-overlay's italic-serif inconsistency** — only place in the app that uses a serif. Either commit (and add a serif token to DesignSystem.swift) or use SF Rounded to match the wordmark. | 30 min | UI review |
| **12** | **Defenses dropdown color tokens** — currently mixes `NSColor.system{Green,Orange,Red}` with `AnchorDesign.{healthy,alarm}` elsewhere. Unify. | 1 h | UI review |

---

## Accessibility (2-3 days)

| # | Item | Effort |
|---|---|---|
| **13** | **VoiceOver labels** on every `Image(systemName:)` and `Button { } label: { Image(...) }`. Audit ~30 sites. | 3-4 h |
| **14** | **Dynamic Type** — verify all text uses semantic Font roles so it scales | 2 h |
| **15** | **Reduce-Motion** support — gate the arming-overlay animation + breathing menubar shield behind `@Environment(\.accessibilityReduceMotion)` | 1 h |
| **16** | **Contrast pass** — verify every brand-coloured text-on-background combo meets WCAG AA (4.5:1) | 2 h |

---

## Internal cleanup (won't affect users but unblocks contributors)

| # | Item | Effort | Source |
|---|---|---|---|
| **17** | **Internal Anchor → Vakter rename** for SOURCE-level cleanliness: `AnchorMode → VakterMode`, `AnchorState → VakterState`, etc. Currently 31 occurrences across 10 files. Pure mechanical, no user-visible change. Schedule when there's a clean week with no shipping. | 4-6 h | Jonathan |
| **18** | **Repo directory rename** — `/Anchor/` → `/Vakter/`. Costs `git mv` + every `import` path + every cd in scripts. ~2 h. Defer until 1.1+ when build infra is stable. | 2 h | n/a |
| **19** | **Consolidate `runProcess` shells** — `Shell.run` already exists but `DefensesAudit.swift` (in AnchorApp) still has its own inline Process(). | 1 h | Code review |
| **20** | **Delete `AnchorPrivilegedExec.c` fallback** once we're confident the SMAppService daemon path is reliable for every user. Right now it's the safety net when the daemon path fails. | 0 (defer) | Code review |

---

## Distribution channel work (1 week)

| # | Item | Effort |
|---|---|---|
| **21** | **MacPaw direct submission** — fill out their form, attach marketing assets, await review (~2 weeks Apple turn-around). | ½ day + wait |
| **22** | **Setapp application** — separate form, requires the sandbox justification doc (#3), screenshots (#2), and a working trial-mode build (Setapp does its own activation gate). | 1 day + wait |
| **23** | **Mac App Store evaluation** — likely NOT compatible because we need an unsandboxed daemon. Document the decision so contributors don't re-explore. | ½ day | |

---

## Features that came up across the audits

| # | Feature | Effort | Source |
|---|---|---|---|
| **24** | **iCloud-synced trusted-device list** across the user's own Macs. CKShare + a CKRecord per peer. Setapp-grade nice-to-have. | 2-3 days | Jonathan |
| **25** | **Apple Watch unlock** as a disarm method. Pair with the existing Bluetooth trusted-peer machinery; the Watch is always paired. | 1 day | Jonathan |
| **26** | **Smarter cafe mode** that adapts grace based on Wi-Fi SSID (home → longer, public coffee shop → shorter) | 1 day | Plan |
| **27** | **Find My token watch frequency** — currently 30s. Could drop to 5s during the first 60s after arm (high-suspicion window). | 30 min | Plan |
| **28** | **Per-trigger photo cadence** — alarm triggered by Find-My-cleared has different forensic value than lid-close. Different photo-burst rates. | 2 h | Plan |
| **29** | **Hardware key disarm** (YubiKey) — for the paranoid pro user segment. | 2-3 days | Plan |
| **30** | **Stealth-snitch mode** — alarm fires silently, only iMessage. No audible siren. For users worried about embarrassment in public. | 1 day | Plan |

---

## Cut for now (might revisit)

- **Mac App Store version** — fundamentally incompatible with unsandboxed daemon. Setapp is the closest substitute.
- **iOS companion app** — interesting (push notification on alarm, remote arm/disarm) but a whole new project. Year-two.
- **Windows / Linux** — Vakter is Mac-first by design (the alarm uses Mac-specific signals like lid-close, Touch ID, IOPMSleep). Don't dilute.
- **Subscription pricing** — Jonathan flagged the README/MacPaw price mismatch ($19 one-time vs $30/yr). Decision: $29 one-time, plus Setapp subscription tier. Updated in README. Stop calling it $19.

---

## How to use this file

- When something gets done, **move it to CHANGELOG.md** (TBD), don't
  delete it.
- When a new audit (per `AUDIT_PLAN.md`) surfaces an item, add it here
  with the audit number it came from.
- Treat the "Pre-MacPaw-submission" section as the launch milestone.
  Everything in it = launch blocker.
