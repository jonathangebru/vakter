# Feature roadmap — pre-launch reality check + post-launch v1.5 plan

**Strategy memo:** .claude/strategy/2026-05-21-feature-audit-and-roadmap.md
**Priority:** Epic A = p1; Epic B = p2
**Estimated complexity:** Epic A = medium (7-9 calendar days); Epic B = large (4-6 weeks post-launch)

---

## Background for PO

A feature audit (linked memo) verified what Vakter v1.4.1 actually ships against the README's competitor table and the STRATEGY doc's claims. Findings:

- We ship **~58 distinct user-facing features**. STRATEGY.md §1 still describes v1.2-era state — it's stale. Big chunks of "v1.3/v1.4/v1.5 deferred" items in STRATEGY §10 are *already implemented*.
- README's "20 defenses checks" claim is **false** (we ship 12). The "Bluetooth proximity disarm" row is **misleading** (it's informational only, never causes disarm).
- The README **undersells** what we have by ~40% — hash chain, PDF export, audio capture, cloud backup, email delivery, 9 sirens, auto-arm engine, Find My + Apple ID watchers all uncredited.
- Competitive landscape: Vakter beats every direct competitor on feature surface. The consumer middle is empty (Apple Find My / enterprise Prey / dead indies / 1 living solo at $9.99/yr).
- **Pre-launch GO recommendation** — v1.4.1 ships as launch product with a ~5-day fix list.

Two epics follow. **Epic A is the launch-blocking fix list. Epic B is the post-launch v1.5 plan.**

---

# EPIC A — Pre-launch reality check + 5-day fix list

## Epic title for the board

`v1.4.2 — Pre-launch reality check (truth, polish, the missing UX moment)`

## Goal

By the end of this epic, the README, the website, and the product all tell the **same true story**. v1.4.2 ships with one cinematic moment the demo video can use (stealth lock-screen overlay), Sparkle wired for auto-update, Settings consolidated to 6 tabs, and the Defenses checklist backing its README count.

## Acceptance criteria (epic-level)

- README + website + STRATEGY.md feature claims all reconcile against shipping code (verified by spot-check).
- Defenses checklist ships ≥18 checks (we have 12 + add 8 = 20, but ≥18 backs "around 20" honestly).
- Sparkle 2 wired; signed appcast.xml hosted at vakter.app; app prompts for an update when a newer build is pushed to the appcast.
- Settings tab count = 6 (down from 11).
- Stealth lock-screen overlay renders during `.alarm` state with user-configurable "if found" text. Disappears on disarm.
- `ArmVakterIntent.perform()` actually calls helper.arm() over XPC (no more TODO at line 19-26).
- Onboarding step 4 ("hearAlarm") plays the actual user-selected siren + voice cue, with mic+camera permission prompts surfaced.
- `XPCService.swift:127` no longer returns an empty stub for defenses-checklist-over-XPC.
- iOS + Watch companion apps are submitted to Apple for provisioning (TestFlight pending). Build is expected to be in TestFlight by launch week or 1 week after; not a blocker if Apple is slow.

## Suggested Features for PO to file

1. **README + website honesty pass** [agent:vakter-brand-keeper] — Update README.md comparison table + Website/index.html feature blocks to reflect actual shipping features. Add hash chain, PDF export, audio capture, cloud backup, email delivery, 9 sirens, voice cue, auto-arm engine, Find My + Apple ID watchers. Correct "20 → 12" defenses count (or reflect new count if Feature 2 ships). Soften "Bluetooth proximity disarm" row to "Bluetooth-trusted-device awareness" until Feature 9 ships. Update Anchor/STRATEGY.md §1 to reflect v1.4.1 reality.

2. **Defenses audit: ship 8 additional checks** [agent:vakter-mac-engineer] — Add to `DefensesAudit.swift`: AirDrop discovery scope, AirPlay receiver, File sharing off, Media sharing off, Printer sharing off, Remote Login (SSH) off, Remote Management (ARD) off, Boot security level (Full Security on Apple Silicon). Each check follows the existing pattern (shell-out + status mapping). Categorise into the existing 5 buckets. Update `DefenseChecklist.swift` if new categories are needed.

