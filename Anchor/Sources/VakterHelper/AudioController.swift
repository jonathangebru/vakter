import Foundation
import CoreAudio
import AVFoundation
import VakterShared

/// Protocol the state machine talks to (lets us inject a test double).
protocol AudioControlling {
    func playArmChirp()
    func playGraceChirp()
    func playDisarmChirp()
    func startAlarm(audible: Bool)

    /// Variant that lets the state machine pin a per-mode hard cap on
    /// audible-siren runtime. Used by `.cafe` mode (30 s cap) so the
    /// laptop doesn't scream for ten minutes in a coffee shop. `cap`
    /// of `nil` means "use the global 10-min failsafe."
    func startAlarm(audible: Bool, cap: TimeInterval?)

    func stopAlarm()

    /// Fire the full alarm subsystem (siren + voice + system-audio override
    /// to internal speakers at max volume) for `duration` seconds, then
    /// auto-stop and restore prior audio state. Used by the Diagnostics
    /// menu "Test alarm" item. Independent of the state machine.
    func playTestAlarm(duration: TimeInterval)
}

/// The Anchor alarm audio engine.
///
/// Implementation strategy verified by spikes 1 and 7 (2026-05-11):
///   - CoreAudio for system volume + mute + output-device override
///   - AVAudioEngine for the siren tone (looped sine sweep)
///   - AVSpeechSynthesizer for the voice cue, mixed alongside
///
/// During ALARM we:
///   1. Snapshot the user's current volume + mute + output device
///   2. Force volume → 100%, unmute, route to internal speakers
///   3. Start the siren on a loop and inject voice utterances every ~4s
///   4. On `stopAlarm()`: restore everything to the snapshot
final class AudioController: AudioControlling, @unchecked Sendable {

    private let engine = AVAudioEngine()
    private let synth = AVSpeechSynthesizer()

    /// Holds a strong reference to the currently-playing bundled voice
    /// clip so `AVAudioPlayer` isn't deallocated mid-utterance. Cleared
    /// in `stopAlarm()` to silence in-flight playback when the user
    /// disarms during the voice cue.
    private var activeVoicePlayer: AVAudioPlayer?

    /// Holds the looping `AVAudioPlayer` for sample-backed alarm sounds
    /// (Sonniss recordings under `Resources/sounds/`). Lives for the
    /// duration of the alarm; `stopAlarm()` calls `.stop()` + nils it.
    private var sampleSirenPlayer: AVAudioPlayer?
    private let chirps = ChirpPlayer()

    // Saved-state snapshot so we restore exactly what the user had.
    private struct Snapshot {
        let volume: Float32
        let muted: UInt32
        /// The default-output device that was active before the alarm took
        /// over (e.g. AirPods, external speakers). Restored on disarm so
        /// audio routing returns to normal.
        let priorDefaultOutput: AudioObjectID
    }
    private var snapshot: Snapshot?

    private var isPlayingAlarm = false
    private var voiceTimer: DispatchSourceTimer?

    /// Failsafe: if the alarm somehow never gets stopped (a crash mid-
    /// flight, a hung disarm path, a thief who keeps the Mac powered
    /// for hours), we still don't want the siren to run forever burning
    /// the battery and rendering the laptop unusable to the rightful
    /// owner when they recover it. Ten minutes is the hard ceiling for
    /// audible-alarm runtime. After that we auto-stop and restore audio
    /// state. The visual armed state (red strip / menubar shield)
    /// remains — only the audible siren cuts out.
    private static let maxAlarmDuration: TimeInterval = 10 * 60
    private var alarmFailsafeTimer: DispatchSourceTimer?

    // MARK: Public

    func playArmChirp() {
        NSLog("[Audio] ARM chirp")
        chirps.playArmChirp()
    }

    func playGraceChirp() {
        NSLog("[Audio] GRACE chirp")
        chirps.playGraceChirp()
    }

    func playDisarmChirp() {
        NSLog("[Audio] DISARM chirp")
        chirps.playDisarmChirp()
    }

    func startAlarm(audible: Bool) {
        startAlarm(audible: audible, cap: nil)
    }

    func startAlarm(audible: Bool, cap: TimeInterval?) {
        guard !isPlayingAlarm else { return }
        isPlayingAlarm = true

        if audible {
            snapshotSystemAudio()
            forceMaxOutput()
            startSiren()
            startVoiceCueLoop()
            armFailsafeTimer(cap: cap)
        } else {
            // Library / cafe equivalent: skip siren; just play the
            // elevated chirp pattern (TODO) so it's audible but not
            // blaring. Even silent alarms respect the per-mode cap
            // so the photo-burst loop has a known upper bound.
            NSLog("[Audio] alarm started (inaudible mode, cap=%.0fs)",
                  cap ?? Self.maxAlarmDuration)
            armFailsafeTimer(cap: cap)
        }
    }

