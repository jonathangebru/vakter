# Vakter — Sound & Voice Quality Research

**Status:** research, no implementation yet. Recommendations + cost
estimates only.

**Trigger:** Jonathan called both the alarm tones and the TTS cue
"cheap" in his v1.0 user review. The current implementation uses
phase-accumulator sine waves (technically correct, audibly synthetic)
and `AVSpeechSynthesizer` with the default *compact* system voice
(robotic on most installs). Both are fixable; this document maps the
options.

---

## 1. Current state (baseline)

### Sounds
- **6 waveforms**, all synthesised live in `AudioController.startSiren()`
  via a single phase accumulator + `instantaneousTone(t:choice:)`:
  - `classicSiren` — pure 880 Hz sine
  - `sweepKlaxon` — 600→1200 Hz triangle sweep
  - `dualTone` — 1000/1300 Hz at 4 Hz toggle
  - `calmChime` — 660 Hz + 0.5 Hz LFO amplitude
  - `japaneseTwoTone` — 1300/1700 Hz at 2 Hz
  - `europeanNeeNaw` — 660/990 Hz at 1 Hz
- **Quality:** pure sines have no harmonics, no air, no body. They
  cut through but they sound like a 1980s synthesizer, not a real
  emergency vehicle. The `calmChime` LFO helps; the others don't.
- **Bundle cost:** ~0 KB (synthesized at runtime).

### Voice
- `AVSpeechSynthesizer` + `AVSpeechSynthesisVoice(language:)`
- 7 locales hard-coded (en, nl, no, de, fr, es, ja)
- Phrase: *"This MacBook is being tracked. Please put it down."*
  (per locale via `LocalePhrases.swift`)
- **Quality:** defaults to the system's *Compact* voice, which on
  most Macs is the highly-compressed 50 MB voice that sounds
  obviously synthetic. Apple ships *Enhanced* and *Premium* voices
  but they're **opt-in downloads** the user has to install via
  Settings → Accessibility → Spoken Content → System Voice → Manage
  Voices. We currently neither prefer them when present nor prompt
  for the download.
- **Bundle cost:** ~0 KB.

---

## 2. Recommendation summary (TL;DR)

Two-phase path:

### Phase A — *Free quality jump, ship next release* (~1 day)
1. **Prefer Premium / Enhanced AVSpeechSynthesisVoice** when present.
   Falls back to Compact only if nothing better is downloaded. Code:
   `AVSpeechSynthesisVoice.speechVoices().filter { $0.quality == .premium }.first(where: { $0.language == "en-US" })`. **Quality jump = significant.** Cost = 1 hour of code.
2. **Onboarding prompt** to download the Enhanced/Premium variant
   for the user's system locale. Opens
   `x-apple.systempreferences:com.apple.preference.universalaccess?Speech`.
   Cost = 2 hours.
3. **Add 6–8 professional alarm samples** from **Sonniss** or a
   single **Boom Library** pack. Ship as `.m4a` AAC inside the
   .app bundle. Pricing range: free (Sonniss GDC bundle) to
   $99 (Sonniss Sirens). Replace 3-of-6 synth waveforms with real
   samples while keeping the synth as the locale-recognisable
   options (Japanese two-tone, European nee-naw, calm chime —
   these MUST be synth-accurate frequencies, real recordings
   would drift).
4. **Drop the phase-accumulator pure-sine** for the remaining
   synthesised sounds — add a third harmonic (×2 freq at 0.3
   amplitude) so they don't sound like a 1980s synthesizer.
   Cost = 30 min of math.

### Phase B — *Premium polish, post-1.0 release* (~1 week)
5. **Custom-recorded voice** for top 3 languages (en, es, de) by a
   voice actor. Hire on Fiverr / VoicesPro ~$50-150 per locale. Ship
   as embedded `.m4a`. Adds ~10 MB. Massive quality jump.
6. **Localized siren cadences** — actual recorded sirens from EU,
   US, JP emergency vehicles, sourced from Sonniss locale packs.