3. **Wire Sparkle 2 for in-app auto-update** [agent:vakter-mac-engineer] — Follow `SPARKLE_SETUP.md`. Add SwiftPM dep, generate EdDSA key, wire `SPUStandardUpdaterController` into AppDelegate, add Settings → General "Check for updates" toggle. Coordinate with brand-keeper on hosting appcast.xml at vakter.app/appcast.xml (depends on #9 deploy epic being live).

4. **Settings tab consolidation 11→6** [agent:vakter-mac-engineer] — Merge: Shortcut + Sound under General; Notifications + Privacy + Auto-arm & Cloud under one "Alerts & Cloud" tab; Event Log + About stay but Event Log might surface as a menubar entry instead. Target final 6: General (incl. Shortcut, Sound), Modes, Trusted Devices, Defenses, Alerts & Cloud (incl. Notifications, Privacy, Auto-arm), Event Log. About moves to a window opened from menubar. Verify all KeyRecorder + AlarmSound + auto-arm flows still work after consolidation.

5. **Stealth lock-screen takeover ("STOLEN — call X")** [agent:vakter-mac-engineer] — On `.alarm` state, render a fullscreen `NSWindow` at `.screenSaver` level with user-configured "if found, please contact" text + a callback number. Survives the immediate screen lock kick-off. Dismisses on disarm. Adds a Settings card under General with the configurable text. Test that it doesn't fire during `.grace` (only `.alarm`).

6. **Wire ArmVakterIntent + SetVakterModeIntent to actually call the helper** [agent:vakter-mac-engineer] — Close the existing `TODO(week-3)` in `Sources/VakterApp/VakterIntents.swift:19-26` and the equivalent in `SetVakterModeIntent.perform()`. Both intents should dispatch through `HelperClient` (XPC) and await reply. Test with a Shortcut "When Café focus activates, arm Vakter."

7. **Onboarding hearAlarm step + permission prompts** [agent:vakter-mac-engineer] — Verify `Onboarding.swift`'s `hearAlarm` step plays the user-selected siren + voice cue (currently might play default classicSiren). Trigger camera + microphone permission prompts during this step so they're granted before any real alarm. Show small confirm-permission tiles. release-warden runs through onboarding on a clean install to verify all permissions land cleanly.

8. **Defenses checklist over XPC** [agent:vakter-mac-engineer] — Close the TODO at `Sources/VakterHelper/XPCService.swift:127`. Replace the empty-stub return with a real call to `DefensesProbe.snapshot()` (which already exists in VakterShared and runs in the helper). Surface in the menubar dropdown's Defenses submenu via XPC; today only the in-app Defenses tab works.

9. **iOS + Watch companion provisioning + TestFlight submission** [agent:vakter-mac-engineer + needs-human] — Follow `iOS/SETUP.md`. Create CloudKit container in Apple Developer Portal (`iCloud.app.vakter.companion`), provision iOS + Watch app IDs, generate provisioning profiles, set up TestFlight build. **needs-human**: developer-portal logins, App Store Connect setup, TestFlight internal-tester invitation list. If Apple review is slow, ship without and pre-announce "iOS companion in beta — GA within 4 weeks of launch."

10. **In-app launch demo video** [agent:vakter-brand-keeper] — Refresh the 60-second demo video (BACKLOG #2) to feature the new stealth lock-screen overlay from Feature 5. Bundle into the app at Help → "See it in action" (in-app player, no internet). Update Website/index.html hero with new cut.

## Anti-scope

- Do NOT file payment processor / Stripe / Paddle work as part of this epic — separate decision, needs-human.
- Do NOT file Setapp / MacPaw submission timing — sequence after the v1.4.2 build is signed and notarised.
- Do NOT include the v1.5 features (Calm Cafe presence-aware grace, auto-fix buttons, weekly digest, Stealth-snitch mode, Custom mode, hash-chain verifier, insurance PDF variants) — those are Epic B.
- Do NOT redesign the website. Reality-check + asset refresh only.
- Do NOT touch the Privacy or Security pages — they're new and clean. They get a small accuracy refresh if Defenses checks count changes.

## Reading priority for PO

- `Anchor/.claude/strategy/2026-05-21-feature-audit-and-roadmap.md` — the memo this directive is filing
- `Anchor/STRATEGY.md` — current north star (§1 is stale; §10 has the v1.3-v1.5 list this work delivers against)
- `Anchor/BACKLOG.md` — items #1 (Sparkle), #2 (marketing assets), #6 (Settings consolidation) overlap with features above
- `Anchor/SECURITY.md` — touched indirectly by Sparkle setup (the appcast claim)
- `Anchor/README.md` — the table that has wrong/missing claims
- `Anchor/SPARKLE_SETUP.md` — the runbook for Sparkle wiring
- `Anchor/iOS/SETUP.md` — the iOS provisioning runbook
- `Anchor/Sources/VakterApp/DefensesAudit.swift` — pattern for adding checks
- `Anchor/Sources/VakterApp/VakterIntents.swift:19-26` — the existing TODO
- `Anchor/Sources/VakterHelper/XPCService.swift:127` — the existing TODO

---

# EPIC B — Post-launch v1.5 plan (consolidate, don't dispatch yet)

## Epic title for the board

`v1.5 — Calm follow-up (presence-aware grace, auto-fix, weekly digest, custom mode)`

## Goal

File this epic on the board so the v1.5 work is visible, but **do not dispatch any features inside it until v1.4.2 has shipped and the first post-launch retro is filed.** This epic is a placeholder + consolidated plan, not active work.

## Acceptance criteria (epic-level)

This epic is closed when v1.5 ships with the 9 features below in some form. Sequencing inside v1.5 will be re-decided after launch data is in.

## Suggested Features for PO to file (placeholder — NOT to dispatch)

1. **"Calm Cafe" presence-aware grace extension** [agent:vakter-mac-engineer] — Wire the dormant BT-trust signal as a grace softener (cafe + library modes only, opt-in). Multiplies graceSeconds by 1.5x when a trusted phone is in range.

2. **Defenses checklist auto-fix buttons** [agent:vakter-mac-engineer] — For checks where macOS supports programmatic toggle (Firewall on, Stealth on, Login Items toggle), add a "Fix" button alongside "Fix in Settings →". Pareto-style.

3. **Defenses audit weekly digest notification** [agent:vakter-mac-engineer] — Every Monday morning at user-set time, post a macOS notification: "Defenses score: 87 (down 5). 2 to fix." UNUserNotificationCenter + once-a-week timer. User can disable.

4. **Stealth-snitch silent-alarm mode** [agent:vakter-mac-engineer] — Global toggle: alarm fires silently (no siren, no voice), all evidence captured + delivered. For privacy-conscious users / public-embarrassment-averse. Orthogonal to Cafe mode.

5. **Custom mode (sixth VakterMode)** [agent:vakter-mac-engineer] — Adds `VakterMode.custom`. User picks grace seconds, audible bool, photo cadence, alarm cap, default sound. Settings UI block in ModesTab.

6. **Insurance-ready PDF report variants (US/EU/UK)** [agent:vakter-mac-engineer] — Region-aware PDF templates in EvidenceReport.swift. Gated on insurance-industry insider review of the templates first.

7. **Tamper-evident hash chain online verifier (vakter.app/verify)** [agent:vakter-brand-keeper] — Browser-side JS + WebCrypto API. Paste a PDF, see chain verification result with SHA-256 chain visualisation. No upload. Show-HN-able artifact for a second wave.

8. **Audible "test it now" buyer demo flow** [agent:vakter-mac-engineer + agent:vakter-brand-keeper] — A 30-second "demo me a full incident" menubar item, separate from Run Arm Demo. Full lifecycle with voiceover/captions. brand-keeper writes narration; mac-engineer wires the choreography.

9. **Wi-Fi-adaptive Cafe grace** [agent:vakter-mac-engineer] — When Cafe mode + connected to a "trusted network" SSID (Home, Office), use Library-mode grace. On unrecognised SSID, use strict Cafe params. BACKLOG #26.

## Anti-scope

- This epic does NOT dispatch any features. It's a planning artefact.
- Do NOT file the v2.0+ items (YubiKey disarm, QR found-me page, video-call detection, web dashboard) as part of v1.5. Those are a separate 2.0 epic to be filed after v1.5 retro.

## Reading priority for PO

- `.claude/strategy/2026-05-21-feature-audit-and-roadmap.md` — §8 v1.5 plan
- `BACKLOG.md` — items #25-#30 overlap with v1.5
- v1.4.2's launch data (whatever exists at launch + 2 weeks) will inform v1.5 sequencing
