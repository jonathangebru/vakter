import Foundation
@preconcurrency import AVFoundation

/// Plays the short UI confirmation tones — arm chirp, grace chirp,
/// disarm chirp. Each is synthesised on the fly via a brief AVAudioEngine
/// source node so we don't ship any asset files.
///
/// Sound design (calm-protector brand, see openspec/design.md):
///   - Arm chirp:    two warm tones (660 Hz → 880 Hz), 120 ms each, gentle
///   - Grace chirp:  one slightly louder tone (700 Hz), 150 ms, escalates
///                   on each repeat as the grace window counts down
///   - Disarm chirp: two warm tones (880 Hz → 660 Hz), 120 ms each
///
/// All tones use a half-sine envelope (attack + release) so they don't
/// click on start/stop. Amplitude is conservative (~30% peak) — these are
/// confirmation sounds, not alarms.
///
/// Plays at the system's CURRENT volume (we don't force max for chirps;
/// that's only for the actual ALARM). A muted system will not hear chirps;
/// that's the right tradeoff — chirps are UI feedback, not alarms.
final class ChirpPlayer: @unchecked Sendable {

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var graceChirpCount: Int = 0

    init() {
        self.format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    }

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
        // Build a single PCM buffer with all tones concatenated.
        let sampleRate = format.sampleRate
        let totalFrames = AVAudioFrameCount(
            tones.reduce(0) { $0 + $1.duration } * sampleRate
        )
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            return
        }
        buffer.frameLength = totalFrames

        let chanCount = Int(format.channelCount)
        var writeIdx: Int = 0
        for tone in tones {
            let frames = Int(tone.duration * sampleRate)
            let omega = 2.0 * .pi * tone.frequency / sampleRate
            for i in 0..<frames {
                // Half-sine envelope across the whole tone — fade in, fade out.
                let envelope = sin(.pi * Double(i) / Double(frames))
                let sample = Float(amplitude * envelope * sin(omega * Double(i)))
                for ch in 0..<chanCount {
                    buffer.floatChannelData?[ch][writeIdx + i] = sample
                }
            }
            writeIdx += frames
        }

        // Hot-swap the engine for each playback: simplest reliable path,
        // and chirps are infrequent. Cost ~5 ms each — fine.
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            NSLog("[ChirpPlayer] engine start failed: %@", error.localizedDescription)
            return
        }
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()

        // Stop the engine just after the chirp finishes. We don't need a
        // sample-accurate completion callback here — chirps are infrequent
        // and the engine's auto-shutoff timing isn't critical.
        let totalDuration = tones.reduce(0.0) { $0 + $1.duration }
        DispatchQueue.global().asyncAfter(deadline: .now() + totalDuration + 0.1) { [engine] in
            engine.stop()
            engine.detach(player)
        }
    }
}
