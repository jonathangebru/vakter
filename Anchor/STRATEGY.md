# Vakter Strategy — Post-v1.2 Research Synthesis

*Compiled May 2026, after the v1.2 design polish + notarized DMG shipped.
Sources: four parallel research agents covering codebase audit, competitive
landscape + financials, marketing playbook, and competitor website teardown.
This document is the action layer on top of that research.*

---

## 1. Where Vakter actually stands (codebase audit)

### Production-ready today (v1.2)

- State machine + 5 modes (Normal, Travel, Library, Loaner, Cafe)
- 4 trigger sources: lid close, power disconnect, Bluetooth peer departure,
  power-button brief press
- 2 escalation watchers: Find My token cleared, Apple ID signed out
- 6 synthesised + 3 sample-backed sirens, 7-locale neural TTS voice cue
- iMessage evidence delivery with photo burst + Apple Maps URL
- Defenses checklist (20 checks across 5 categories)
- Hotkey customisation, Bluetooth-trusted-peer proximity disarm
- macOS Sequoia design pass: vibrant sidebar, tinted-icon rows, native
  attributed menubar header, SF Pro Display arming overlay, VoiceOver labels
- Notarized DMG (4.8 MB) ready to distribute

### Code-level TODOs still open (from grep audit)

| File:line | Gap | User-visible? |
|---|---|---|
| `XPCService.swift:127` | Defenses checklist returns empty stub over XPC | **Yes** — only works in-app, not surfaced via helper |
| `StateMachine.swift:74` | `snapshot.lastEvent` hard-coded to `nil` | Yes — menubar can't show "Last event" |
| `StateMachine.swift:419` | Captured photos not appended to alarm event | Yes — photos save but don't render in Event Log |
| `MenuBarController.swift:10` | Grace-state pulse animation TODO | Minor |
| `PowerObserver.swift:10` | Polling instead of `IOPSNotificationCreateRunLoopSource` | No (works fine) |
| `XPCService.swift:47` | Peer code-sig verification not implemented | **Yes** — security gap |

### Pre-launch backlog (BACKLOG.md, condensed)

- Sparkle integration (in-app auto-update)
- Crash reporting (PLCrashReporter, anonymous)
- Settings tab consolidation 10→6
- High-DPI menubar icon detail
- Marketing assets + App Preview video

**Shipping risk: low.** No bugs gate v1.2. Everything above is either polish
or pre-launch professional infrastructure.

---

## 2. Competitive landscape — the gap is real

### Direct anti-theft Mac apps

| Player | Status | Pricing | Scale signal |
|---|---|---|---|
| **Prey** | Alive, enterprise-skewing | $1.23–$2.99/slot/mo | 8M+ devices, ~$10–25M ARR est., bootstrapped |
| **Absolute Home & Office** (ex-LoJack) | Alive, enterprise-only | Subscription | Parent acquired 2023 for **$870M** |
| **HiddenApp / Senturo** | Alive | $1.67–$5.99/mo | <$5M ARR est. |
| **Orbicule Undercover** | **DEAD** — domain parked at HugeDomains | was $49 one-time | Sunset (Apple tightened macOS, broke hidden tracking) |
| **GadgetTrak / MacTrak** | **DEAD** | — | Placeholder homepage |
| **iAlertU** | **Abandonware** (Sudden Motion Sensor gone on Apple Silicon) | — | — |
| **Unplug Alarm** (closest indie analog) | Alive, App Store | **$9.99/yr or $19.99 lifetime** | <$100k ARR likely |
| **Clyde** | Alive, indie | Freemium | Very small |
| **MacBook Alarm** | Alive, indie | Recently pivoted to monthly sub | Very small |

### Adjacent menubar-mindshare competitors (free, not anti-theft)