    func stopAlarm() {
        guard isPlayingAlarm else { return }
        isPlayingAlarm = false
        voiceTimer?.cancel(); voiceTimer = nil
        alarmFailsafeTimer?.cancel(); alarmFailsafeTimer = nil
        synth.stopSpeaking(at: .immediate)
        // Silence any in-flight bundled-voice playback. Without this
        // a `.m4a` started right before disarm would keep talking for
        // the rest of the clip — bad UX.
        activeVoicePlayer?.stop()
        activeVoicePlayer = nil
        // Same for the sample-backed siren loop.
        sampleSirenPlayer?.stop()
        sampleSirenPlayer = nil
        if engine.isRunning { engine.stop() }
        restoreSystemAudio()
        NSLog("[Audio] alarm stopped")
    }

    /// Arm a one-shot timer that hard-stops the audible siren after a
    /// duration cap. Calls `stopAlarm()` which restores audio state and
    /// releases CoreAudio resources. The state machine remains in
    /// `.alarm` — only the audio cuts out so the battery doesn't drain.
    ///
    /// `cap` is the per-mode cap (currently used by `.cafe` mode to
    /// limit the public-space siren to 30 s); nil falls back to the
    /// global `maxAlarmDuration` ceiling (10 min).
    private func armFailsafeTimer(cap: TimeInterval? = nil) {
        alarmFailsafeTimer?.cancel()
        let duration = cap ?? Self.maxAlarmDuration
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + duration)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isPlayingAlarm else { return }
            NSLog("[Audio] failsafe — alarm has run for %.0fs, cutting siren",
                  duration)
            self.stopAlarm()
        }
        timer.resume()
        alarmFailsafeTimer = timer
    }

    func playTestAlarm(duration: TimeInterval) {
        NSLog("[Audio] TEST alarm — running real subsystem for %.1fs", duration)
        startAlarm(audible: true)
        DispatchQueue.global().asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.stopAlarm()
            NSLog("[Audio] TEST alarm — finished, audio restored")
        }
    }

    // MARK: System audio override (CoreAudio)

    private func snapshotSystemAudio() {
        guard let dev = defaultOutputDevice() else { return }
        var vol: Float32 = 0
        var mute: UInt32 = 0
        _ = readFloat32(dev, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, &vol)
        _ = readUInt32(dev, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, &mute)
        snapshot = Snapshot(volume: vol, muted: mute, priorDefaultOutput: dev)
        NSLog("[Audio] snapshot: vol=%.2f mute=%u priorDev=%u", vol, mute, dev)
    }

    private func forceMaxOutput() {
        // Step 1: force the system default output device to the built-in
        // speakers, in case the user has AirPods / external speakers active.
        // We don't want the alarm playing quietly into a thief's earbuds.
        if let internalSpeakers = internalSpeakersDevice() {
            setDefaultOutputDevice(internalSpeakers)
            NSLog("[Audio] default output → internal speakers (id=%u)", internalSpeakers)
        } else {
            NSLog("[Audio] WARN: could not locate internal speakers; alarm plays through current default")
        }

        // Step 2: unmute and max volume on the (now-current) default device.
        // On Apple Silicon Macs, the master-element volume on
        // `kAudioObjectPropertyElementMain` (formerly Master) is often a
        // no-op for output devices — the device exposes per-channel
        // volume only. So we write to ALL elements: Main + every channel
        // we can find (typically 1 = left, 2 = right). Belt-and-braces.
        guard let dev = defaultOutputDevice() else { return }

        // Unmute, then read back to verify.
        var muteBefore: UInt32 = 0
        _ = readUInt32(dev, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, &muteBefore)
        let muteWriteOK = writeUInt32(dev, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, 0)
        var muteAfter: UInt32 = 99
        _ = readUInt32(dev, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, &muteAfter)
        NSLog("[Audio] mute: %u→%u (write ok=%@)", muteBefore, muteAfter, muteWriteOK ? "yes" : "no")

        // Volume write across master + per-channel elements.
        let beforeMaster = readScalar(dev, element: kAudioObjectPropertyElementMain)
        var anySucceeded = false
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            let ok = writeScalar(dev, value: 1.0, element: element)
            if ok { anySucceeded = true }
        }
        let afterMaster = readScalar(dev, element: kAudioObjectPropertyElementMain)
        let afterCh1    = readScalar(dev, element: 1)
        let afterCh2    = readScalar(dev, element: 2)
        NSLog("[Audio] forceMax: any-write=%@ master %.2f→%.2f ch1=%.2f ch2=%.2f",
              anySucceeded ? "yes" : "no",
              beforeMaster, afterMaster, afterCh1, afterCh2)

        // Also crank the AVAudioEngine's own mixer — defensive, since the
        // engine's per-node volume multiplies the system volume.
        engine.mainMixerNode.outputVolume = 1.0
    }

    private func restoreSystemAudio() {
        guard let snap = snapshot else { return }
        // Restore volume + mute on whichever device is currently default
        // BEFORE switching back, so the internal-speakers state is left
        // identical to how the user typically uses it.
        if let dev = defaultOutputDevice() {
            for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
                _ = writeScalar(dev, value: snap.volume, element: element)
            }
            _ = writeUInt32(dev, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, snap.muted)
        }
        // Then switch the default output back to what it was (e.g. AirPods).
        if snap.priorDefaultOutput != 0 {
            setDefaultOutputDevice(snap.priorDefaultOutput)
            NSLog("[Audio] default output restored to id=%u", snap.priorDefaultOutput)
        }
        snapshot = nil
    }

    // Channel-aware helpers for volume reads/writes.
    private func readScalar(_ id: AudioObjectID, element: UInt32) -> Float32 {
        var out: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        let s = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &out)
        return s == noErr ? out : -1.0
    }

    @discardableResult
    private func writeScalar(_ id: AudioObjectID, value: Float32, element: UInt32) -> Bool {
        var v = value
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        let s = AudioObjectSetPropertyData(
            id, &addr, 0, nil,
            UInt32(MemoryLayout<Float32>.size), &v
        )
        return s == noErr
    }

    // MARK: Siren

    /// Phase-accumulator-based source-node renderer. Reads the user-
    /// selected `AlarmSound` at alarm-start time and dispatches to the
    /// right waveform generator. Phase is continuous across callbacks
    /// — the audio engine calls our closure sequentially on a real-time
    /// thread, so no synchronisation is required between calls.
    private func startSiren() {
        let choice = AlarmSoundStore.load()

        // Sample-backed sirens (Sonniss GDC 2026 — Federico Soler) play
        // through an `AVAudioPlayer` on infinite loop. Audibly richer
        // than the synth waveforms; v1.1's headline audio upgrade.
        if choice.isSampleBacked,
           let name = choice.sampleResourceName,
           let url = Bundle.main.url(
                forResource: name, withExtension: "m4a",
                subdirectory: "sounds")
        {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1   // infinite
                player.volume = 1.0
                player.prepareToPlay()
                player.play()
                self.sampleSirenPlayer = player
                NSLog("[Audio] siren started (sound=%@, sampled)", choice.rawValue)
                return
            } catch {
                NSLog("[Audio] sampled siren load failed (%@): %@ — falling back to synth",
                      name, error.localizedDescription)
                // fall through to synth path below
            }
        }

        let fmt = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let sampleRate = 48000.0
        let twoPi = 2.0 * .pi

        // Phase + sample counter live on the audio thread's closure; no
        // allocation inside the render block.
        var phase: Double = 0.0
        var sampleIndex: UInt64 = 0

        let src = AVAudioSourceNode(format: fmt) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buf in buffers {
                guard let ptr = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<Int(frameCount) {
                    let n = sampleIndex + UInt64(i)
                    let t = Double(n) / sampleRate
                    // Instantaneous frequency + amplitude for this sample.
                    let (freq, ampMul) = Self.instantaneousTone(t: t, choice: choice)
                    ptr[i] = Float(ampMul * sin(phase)) * 0.6
                    phase += twoPi * freq / sampleRate
                    if phase > twoPi { phase -= twoPi }
                }
            }
            sampleIndex += UInt64(frameCount)
            return noErr
        }

        engine.attach(src)
        engine.connect(src, to: engine.mainMixerNode, format: fmt)
        do {
            try engine.start()
            NSLog("[Audio] siren started (sound=%@)", choice.rawValue)
        } catch {
            NSLog("[Audio] engine start FAILED: %@", error.localizedDescription)
        }
    }

    /// Pure function — given the current sample time `t` (seconds) and
    /// the chosen alarm style, return the instantaneous frequency in Hz
    /// and the amplitude multiplier in [0, 1]. The render block uses
    /// these per sample to drive a single phase accumulator.
    fileprivate static func instantaneousTone(t: Double, choice: AlarmSound) -> (freq: Double, amp: Double) {
        switch choice {
        case .classicSiren:
            // Confident 880 Hz sine — the calm-protector default.
            return (880.0, 1.0)

        case .sweepKlaxon:
            // Triangle frequency sweep 600 → 1200 → 600 over 2 seconds.
            // Period-2s triangle: 0..1 ramps up, 1..2 ramps down.
            let phase2s = t.truncatingRemainder(dividingBy: 2.0)
            let freq = phase2s < 1.0
                ? 600.0 + 600.0 * phase2s          // up
                : 1200.0 - 600.0 * (phase2s - 1.0) // down
            return (freq, 1.0)

        case .dualTone:
            // Alternate 1000 Hz / 1300 Hz at 4 Hz toggle. Phase keeps
            // accumulating across switches so the click is minimal.
            let toggle = Int(t * 4.0) % 2
            return (toggle == 0 ? 1000.0 : 1300.0, 1.0)

        case .calmChime:
            // 660 Hz with a 0.5 Hz amplitude wobble — loud (system
            // volume is still forced) but less aggressive in profile.
            let lfo = 0.55 + 0.45 * sin(2.0 * .pi * 0.5 * t)
            return (660.0, lfo)

        case .japaneseTwoTone:
            // 1300 / 1700 Hz alternating at 2 Hz — Japanese emergency-
            // vehicle cadence. Higher pitch than the European nee-naw
            // because it has to cut through urban noise.
            let toggle = Int(t * 2.0) % 2
            return (toggle == 0 ? 1300.0 : 1700.0, 1.0)

        case .europeanNeeNaw:
            // 660 / 990 Hz alternating at 1 Hz — the cadence Brits,
            // Germans, and French read as "ambulance / police."
            let toggle = Int(t * 1.0) % 2
            return (toggle == 0 ? 660.0 : 990.0, 1.0)

        case .pulseAlarm, .rhythmicKlaxon, .urgentBeacon:
            // Sample-backed sounds never reach this synth path —
            // `startSiren()` short-circuits to `AVAudioPlayer` before
            // attaching the source node. This case keeps the switch
            // exhaustive; if reached (sample missing at runtime),
            // play a confident 880 Hz so the alarm fires *something*.
            return (880.0, 1.0)
        }
    }

    // MARK: Voice cue

    /// One-time index that picks the best AVSpeechSynthesisVoice for
    /// each locale on this Mac. Prefers `.premium` > `.enhanced` >
    /// default. Computed once at first use, not per utterance, because
    /// `AVSpeechSynthesisVoice.speechVoices()` is ~150 entries and
    /// iterating it every 4 s during an alarm is wasted CPU.
    private static let bestVoiceCache: [String: AVSpeechSynthesisVoice] = {
        var cache: [String: AVSpeechSynthesisVoice] = [:]
        for voice in AVSpeechSynthesisVoice.speechVoices() {
            let lang = voice.language
            // Quality priority: premium=3, enhanced=2, default=1.
            // Higher number wins.
            let candidatePriority: Int = {
                switch voice.quality {
                case .premium:  return 3
                case .enhanced: return 2
                default:        return 1
                }
            }()
            let incumbentPriority: Int = {
                guard let incumbent = cache[lang] else { return 0 }
                switch incumbent.quality {
                case .premium:  return 3
                case .enhanced: return 2
                default:        return 1
                }
            }()
            if candidatePriority > incumbentPriority {
                cache[lang] = voice
            }
        }
        NSLog("[Audio] voice-cache: %d languages indexed", cache.count)
        return cache
    }()

    /// Bundled pre-rendered audio for the given phrase + active locale.
    /// Returns nil if the bundle doesn't ship audio for this combination
    /// (e.g. a locale we don't support, or a phrase we haven't rendered).
    /// The runtime path then falls back to live AVSpeechSynthesizer.
    ///
    /// Audio lives at `<bundle>/Resources/voices/<locale>/<phrase>.m4a`,
    /// rendered by `Scripts/render-voices.sh` at build time using a mix
    /// of Piper (neural) for European languages and Apple `say` for
    /// Japanese / Korean (Piper has no models for those).
    private func bundledVoiceURL(phrase: VakterPhrase, locale: String) -> URL? {
        Bundle.main.url(
            forResource: phrase.rawValue,
            withExtension: "m4a",
            subdirectory: "voices/\(locale)"
        )
    }

    private func startVoiceCueLoop() {
        // Pull text + voice tag from `LocalePhrases` so the cue is
        // spoken in the user's macOS-system language. Supported:
        // en, nl, no, de, fr, es, ja, it, zh, ko. Falls back to en-US
        // if the host system locale isn't in our table.
        let voiceTag = LocalePhrases.voiceLanguageTag(for: .current)
        let phraseKey: VakterPhrase = .alarmVoiceCue

        let utterance: () -> Void = { [weak self] in
            guard let self = self, self.isPlayingAlarm else { return }

            // Path 1 — bundled pre-rendered audio. This is the v1.1
            // headline feature: Piper-rendered or Apple-say-rendered
            // AAC, ~30 KB per clip, ships in the .app. Always loads in
            // <50 ms, always sounds the same regardless of which
            // AVSpeechSynthesisVoice the user has installed.
            if let url = self.bundledVoiceURL(phrase: phraseKey, locale: voiceTag) {
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.volume = 1.0
                    player.prepareToPlay()
                    player.play()
                    // Keep a strong reference until playback finishes,
                    // otherwise the player deallocates mid-utterance.
                    self.activeVoicePlayer = player
                    return
                } catch {
                    NSLog("[Audio] bundled voice failed (%@/%@): %@ — falling back to AVSS",
                          voiceTag, phraseKey.rawValue, error.localizedDescription)
                }
            }

            // Path 2 — live AVSpeechSynthesizer, picking the best-quality
            // voice we have installed for this locale. Falls back to
            // en-US Premium if available, else system default.
            let phrase = AVSpeechUtterance(
                string: LocalePhrases.text(phraseKey, locale: .current)
            )
            phrase.voice = Self.bestVoiceCache[voiceTag]
                ?? Self.bestVoiceCache["en-US"]
                ?? AVSpeechSynthesisVoice(language: "en-US")
            phrase.volume = 1.0
            phrase.rate = AVSpeechUtteranceDefaultSpeechRate
            self.synth.speak(phrase)
        }

        NSLog("[Audio] voice-cue locale=%@ bundled=%@",
              voiceTag,
              bundledVoiceURL(phrase: phraseKey, locale: voiceTag) == nil ? "no" : "yes")

        // Fire immediately, then every 4 seconds.
        utterance()
        let t = DispatchSource.makeTimerSource(queue: .global())
        t.schedule(deadline: .now() + 4.0, repeating: 4.0)
        t.setEventHandler(handler: utterance)
        t.resume()
        voiceTimer = t
    }

    // MARK: CoreAudio low-level helpers (ported from spikes/01-audio)

    private func defaultOutputDevice() -> AudioObjectID? {
        var id: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let s = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return s == noErr ? id : nil
    }

    @discardableResult
    private func setDefaultOutputDevice(_ id: AudioObjectID) -> Bool {
        var value = id
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let s = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
            UInt32(MemoryLayout<AudioObjectID>.size), &value
        )
        return s == noErr
    }

    /// Enumerate all output devices and identify the built-in speakers
    /// by name. Ports the spike-1 detection logic verified on this Mac.
    private func internalSpeakersDevice() -> AudioObjectID? {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var status = AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size)
        guard status == noErr else { return nil }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids)
        guard status == noErr else { return nil }

        for id in ids {
            let name = deviceName(id).lowercased()
            if name.contains("macbook") && name.contains("speaker") { return id }
            if name.contains("built-in output") { return id }
            if name.contains("internal speakers") { return id }
        }
        return nil
    }

    /// Read the human-readable name of an audio device.
    private func deviceName(_ id: AudioObjectID) -> String {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let s = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name)
        guard s == noErr, let result = name?.takeRetainedValue() else { return "?" }
        return result as String
    }

    private func readFloat32(_ id: AudioObjectID, selector: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope, _ out: inout Float32) -> Bool {
        var size = UInt32(MemoryLayout<Float32>.size)
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &out) == noErr
    }

    private func writeFloat32(_ id: AudioObjectID, selector: AudioObjectPropertySelector,
                              scope: AudioObjectPropertyScope, _ value: Float32) -> Bool {
        var v = value
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    private func readUInt32(_ id: AudioObjectID, selector: AudioObjectPropertySelector,
                            scope: AudioObjectPropertyScope, _ out: inout UInt32) -> Bool {
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &out) == noErr
    }

    private func writeUInt32(_ id: AudioObjectID, selector: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope, _ value: UInt32) -> Bool {
        var v = value
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }
}
