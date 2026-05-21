import Foundation
@preconcurrency import AVFoundation

/// Plays the short UI confirmation tones — arm chirp, grace chirp,
/// disarm chirp. Each is synthesised on the fly: PCM samples generated in
/// memory, wrapped in a WAV container, played through `AVAudioPlayer`.
///
/// **Why AVAudioPlayer and not AVAudioEngine?**
/// We originally used `AVAudioEngine` + `AVAudioPlayerNode` for chirps.
/// That throws `'com.apple.coreaudio.avfaudio' player did not see an IO
/// cycle.` when called while the audio state is transitioning — which is
/// exactly what happens during a lid-close arm sequence (screen lock
/// engages right before the grace chirp is requested). The exception
/// crashed the entire helper. AVAudioPlayer manages its own audio unit
/// internally, never raises that exception, and is the right level of
/// abstraction for short one-shot clips anyway.
///
/// Sound design (calm-protector brand):
///   - Arm chirp:    two warm tones (660 → 880 Hz), 120 ms each
///   - Grace chirp:  one tone (700 Hz, 150 ms), amplitude escalates on
///                   each successive grace chirp
///   - Disarm chirp: two warm tones (880 → 660 Hz), 120 ms each
///
/// All tones use a half-sine envelope (attack + release) so they don't
/// click on start/stop. Amplitude is conservative (~30% peak).
///
/// Plays at the system's CURRENT volume — chirps are UI feedback, not
/// alarms. Muted system = silent chirps; that's the right tradeoff.
final class ChirpPlayer: @unchecked Sendable {

    private let sampleRate: Double = 48000
    private let channels: Int = 2
    private var graceChirpCount: Int = 0

    // Hold a strong reference to the currently-playing player so it
    // survives across the play() call boundary. AVAudioPlayer needs
    // someone to retain it until it finishes.
    private var inflight: [AVAudioPlayer] = []
    private let lock = NSLock()

    // MARK: Public chirps

    func playArmChirp() {
        play(tones: [
            Tone(frequency: 660, duration: 0.12),
            Tone(frequency: 880, duration: 0.12),
        ], amplitude: 0.30)
    }

    func playGraceChirp() {
        graceChirpCount += 1
        // Subsequent grace chirps get progressively louder — escalation cue.
        let amp = min(0.25 + Double(graceChirpCount) * 0.10, 0.55)
        play(tones: [Tone(frequency: 700, duration: 0.15)], amplitude: amp)
    }

    func playDisarmChirp() {
        graceChirpCount = 0
        play(tones: [
            Tone(frequency: 880, duration: 0.12),
            Tone(frequency: 660, duration: 0.12),
        ], amplitude: 0.30)
    }

    // MARK: Synth

    private struct Tone {
        let frequency: Double
        let duration: TimeInterval
    }

    private func play(tones: [Tone], amplitude: Double) {
        let pcm = renderPCM(tones: tones, amplitude: amplitude)
        let wav = wrapAsWAV(pcm: pcm)
        do {
            let player = try AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue)
            player.volume = 1.0
            player.prepareToPlay()
            // Retain so it doesn't dealloc mid-playback.
            lock.lock(); inflight.append(player); lock.unlock()
            player.play()
            // Clean up after the chirp finishes — duration + small slack.
            let totalDuration = tones.reduce(0.0) { $0 + $1.duration } + 0.2
            DispatchQueue.global().asyncAfter(deadline: .now() + totalDuration) { [weak self] in
                guard let self = self else { return }
                self.lock.lock()
                self.inflight.removeAll { $0 === player }
                self.lock.unlock()
            }
        } catch {
            NSLog("[ChirpPlayer] AVAudioPlayer init failed: %@", error.localizedDescription)
        }
    }

    /// Generate 16-bit-little-endian interleaved stereo PCM samples for
    /// the requested tones, with a half-sine envelope per tone.
    private func renderPCM(tones: [Tone], amplitude: Double) -> Data {
        var data = Data()
        for tone in tones {
            let frames = Int(tone.duration * sampleRate)
            let omega = 2.0 * .pi * tone.frequency / sampleRate
            for i in 0..<frames {
                let envelope = sin(.pi * Double(i) / Double(frames))   // half-sine attack/release
                let sample16 = Int16(amplitude * envelope * sin(omega * Double(i)) * Double(Int16.max))
                // Interleaved stereo — same sample to both channels.
                var le = sample16.littleEndian
                let bytes = withUnsafeBytes(of: &le) { Data($0) }
                data.append(bytes)   // left
                data.append(bytes)   // right
            }
        }
        return data
    }

    /// Wrap raw 16-bit interleaved stereo PCM in a minimal WAV header
    /// so AVAudioPlayer can decode it from a data blob.
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
        // RIFF header
        header.append("RIFF".data(using: .ascii)!)
        appendLE32(36 + pcmLength)
        header.append("WAVE".data(using: .ascii)!)
        // fmt subchunk
        header.append("fmt ".data(using: .ascii)!)
        appendLE32(16)                     // subchunk size (PCM)
        appendLE16(1)                      // audio format = PCM
        appendLE16(UInt16(channels))
        appendLE32(UInt32(sampleRate))
        appendLE32(byteRate)
        appendLE16(blockAlign)
        appendLE16(bitsPerSample)
        // data subchunk
        header.append("data".data(using: .ascii)!)
        appendLE32(pcmLength)
        var wav = header
        wav.append(pcm)
        return wav
    }
}