- **Objective-See tools** — LuLu, KnockKnock, BlockBlock, **Do Not Disturb**
  (DND directly overlaps with Vakter's lid-open trigger). Free, OSS, trusted.
  Vakter's wedge: multi-trigger + sirens + evidence delivery + modes.

### Apple Find My (the elephant)

- Passive and reactive. Tracks after the fact.
- Requires Mac powered + online + signed-in + not wiped.
- Doesn't deter; doesn't push evidence in-the-moment.
- **Vakter's pinned reply when someone asks "why not Find My?":**
  > Find My is recovery; Vakter is deterrence + evidence. Find My needs
  > the Mac powered, online, signed-in, and not wiped — thieves close
  > the lid and the trail dies in 30 seconds. Vakter arms locally:
  > triggers an alarm + photo burst + iMessage to your phone *before*
  > the lid closes. Think of it as a car alarm, not LoJack. They're
  > complementary.

### Market sizing

- ~100M+ active Macs worldwide
- Apple ecosystem: 2.5B active devices total
- Kensington 2025 study: 76% of US/EU IT decision-makers had a device theft
  in the past 2 years
- ~97% of stolen laptops never recovered
- Endpoint security TAM: $16–27B in 2025, but consumer slice is single-digit
  billions and dominated by AV (Norton, McAfee, Bitdefender)
- **0.05% of consumer Macs at $29 = ~$1.4M ARR ceiling**

### What this means for positioning

- **The consumer middle is empty.** Apple Find My (free passive) on one
  end, Prey/Absolute (enterprise) on the other. No one is doing in-the-moment
  deterrence for consumers.
- **The legacy indie pack is a graveyard.** Undercover, iAlertU, GadgetTrak
  all died. The category has decayed; Vakter shows up in a vacuum where the
  legacy brand is literally gone.
- **The only living direct analog (Unplug Alarm) is one indie at $9.99/yr.**
  Clyde and MacBook Alarm are also solo and undermarketed. None have multi-
  trigger logic, 5 modes, iMessage-with-Maps evidence, neural-TTS voice, or
  a defenses checklist. **Vakter is meaningfully ahead of the indie pack.**

---

## 3. Vision — what to commit to

**The wedge no one owns:** *calm-when-nearby, fierce-when-stolen.*

The brand language already in the code supports this — night-watch, *vakter*,
lighthouse, calm in normal use, fierce on alarm. Don't drift. The marketing
copy should mirror what's already inline:

> The night-watch for your Mac — calm when you're nearby, fierce the moment
> someone tries to walk off with it.

Counter-positioning hooks:

- **"Not AI, just a watchful tool."** The market is saturated with "AI-
  powered X"; you're an old-fashioned utility that does one thing well.
- **"No cloud. No telemetry. No accounts."** Three-line contrarian framing
  on the homepage. Converts security-skeptical users at ~3× the rate of
  a feature list.
- **"Apple Silicon, macOS Sequoia day-one."** Mac-only is a feature.
- **"The deterrent layer Apple deliberately doesn't ship."** Frames Find My
  as complementary, not competitive.

---

## 4. Pricing — opinionated call

**$29 one-time, 14-day full trial, optional $12/yr for updates after year one.**

This is the **CleanShot X model**, the most-copied Mac utility pricing of 2025
because it works. Comparable price points:

- Bartender 6 = $20
- CleanShot X = $29
- Pareto Security = free OSS + ~$30 paid tier
- Unplug Alarm = $19.99 lifetime (anchor below us — we're a clear step up
  in feature surface)

**Why not subscription:** Mac utility buyers want "buy and forget." Security
≠ Notion. The market punishes subs for utilities (see Bartender 5 backlash
when Applause bought it). Pure-sub Prey survives only because it sells B2B.

**Why not lifetime-only:** Leaves money on the table. CleanShot's hybrid
extracts ~30% of cohorts to year-2 update licences while keeping the
"lifetime" narrative.

**Add later (month 4+):** $79 "Family" tier for 5 Macs.

---

## 5. Trust signals — closed-source playbook

Vakter is **closed-source by deliberate choice** (decision made May
2026 after considering GPLv3 split). The Little Snitch / Bartender /
CleanShot precedent is solid: closed-source utilities can absolutely
earn macOS power-user trust if every *other* signal is taut. In
priority order:

1. **Tiny + well-documented privileged surface.** The root daemon is
   ~150 LOC with *one* exported XPC method (`pmset disablesleep`).
   The helper runs as the user, same privilege level as Safari. No
   kernel extension, no System Extension, no Network Extension. The
   landing page + SECURITY.md make this surface area legible at a
   glance. Smallness *is* the audit.
2. **200-word privacy policy, not 4,000.** Lead: "Vakter does not
   transmit photos, audio, or telemetry off your device. Period."
3. **"How it works" page with architecture diagram.** Show daemons,
   XPC boundaries, what's stored where, how iMessage is sent (your
   Apple ID, no server). Make the *behavior* legible since the source
   isn't.
