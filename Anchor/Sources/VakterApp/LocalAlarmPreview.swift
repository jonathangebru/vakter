import Foundation
@preconcurrency import AVFoundation
import VakterShared

/// Last-resort alarm preview that runs *inside the menubar app process*
/// — no XPC, no helper required.
///
/// **Why this exists.** Both Onboarding and Settings → General → Sound
/// have a "Play the alarm" / "Preview" button. Those buttons normally route
/// through the helper (so the user hears the actual production alarm
/// subsystem with system-volume override). But there are real-world
/// scenarios where the helper is unreachable:
///
///   - Brand-new install where the user hasn't yet approved the helper
///     in System Settings → Login Items
///   - Just-rebuilt build where the LWCR signature changed and macOS
///     refuses to launch the binary until the user re-approves
///   - Helper crashed and hasn't restarted yet
///
/// Without this fallback, the button silently does nothing in any of
/// those states. The user can't tell whether the app is broken or just
/// not approved. With this fallback, the button *always* makes a sound.
///
/// The preview uses `AVAudioPlayer` driving an in-memory WAV blob of
/// the user's currently-selected alarm waveform. It plays at the current
/// system volume on the current default output device — *not* the full
/// production override path (forcing internal speakers + max volume).
/// That's fine for preview purposes; the production alarm fires through
/// the helper.
final class LocalAlarmPreview: @unchecked Sendable {

    static let shared = LocalAlarmPreview()

    private let queue = DispatchQueue(label: "app.vakter.mac.localpreview")
    private var current: AVAudioPlayer?

    private init() {}

    /// Play the user's selected alarm sound for `seconds` seconds, then
    /// stop. Idempotent — calling while already playing does nothing.
    ///
    /// Two playback paths depending on whether the chosen `AlarmSound`
    /// is sample-backed (v1.1.0 Sonniss recordings) or synthesised:
    ///
    /// • **Sample-backed** — load the bundled `.m4a` from
    ///   `Bundle.main/Resources/sounds/<rawValue>.m4a` and play it
    ///   directly. Auto-stops itself after `seconds` (the source is
    ///   30 s, so anything ≤ 30 doesn't loop). This is the path the
    ///   Settings → General → Sound Preview button uses and the pre-v1.1.0
    ///   bug was that this branch didn't exist. (Pre-v1.4.3 lived in a
    ///   standalone "Sound" tab; consolidation #23 folded it into General.)
    ///
    /// • **Synthesised** — render PCM via `instantaneousTone()` for
    ///   exactly `seconds`, wrap in a WAV header, play. Unchanged.
    func play(seconds: Double) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.current?.isPlaying == true { return }
            let choice = AlarmSoundStore.load()