7. **Optional Piper TTS download** as a "Natural voice" toggle in
   Settings → Sound. User clicks → app downloads a 30 MB ONNX voice
   model. Local, offline, no per-call cost. Best-in-class quality.

---

## 3. Sound pack research (detailed)

### Option A — Sonniss
**Price**: $69-$199 per pack, or **FREE** via their annual GDC bundle (released every January, hundreds of GB of pro-grade SFX, **explicitly licensed for commercial use including app embedding**).

**Recommended packs for Vakter**:
- *Traditional Sirens* ($129) — vintage civilian / civil-defence sirens, useful for the "classic" mode
- *Sirens* (AudioHero collection, 170 recordings, $99) — ambulance, police, fire, multiple distances + perspectives
- *Civil Alarm* ($69) — institutional alarms, perfect for the cafe / library "gentle" mode
- *South African Sirens* ($59) — niche, but a unique locale option

**License**: royalty-free, perpetual, includes embedding in shipped applications (verified via their license terms). One-time payment, no recurring fees.

### Option B — Boom Library
**Price**: ~$50–$300 per pack. The flagship **BOOM ONE** is 48,000+ files for $499/yr subscription.

Industry-standard quality (used in major Hollywood films and AAA games). Heavier than Vakter needs. Skip unless we're scaling to dozens of sounds.

### Option C — ElevenLabs Sound Effects (AI-generated)
**Price**: subscription, starts at $5/month for the smallest paid tier (free tier excludes commercial use).

You type a prompt ("urgent klaxon, 3-second loop"), it generates 4 variants. Files are royalty-free for commercial use *on a paid account*. Caveat from their TOS: you can't use the output to build a "competing TTS product" — Vakter is an alarm app, not a TTS product, so this is fine.

**Use case**: rapid iteration of unusual alarms (the "stealth panic mode" silent chime, for example) without paying a sound designer.

### Option D — Mixkit / Zapsplat / HookSounds (free tiers)
Free for personal + commercial use **with attribution required** on some tiers. The attribution requirement is incompatible with a paid Vakter — every user would see "siren by Mixkit" inside the app. Skip the free tiers, **buy the licensed paid tier** if going this route.

### Option E — Freesound.org
**Price**: free, but mixed licenses. Each sound is individually licensed by its uploader (CC0, CC-BY, CC-BY-NC). For a paid commercial app, only **CC0** sounds are safe; CC-BY requires attribution; CC-BY-NC blocks commercial use entirely.

Good for prototyping. Risky for production — license audit per sample.

### Option F — Hire a sound designer
**Price**: $500–$2000 for 8–10 bespoke alarm sounds.

Marketplaces: Fiverr (`$50-200/sound`), Splice (subscription + commissioned work), specialised platforms like **A Sound Effect** or **The Sound Lab**.

**Recommended path for Vakter**:
- Buy **Sonniss "Traditional Sirens"** ($129) — covers `classicSiren` + a richer alternative
- Buy **Sonniss "Civil Alarm"** ($69) — covers `calmChime` upgrade for cafe/library mode
- **OR** wait for the next Sonniss GDC bundle (free) and pick from there

Total Phase-A sound cost: **$0–$198 one-time**.

---

## 4. Voice TTS research (detailed)

### Option A — `AVSpeechSynthesisVoice.quality == .premium`
**The easy win.** macOS Sonoma (14) and Sequoia (15) ship neural
Premium voices for download. Quality is genuinely good — "quietly
excellent" per the developer community. 100 ms first-audio latency,
zero network dependency, zero bundle cost (the user downloads them).

**The catch**: not all Macs have them downloaded. Default after a
clean OS install is the Compact voice. Per locale, Premium is
~100–200 MB to download.

**Vakter's job**: detect, prefer, prompt to download if absent.

```swift
// Best-available voice for the current locale.
let lang = LocalePhrases.voiceLanguageTag(for: .current)
let voice = AVSpeechSynthesisVoice.speechVoices()
    .filter { $0.language == lang }
    .sorted { ($0.quality.priority) > ($1.quality.priority) }
    .first
    ?? AVSpeechSynthesisVoice(language: "en-US")
```