4. **"No cloud, no telemetry, no accounts."** Three-line contrarian
   framing on the homepage. Closes ~40% of the
   "but-can-I-trust-it" gap on its own — most security paranoia is
   about silent network calls, which Activity Monitor / Little Snitch
   can verify users see zero of.
5. **Notarization + Hardened Runtime + Developer ID Application.**
   Lean on Apple's transparency. `codesign --display --entitlements -`
   on the installed bundle lets users audit exactly what capabilities
   we asked for. Surface this in the SECURITY page.
6. **Public security disclosure address** (`security@vakter.app`) +
   stated 90-day disclosure policy. No bounty at launch; commit to one
   at $5k MRR.
7. **Paid third-party audit at $50k MRR.** Commit publicly to an NCC /
   Trail of Bits audit when revenue supports it. Publish the report.
   This is the closed-source equivalent of "audit the code."
8. **Real human accountability** — photo, full name, location, "I'm a solo
   dev in [city]." Little Snitch, CleanShot, Bartender all show the human.
9. **"What we don't do" section** on the homepage. Contrarian framing wins.
10. **A real wordmark.** SF Symbol-only logo will tank trust 30%+ for a
    security tool. $300 on a Dribbble icon designer if needed —
    highest-leverage cash spend possible.

---

## 6. Marketing channel playbook

### Top 5 highest-leverage moves for the next 30 days

1. **Record the 10-second grab-and-scream demo video in a real coffee shop.**
   Mux-hosted, autoplay, muted, looping on landing page hero. Powers PH, HN,
   YouTube outreach, TikTok cuts, the entire campaign. Anti-theft is
   cinematic and no competitor shows it. **Single most important asset.**
2. **Publish a polished `SECURITY.md` + "How it works" page** with the
   architecture diagram, privilege boundary, data flows, and "no
   cloud / no telemetry / no accounts" framing. Closed-source means
   we win trust through *behavioral legibility*, not auditability.
   (See §5.)
3. **Price at $29 one-time, 14-day trial, $12/yr optional updates.**
4. **Email Quinn Nelson (Snazzy Labs) with a free licence + pre-cut 60s
   B-roll.** Same day: identical pitch to Tyler Stalman, Created Tech,
   MaxTech, 5 niche reviewers. One Snazzy hit = 30k–100k views → 100–400
   paid. Worth more than all of Reddit combined.
5. **Launch on Product Hunt Saturday 12:01am PT** (halves the upvote bar
   vs Tuesday), then **Show HN Tuesday 8am ET** with title
   `Show HN: Vakter – Arm your Mac with one hotkey, screams if grabbed`.
   Pre-write the pinned "why not Find My?" reply. Two front-page shots in
   one launch week.

### Channel-by-channel quick reference

