# Vakter Positioning Memo — Physical + Digital Threat Expansion
**Date:** 2026-05-22
**Author:** vakter-brand-keeper
**Status:** Approved for execution — applies to branch `vkt-30-bodyguard-rebrand`
**Predecessor:** `2026-05-22-llm-security-novel-features.md`

---

## Research findings (condensed)

**What the competitive landscape says:**

"Sentinel," "Sentry," and "SentinelOne" are colonized — enterprise Mac security has taken those words. "Watchman Monitoring" uses watchman for IT fleet management (B2B). None of them touch the *night-watchmen / vakter* etymology at the consumer layer.

1Password's brand evolution succeeded because they *layered* the metaphor rather than replacing it: the vault stayed; the scope of what the vault protects expanded. Little Snitch's brand strength comes from naming a behavior, not a feature category. The "watchman" metaphor is inherently extensible: a night watchman guards against every threat that shows up on watch — fire, theft, an intruder climbing the gangway, someone pilfering cargo from a clipboard at 3am.

ClickFix is documented and current. Apple shipped a binary Terminal paste warning in macOS 26.1 (March 2026). Microsoft Security documented an active ClickFix campaign delivering macOS infostealers in May 2026. This is not a theoretical threat. Journalists, indie developers, and activists are the exact users who encounter fake "Cloudflare verify" prompts and developer-tooling impostor pages.

**The metaphor question (honest answer):**

"Bodyguard" is the approved direction. Executing it. But the more precise metaphor for what Vakter does — and what the night-watchmen etymology already says — is *watch*: a watchman guards a *place and its approaches*, while a bodyguard guards a *person*. Vakter guards a Mac (a place + its state), not the user's physical person. The expansion to digital threats (a paste clipboard hijack, a malicious LaunchAgent, a hostile MDM profile) is someone arriving at the dock to board the ship under false pretenses. That's still watch-duty.

**Recommendation in plain terms:** execute the "bodyguard" language as approved (it communicates protection broadly, which is the user-facing goal), but root it in the watch/night-watchman metaphor rather than replacing that metaphor. "Your Mac's bodyguard" is the external positioning claim; "the night-watch" remains the brand soul. They coexist.

---

## Chosen tagline

> **Vakter — the watch that never sleeps.**

This is the primary tagline for use in hero copy, press descriptions, and product context where brevity matters.

Rationale: "watch" preserves the Norwegian etymology (vakter = night-watchmen; a watch is their duty); "never sleeps" is a factual product claim (the daemon runs always-on) and a contrast with Find My (which needs the Mac awake and online); the formulation is a complete sentence without a verb needing "AI" or "boost."

### Three alternates considered

1. **"Calm in normal use. Your Mac's bodyguard when it isn't."**
   — Uses the approved "bodyguard" framing directly. Good for short-form / Twitter. Slightly weaker because "bodyguard" implies personal escort more than place-guarding.

2. **"The deterrent layer Apple doesn't ship — for physical and digital threats."**
   — Accurate and specific. Strong for HN/IH where technical framing converts. Too long for a hero tagline.

3. **"Vakter watches your Mac. Whoever's threatening it doesn't matter."**
   — Blunt, brand-accurate. The "whoever" does the work of expanding scope without naming every threat type. Feels like the existing voice at its best.

---

## Hero paragraph rewrite

**Before:**
> Calm in normal use. Fierce the moment someone tries to walk off with it. Lives in your menu bar. Wakes the deck when the lid closes, the cable pulls, or your phone leaves the room.

**After:**
> Calm in normal use. Fierce the moment someone threatens it — in person or on your clipboard. Lives in your menu bar. Wakes the deck when the lid closes, the cable pulls, or your phone leaves the room. Coming in v1.6: explains the shell command a web page just wrote to your clipboard before you paste it.

The structure is identical. "Threatens it — in person or on your clipboard" is the expansion. One clause. "Coming in v1.6" is honest; the feature is not shipping today.

**Shorter alternate for meta/social:**
> Calm in normal use. Fierce when someone threatens your Mac — physically or digitally. No cloud. No telemetry. €29 once.

---

## 3-line elevator pitch for press

Vakter is a macOS menubar utility that guards your Mac against physical and digital threats. Press one shortcut to arm it; a siren fires, photos capture, and your phone gets a Maps pin the instant someone tries to walk off with it. Starting in v1.6, it also watches your clipboard for shell commands written by malicious web pages — the threat that Apple's new Terminal warning blocks without explaining.

---

## "We already do X, now we also do Y" framing for v1.4 customers

For customers who bought Vakter as anti-theft:

> Vakter v1.4 watches your Mac against the grab: lid close, cable pull, Bluetooth peers gone. That's what shipped. The watch is expanding. v1.6 adds a clipboard shield for ClickFix paste attacks — a web page silently drops a shell command into your clipboard, you paste it into Terminal, it runs. Vakter will intercept and explain the command before it executes. Same watch, wider scope. Your licence covers it.

---

## What stays unchanged

- **The lighthouse glyph.** It's the brand's visual soul. A lighthouse keeps watch over approaches. The glyph fits the expanded threat model as precisely as it fit the original.
- **The night-watchmen etymology.** "§ vakter · norwegian · the night-watchmen" stays in the hero eyebrow. This etymology is the answer to "why this name?" and remains correct at any scope.
- **The calm/fierce duality.** Central rhythm of the brand. Preserved in every rewrite.
- **The navy + amber palette.** Unchanged.
- **The system-font type stack.** Unchanged.
- **"No cloud. No telemetry. No accounts."** These remain the trust anchors. The digital-threat expansion doesn't change them — the clipboard shield runs on-device with no server.
- **"The deterrent layer Apple deliberately doesn't ship."** Still true, now more true: Apple ships a binary paste warning; Vakter ships the explanatory version.
- **Pricing: €29 one-time.** Currency standardized from $29 to €29 across all surfaces.

---

## What evolves

| Surface | Before | After |
|---|---|---|
| Hero tagline | "The night-watch for your Mac" | "The watch that never sleeps." OR keep existing with expanded sub-copy |
| Hero sub-paragraph | Physical threats only | Physical + digital (clipboard); v1.6 callout |
| `<meta description>` | `$29` anti-theft framing | `€29`; physical + digital framing |
| Press 50-word | Anti-theft only | Adds "and digital threats (coming v1.6)" |
| Press 150-word | Anti-theft only | Expanded scope + ClickFix framing |
| Press 500-word | Anti-theft only | Full expanded scope narrative |
| Press quotables | 5 existing | +2 new: bodyguard framing + ClickFix hook |
| Changelog | v1.4.3 is current | Add v1.6 "coming next" entry |
| SECURITY.md §9 out-of-scope | Physical attacks listed | Scope note clarifies physical + digital |
| PRIVACY.md intro | "anti-theft alarm for Mac" | "anti-theft and digital-threat guard for Mac" |
| README opening | "calm anti-theft" | "the watch against physical and digital threats" |
| STRATEGY.md §1 | "anti-theft" positioning | Expanded positioning sentence |
| AI_TEAM.md closing | "Vakter" — anti-theft product | Updated for expanded scope |
| `$29` everywhere | Dollar sign | `€29` |
| FAQ | Existing physical-threat FAQs | +1 FAQ about digital threats scope |

---

## Currency note

All `$29` occurrences become `€29`. This applies to: `Website/index.html` (button, pricing card, compare card, meta descriptions), `Website/press/index.html` (copy snippets, facts), `README.md`, `STRATEGY.md` (comparison tables). A grep confirms 12 distinct `$29` instances across these files before the change.