Where `priority` is: premium=3, enhanced=2, default=1.

### Option B — Piper (open-source neural TTS)
- Open-source (MIT), based on the VITS architecture
- **Apple Silicon native** (arm64, macOS 13+)
- ONNX runtime, **runs on CPU only** (no GPU needed)
- Voice models: 20–100 MB each, **hundreds of languages**
- Natural-sounding, very close to commercial TTS

**Integration paths**:
1. **CLI binary embedded in bundle** + `Process()` call — simplest, ~50 MB binary + 30 MB per voice. Total ~150 MB extra in the .app bundle. Code: trivial.
2. **ONNX Runtime Swift bindings** + ship the `.onnx` model directly. Smaller (~30 MB per voice, no piper binary), but adds Swift package dependency on `onnxruntime-swift-package-manager` (~20 MB framework). Code: ~200 LoC.
3. **Localhost HTTP server** — bring up piper as a child process bound to 127.0.0.1, hit it with curl. Heavy, slow, not recommended for a menubar app.

**Vakter implementation**: integration path **(2)**. Make it an **optional download** so the default install stays small. Settings → Sound → "Use natural voice" toggle → first toggle triggers a 30 MB download (per locale). Voices cached at `~/Library/Application Support/Vakter/voices/`.

### Option C — Kokoro (newer, current SOTA)
- StyleTTS 2 based, 82M parameters (smaller than most rivals)
- **Mean Opinion Score (MOS) 4.2** — basically indistinguishable from early ElevenLabs to a non-expert
- Runs on **MacBook Pro M1-M4** via MPS (Metal Performance Shaders)
- Newer (2025), less battle-tested than Piper
- Apache 2.0 license, commercial use OK

**Trade-off vs Piper**: Kokoro sounds better but is newer. Piper is rock-solid. For Vakter's "must work the moment of an alarm" requirement, **Piper is safer**.

### Option D — Custom voice actor recording
- One-time cost: $500–$2000 for ~20 lines × 3-5 languages
- Sources: Voices.com, Voice123, Fiverr Pro, ACX
- Output: studio-quality `.wav`, converted to `.m4a` for bundle
- Bundle cost: ~5 MB per language
- **Cannot adapt to new phrases** without re-hiring

For Vakter this works because the phrase set is small:
- `alarmVoiceCue` — *"This MacBook is being tracked. Please put it down."*
- (escalating versions: 3 variants per locale)

Total phrases per locale: 3. Total recordings for top-5 languages: 15. Voice actor time: 1-2 hours. Cost: ~$300-800.

**Quality**: indistinguishable from professional film dub.

### Option E — Cloud TTS APIs (OpenAI, Azure, ElevenLabs)
- **Skip.** Vakter's alarm fires when a thief takes the Mac. If they
  yank the power or disable Wi-Fi, the TTS call fails and the alarm
  goes silent. **The whole point is offline reliability.**
- Acceptable use case: pre-generating phrases via cloud TTS, then
  bundling the recordings. Effectively the same as Option D but
  cheaper ($0.30/M chars on OpenAI, ~$5 for the full Vakter phrase
  set in 7 languages). Quality: very good, slightly less natural
  than a human actor.

---

## 5. Bundle-size trade-off

| Option | Voice quality | Bundle cost | Per-launch cost |
|---|---|---|---|
| Current (Compact AVSS) | 4/10 | 0 KB | 0 ms |
| Prefer Premium AVSS | 8/10 (if installed) | 0 KB | 0 ms |
| Premium AVSS + onboarding download prompt | 8/10 (always) | 0 KB | one-time 200 MB OS-level download |
| Piper, optional download | 9/10 | 0 KB by default, +30 MB on toggle | 100-200 ms per phrase |
| Piper, shipped in bundle | 9/10 | +150 MB | 100-200 ms per phrase |
| Pre-recorded voice actor (5 langs) | 10/10 | +25 MB | 0 ms |

**Vakter's current DMG is 3.1 MB.** Pre-recorded voice actor is the sweet spot: best quality, smallest bundle, no runtime cost, no user-action required. Phase B work, but it's the right end state.