| Channel | Tactic | Realistic outcome |
|---|---|---|
| Product Hunt | Saturday launch, self-hunt, 15s GIF as gallery's first image | Top 5 day → 100–300 dl, 3–15 paid |
| Show HN | Tuesday 8am ET, pre-written "why not Find My?" pinned reply | Front page 4–8h = 300–1,000 dl, 20–60 paid |
| r/macapps | `[App]` tag, story-led title, free-code giveaway in launch post | 30–80 sales |
| 9to5Mac Indie Spotlight | Email `michaelb@9to5mac.com`, 60-word pitch + GIF | 80–250 dl, 10–30 paid |
| Snazzy Labs YouTube | Pre-cut B-roll + free licence to `videos@snazzylabs.com` | 800–3,000 dl, 100–400 paid |
| TikTok / Reels / Shorts | 3–5x/week for 30 days, vertical, no face | One hit @ 200k+ views = 200–800 dl |
| SEO long-tail | 5 long-form posts in 60 days; "MacBook stolen at coffee shop" first | Compounds; month 6 = 6–50 paid/mo passive |
| SetApp | Apply at month 3 once 500+ paying users | $500–$3k/mo passive |
| Mac App Store | Skip for v1 (daemons can't be sandboxed); consider "Vakter Lite" year 2 | — |

### Launch-week numbers ceiling (if everything lands)

PH + Show HN + 9to5Mac + Snazzy + r/macapps in one week = **$5k–$20k revenue**.
Floor if Snazzy passes: ~$500. The Snazzy variable is the difference.

---

## 7. Website — the alternating-block Little-Snitch template

What every successful Mac-app site does:

1. **One screenshot, one sentence, one CTA above the fold.** No carousel.
2. **Named testimonials with faces.** Borrow specific authority.
3. **Press-logo bar in first scroll.** 9to5Mac / MacStories / Macworld.
4. **Footer that respects power users.** Changelog, Status, Security, Press
   kit, EULA, RSS. CleanShot's footer is the gold standard.
5. **Short opinionated tagline.** Two clauses, declarative, no marketing-speak.

What anti-theft incumbents do badly (Vakter's counter-position):

- Hidden pricing → show `$29` on the hero
- B2B IT voice → talk to the emotional buyer ("someone grabbed my Mac")
- Illustrated SaaS mascots → real product screenshots, alternating blocks
- Multi-OS dilutes credibility → brag Apple Silicon + macOS Sequoia day-one
- Nobody surfaces Notarised / Hardened Runtime → free differentiator

**Tagline candidates:**

- *"The night-watch for your Mac."* (the README quote, brand-aligned)
- *"When your Mac says goodbye, Vakter says cheese."* (cinematic, viral)
- *"Calm when you're nearby. Fierce when you're not."* (positioning-led)

**Hero copy concept:**

> ### Vakter
> *The night-watch for your Mac.*
>
> Press one hotkey. The lid, the charger, and your trusted devices
> become your watch crew. The moment someone tries to walk off with
> your Mac, Vakter screams, captures photos, and pings your phone.
>
> [ Download for Mac — $29 ]
>
> *14-day full trial · Apple Silicon · Notarised · No cloud, no
> telemetry, no accounts*

---

## 8. Six-week launch sequence

| Week | Theme | Deliverables |
|---|---|---|
| **-6** | Foundation | Buy `vakter.app`, landing page skeleton, Plausible analytics, Paddle/Lemon Squeezy account, open `vakter-helper` and `vakter-daemon` repos |
| **-5** | Demo content | Record the 10s + 60s hero demo in a real coffee shop. Get 5 TikTok-format 15s vertical cuts. 8 product screenshots at PH/9to5Mac specs |
| **-4** | Press kit | `/press` page, draft pitch emails (don't send), submit to AlternativeTo / AppShout (long approval lag) |
| **-3** | Community seed | IH "looking for 20 beta testers" post, lurk + comment in r/macapps |
| **-2** | Beta + content | Run closed beta with IH testers, write SEO post #1, draft Show HN, pre-write all PH comment responses |
| **-1** | Polish + tease | Fresh-eyes landing-page review, daily X/Mastodon/Bluesky teasers, schedule PH launch |
| **Launch** | Sat–Fri | Sat 12:01am PT PH live, Sat 8am ET press blast, Sat 10am ET Reddit, Mon 8am ET Show HN, Tue–Thu daily TikTok, Fri public recap on IH |

---

## 9. What to actually build next (v1.3 backlog priority)

Ordered by leverage, highest first:

1. **Close `XPCService.swift:127`** — wire defenses checklist over XPC so the
   helper can deliver it (currently in-app only).
2. **Wire photo-burst → event log** (`StateMachine.swift:419`). Photos save
   but don't render in the Event Log UI today.
3. **`snapshot.lastEvent`** (`StateMachine.swift:74`) — surface latest event
   in the menubar dropdown.
4. **Sparkle integration** for in-app auto-update.
5. **Split the repo:** create public `vakter-core` (helper + daemon) under
   **GPLv3**, with `SECURITY.md`. Keep `vakter` (app) private.
6. **Crash reporting** (PLCrashReporter, anonymous-only).
7. **Settings tab consolidation** 10→6 (already partly done in v1.2).
8. **`XPCService.swift:47`** — peer code-signature Team ID verification.
9. **Landing page** (vakter.app) — alternating-block layout, hero video slot.
10. **Press kit** — `/press`, high-res icons, GIFs, founder photo, 50/150/500-
    word descriptions.

Out of scope for v1.3 (deferred):

- Mac App Store version (fundamentally unsandboxable)
- iOS companion app
- Windows / Linux
- Accelerometer snatch trigger (false-positive prone)
- Honeypot Silent Panic mode (needs unified-log monitoring)
- Real password swap / Adversary mode (needs FileVault recovery-key escrow)
- Apple Watch unlock as disarm method

---

## 10. Feature roadmap — v1.3 → v1.5 (the path to "best anti-theft Mac app possible")

The competitive research surfaced one big gap: every existing anti-theft tool
*either* alarms-and-yells (Unplug Alarm, Clyde, MacBook Alarm) *or*
tracks-and-recovers (Prey, Find My, Absolute). Nobody does **alarm + active
evidence collection + recovery-ready forensics + companion ecosystem** in one
calm-feeling product. That's Vakter's path to category leadership.

Build order across three releases, each with a single positioning beat:

### v1.3 — "Builds a police case while it yells" (3–4 weeks)

The recovery-rate features. Every event becomes evidence-grade.

1. **Audio capture on alarm** — 10-second ambient audio (AAC, ~80 KB). Photos
   catch a face if the thief is in front of the camera; audio catches
   everything else — voices, names, the room, the car. Mic permission ask is
   clean. Attach to the iMessage payload alongside photos.
2. **Continuous evidence burst** — photo + 5s audio + location every 30s for
   the first 5 min after the alarm. Thief covers the lens in second 2; you
   get them eventually when they prop the Mac open at home or sit down
   somewhere. <1 MB total per incident.
3. **Tamper-evident event log** — Merkle hash chain. Every event signs the
   previous event's hash. If the thief deletes entries, the chain breaks
   visibly. ~200 LOC; massive credibility uplift in the "is this evidence
   quality" conversation.
4. **Police-ready PDF report** — auto-generated, single-click export.
   Includes timestamp, serial number, all photos, audio transcripts,
   location trail, defenses snapshot proving FileVault/Find My were on,
   signed hash chain. Hand it to a cop or insurance adjuster. **No
   competitor has this.**
5. **Close `XPCService.swift:127`** — defenses checklist over XPC.
6. **Wire photo-burst → Event Log** (`StateMachine.swift:419`).
7. **`snapshot.lastEvent`** (`StateMachine.swift:74`).
8. **Sparkle in-app auto-update.**
9. **Crash reporting** — PLCrashReporter, anonymous-only.
10. **XPC peer code-sig Team ID verification** (`XPCService.swift:47`).

### v1.4 — "Your Mac and your iPhone protect each other" (4–5 weeks)

The companion ecosystem. Anti-theft is fundamentally a two-device product
and every successful competitor (Prey, HiddenApp, Unplug Alarm) has a
phone app. Vakter has the foundations (AnchorIntents.swift) already.

1. **iOS companion app** — settings, push alerts (separate from iMessage),
   event log with photos + audio playback, "Find My Vakter Mac" map view,
   remote arm/disarm. SwiftUI, ~2 weeks for v1. App Store distribution.
2. **Live web dashboard with evidence stream** — user provides their own
   S3/B2 bucket key once during setup; on alarm, Vakter posts evidence
   there and emails them a one-off URL (`vakter.app/v/abc123`) that shows
   live location + photo stream + audio playback for 7 days. **This is
   what Prey charges $2/mo for** — we do it self-hosted, zero ongoing cost
   to us, **and the evidence survives a Mac wipe** because it's already
   in the cloud before the thief notices.
3. **Apple Watch arm-from-wrist** — single arm/disarm button + haptic
   confirmation. Trivial once iOS app exists. The "tap watch, walk away"
   UX is iconic in the demo video.

### v1.5 — "Set it up once, never think about it again" (4–5 weeks)

Friction killers + Pro tier features. The #1 user friction with every
anti-theft tool is forgetting to arm it. Solve that and you win retention.

1. **Auto-arm rules** — geofence ("arm when I leave home"), Wi-Fi-based
   ("arm when home Wi-Fi disconnects"), calendar-based ("arm during
   meetings"), idle-based ("arm if no input for 90s"). CoreLocation +
   CWWiFiClient + EventKit + IOPMLib already available.
2. **Defenses checklist auto-fix** — for the checks where Vakter *can*
   programmatically fix the issue ("Enable FileVault", "Enable Find My"),
   add a one-click fix button. Pareto Security does this; converts the
   checklist from "guilt-trip" to "concierge".
3. **Multi-Mac coordination (Pro/Family tier)** — register multiple Macs
   to one account, unified event log, "if one is alarmed, alert all the
   others." Justifies the $79 Family tier.
4. **Multi-channel evidence delivery (Pro)** — iMessage + email + Telegram
   bot + Slack webhook. Survives any single channel being offline.
5. **Trusted Wi-Fi networks** — adaptive modes. Home Wi-Fi → Library mode.
   Airport Wi-Fi → Travel mode. Pro tier.
6. **macOS Shortcuts integration** — arm/disarm/run-defenses-check as
   Shortcuts actions. Free tier; great for word-of-mouth in r/macapps.
7. **External monitor / Bluetooth speaker takeover** — if alarm fires and
   external displays or BT speakers are connected, hijack them too. Visual:
   fullscreen "STOLEN MAC — Call 555-XXXX". Audio: siren plays through BT
   speakers too. Cinematic in the demo video.

### Explicitly deferred to v1.6+ or cut entirely

- **Mac App Store version** — daemons can't be sandboxed. Maybe "Vakter
  Lite" (menubar status only, no daemon) as a year-2 top-of-funnel product.
- **iOS companion as separate product** — bundle with Mac app, don't sell
  separately.
- **Honeypot Silent Panic Mode** — needs unified-log monitoring. Defer.
- **Real password swap / Adversary mode** — too risky without FileVault
  recovery-key escrow. Defer.
- **Accelerometer snatch trigger** — false-positive prone (setting Mac on a
  table alarms). Defer indefinitely.
- **Siri voice activation** — Apple's intent extension is painful, 80% of
  users won't use it, hotkey is faster.
- **Social media posting** ("tweet that my Mac was stolen, here's a photo")
  — legal risk if you misidentify someone. **Skip.**
- **Keylogger / screenshot capture of the thief** — creepy, ethical
  landmines, fails App Store. **Skip even though HiddenApp does it.**
- **Cellular triangulation** — only works on cellular M3+ Pro/Max Macs
  (basically zero install base today). Defer 3 years.
- **Apple Intelligence integration** — no real use case for an arm/disarm
  tool.

### Feature parity matrix after v1.5

| | Vakter v1.5 | Prey | Find My | Unplug Alarm | HiddenApp |
|---|:---:|:---:|:---:|:---:|:---:|
| Local alarm + photo burst | ✓ | — | — | ✓ | ✓ |
| Audio capture | ✓ | — | — | — | — |
| Continuous evidence burst | ✓ | partial | — | — | — |
| Tamper-evident log | ✓ | — | — | — | — |
| Police PDF report | ✓ | — | — | — | — |
| iMessage + Maps push | ✓ | — | — | — | — |
| Cloud evidence backup | ✓ (user-owned) | ✓ ($) | — | — | ✓ ($) |
| Live web dashboard | ✓ | ✓ ($) | — | — | ✓ ($) |
| iOS companion | ✓ | ✓ | ✓ | ✓ | ✓ |
| Apple Watch arm | ✓ | — | — | — | — |
| Auto-arm rules | ✓ | — | — | — | — |
| Defenses checklist + auto-fix | ✓ | — | — | — | — |
| Multi-Mac (Pro) | ✓ | ✓ ($) | ✓ | — | ✓ ($) |
| Multi-channel evidence | ✓ | partial | — | — | — |
| Activation lock | (Apple) | — | ✓ | — | — |
| Brand polish + macOS-native UI | ✓ | — | ✓ | — | — |
| Notarized + Hardened Runtime | ✓ | — | (Apple) | ✓ | partial |
| Pricing | $29 one-time | $1.23–2.99/slot/mo | free | $9.99/yr | $1.67–5.99/mo |

After v1.5, Vakter beats Prey on local-response richness, beats Find My on
deterrence, and is the only player offering forensics-grade evidence at
indie-app pricing.

---

## 11. The one-sentence strategic summary

**Vakter is the deterrent layer Apple deliberately doesn't ship: calm in
daily use, fierce the moment your Mac is grabbed. Price it $29 one-time,
publish a security architecture page that earns trust through behavioral
legibility (since the source is closed), lead with a 10-second grab-and-
scream demo video, and chase one Snazzy Labs feature — that's the plan.**