            // Sample-backed path — load the bundled m4a directly.
            if choice.isSampleBacked,
               let resourceName = choice.sampleResourceName,
               let url = Bundle.main.url(
                    forResource: resourceName,
                    withExtension: "m4a",
                    subdirectory: "sounds")
            {
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.volume = 1.0
                    player.prepareToPlay()
                    self.current = player
                    player.play()
                    NSLog("[LocalAlarmPreview] playing sampled preview (sound=%@, %.1fs)",
                          choice.rawValue, seconds)
                    // Stop after `seconds` so the 30 s source doesn't
                    // play to completion. Track the player we just
                    // started — if the user kicks off another preview
                    // in the meantime we don't want to stop *that* one.
                    let stoppedPlayer = player
                    self.queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
                        guard let self = self else { return }
                        if self.current === stoppedPlayer {
                            self.current?.stop()
                            self.current = nil
                        }
                    }
                    return
                } catch {
                    NSLog("[LocalAlarmPreview] sampled preview failed (%@): %@ — falling back to synth",
                          resourceName, error.localizedDescription)
                    // Fall through to synth path
                }
            }

            // Synth path — unchanged from v1.0.0.
            let pcm = self.renderPCM(seconds: max(0.3, seconds), choice: choice)
            let wav = self.wrapAsWAV(pcm: pcm)
            do {
                let player = try AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue)
                player.volume = 1.0
                player.prepareToPlay()
                self.current = player
                player.play()
                NSLog("[LocalAlarmPreview] playing synth preview (sound=%@, %.1fs)",
                      choice.rawValue, seconds)
            } catch {
                NSLog("[LocalAlarmPreview] AVAudioPlayer init failed: %@",
                      error.localizedDescription)
            }
        }
    }

    // MARK: - Synth (mirrors the AlarmSound waveform set)

    private let sampleRate: Double = 48000
    private let channels: Int = 2

    /// Render the chosen waveform for the requested duration into raw
    /// 16-bit interleaved stereo PCM. Mirrors `AudioController`'s
    /// `instantaneousTone(t:choice:)` so the preview matches the
    /// production siren character.
    private func renderPCM(seconds: Double, choice: AlarmSound) -> Data {
        let totalFrames = Int(seconds * sampleRate)
        var data = Data(capacity: totalFrames * 4)
        // Phase accumulator — keeps the wave continuous across sample-rate
        // updates and avoids clicks at frequency switches.
        var phase: Double = 0
        let twoPi = 2.0 * .pi
        let attack = Int(sampleRate * 0.02)  // 20 ms attack
        let release = Int(sampleRate * 0.10) // 100 ms release
        let amp = 0.6                         // matches production siren

        for i in 0..<totalFrames {
            let t = Double(i) / sampleRate
            let (freq, ampMul) = LocalAlarmPreview.instantaneousTone(t: t, choice: choice)

            // Envelope: linear attack, linear release, flat sustain.
            let env: Double
            if i < attack {
                env = Double(i) / Double(attack)
            } else if i > totalFrames - release {
                env = max(0, Double(totalFrames - i) / Double(release))
            } else {
                env = 1.0
            }

            let s = amp * ampMul * env * sin(phase)
            let sample16 = Int16(max(-1, min(1, s)) * Double(Int16.max))
            var le = sample16.littleEndian
            let bytes = withUnsafeBytes(of: &le) { Data($0) }
            data.append(bytes)   // left
            data.append(bytes)   // right
            phase += twoPi * freq / sampleRate
            if phase > twoPi { phase -= twoPi }
        }
        return data
    }

    /// Mirrors `AudioController.instantaneousTone(t:choice:)`. Kept
    /// duplicated rather than pulled into VakterShared to avoid pulling
    /// `AVFoundation` into the shared module.
    fileprivate static func instantaneousTone(t: Double, choice: AlarmSound) -> (freq: Double, amp: Double) {
        switch choice {
        case .classicSiren:
            return (880.0, 1.0)
        case .sweepKlaxon:
            let phase2s = t.truncatingRemainder(dividingBy: 2.0)
            let freq = phase2s < 1.0
                ? 600.0 + 600.0 * phase2s
                : 1200.0 - 600.0 * (phase2s - 1.0)
            return (freq, 1.0)
        case .dualTone:
            let toggle = Int(t * 4.0) % 2
            return (toggle == 0 ? 1000.0 : 1300.0, 1.0)
        case .calmChime:
            let lfo = 0.55 + 0.45 * sin(2.0 * .pi * 0.5 * t)
            return (660.0, lfo)
        case .japaneseTwoTone:
            let toggle = Int(t * 2.0) % 2
            return (toggle == 0 ? 1300.0 : 1700.0, 1.0)
        case .europeanNeeNaw:
            let toggle = Int(t * 1.0) % 2
            return (toggle == 0 ? 660.0 : 990.0, 1.0)
        case .pulseAlarm, .rhythmicKlaxon, .urgentBeacon:
            // Sample-backed sounds don't synthesise a frequency — the
            // `play(seconds:)` entry point branches earlier and loads
            // the bundled AAC directly. This case keeps the switch
            // exhaustive; if reached as a fallback (sample missing),
            // play a calm 880 Hz so the user hears *something*.
            return (880.0, 1.0)
        }
    }

    /// Wrap raw 16-bit interleaved stereo PCM in a minimal WAV header.
    private func wrapAsWAV(pcm: Data) -> Data {
        let pcmLength = UInt32(pcm.count)
        let byteRate = UInt32(sampleRate) * UInt32(channels) * 2
        let blockAlign = UInt16(channels * 2)
        let bitsPerSample: UInt16 = 16
        var header = Data()
        func appendLE32(_ v: UInt32) {
            var le = v.littleEndian
            header.append(Data(bytes: &le, count: 4))
        }
        func appendLE16(_ v: UInt16) {
            var le = v.littleEndian
            header.append(Data(bytes: &le, count: 2))
        }
        header.append("RIFF".data(using: .ascii)!)
        appendLE32(36 + pcmLength)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        appendLE32(16)                  // subchunk size (PCM)
        appendLE16(1)                   // audio format = PCM
        appendLE16(UInt16(channels))
        appendLE32(UInt32(sampleRate))
        appendLE32(byteRate)
        appendLE16(blockAlign)
        appendLE16(bitsPerSample)
        header.append("data".data(using: .ascii)!)
        appendLE32(pcmLength)
        var wav = header
        wav.append(pcm)
        return wav
    }
}