---

## 6. Recommended roadmap

### Phase A — v1.1 release, ~1 day of work
- [ ] Code: prefer Premium/Enhanced AVSS voices when present (~1 h)
- [ ] Onboarding step: "Want a more natural voice?" → opens Speech settings (~1 h)
- [ ] Audio: replace 3 pure-sine waveforms with sampled real-world variants from Sonniss GDC bundle (free if available, $0; or $69 for Civil Alarm pack)
- [ ] Audio: add 3rd harmonic to remaining synth waveforms so they sound less 1980s
- [ ] Test on a Mac with NO Enhanced voice downloaded — confirm graceful fallback

**Cost: $0–$198 + ~6 h dev time.**

### Phase B — v1.2 release, ~1 week of work
- [ ] Hire voice actors for top-3 locales (en, es, de). 3 lines per locale × 3 escalation levels = 9 takes each. Budget $500–$800.
- [ ] Embed `.m4a` files in `Resources/voices/<locale>/`.
- [ ] Code: pick recorded sample over AVSS when available for that locale.
- [ ] Audio: buy Sonniss "Sirens" ($99) — replace remaining synth waveforms.

**Cost: $500–$1000 + ~3 days dev time.**

### Phase C — v1.3+, optional power-user feature
- [ ] "Use natural voice" toggle in Settings → Sound.
- [ ] First-time toggle: download a Piper ONNX voice (~30 MB) for the active locale, cache in support dir.
- [ ] Add a small ONNX runtime swift package to AnchorHelper target.
- [ ] Falls back to recorded voice → AVSS premium → AVSS compact.

**Cost: ~3 days dev time, $0 ongoing.**

---

## 7. Open questions before committing budget

1. **Is the user OK with a one-time $99 Sonniss purchase?** Cleanest path; alternative is waiting for the free January GDC bundle (next drop: Jan 2026).
2. **Voice actor language priority?** Default Vakter languages are en/nl/no/de/fr/es/ja. Top 3 commercial impact is probably en/es/de — Norwegian is brand-name only, French/Japanese can stay AVSS Premium for now.
3. **What's the bundle-size ceiling?** Current DMG is 3.1 MB. Embedded recorded voice for 3 langs adds ~15 MB → DMG becomes ~18 MB. Still tiny by Mac-app standards. Embedded Piper would push it to 150 MB+ — that's the constraint.

---

## Sources

- [Sonniss alarms & sirens libraries](https://sonniss.com/category/sound-libraries/alarms-sirens/)
- [Sonniss Sirens AudioHero pack](https://sonniss.com/sound-effects/sirens/)
- [Sonniss Civil Alarm](https://sonniss.com/sound-effects/civil-alarm/)
- [BOOM Library](https://www.boomlibrary.com/)
- [ElevenLabs Sound Effects](https://elevenlabs.io/sound-effects)
- [ElevenLabs licensing](https://help.elevenlabs.io/hc/en-us/articles/13313564601361-Can-I-publish-the-content-I-generate-on-the-platform)
- [Mixkit free siren SFX](https://mixkit.co/free-sound-effects/siren/)
- [Zapsplat sirens & alarms](https://www.zapsplat.com/sound-effect-category/sirens-and-alarms/)
- [Apple AVSpeechSynthesisVoiceQuality](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality)
- [Apple AVSpeechSynthesisVoiceQuality.premium](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality/premium)
- [WWDC23 — Extend Speech Synthesis with personal and custom voices](https://developer.apple.com/videos/play/wwdc2023/10033/)
- [Piper TTS GitHub](https://github.com/rhasspy/piper)
- [piper-onnx Swift/ONNX usage](https://github.com/thewh1teagle/piper-onnx)
- [Local TTS on Mac, 2026 paths comparison](https://fazm.ai/t/local-text-to-speech-ai)
- [Best open-source TTS 2026 comparison](https://www.codesota.com/guides/tts-models)
- [Offline TTS engine comparison — what sounds human](https://www.freevoicereader.com/blog/offline-tts-engine-comparison-human-voices)
