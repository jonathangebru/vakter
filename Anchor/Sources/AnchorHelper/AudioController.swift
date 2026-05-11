import Foundation
import CoreAudio
import AVFoundation
import AnchorShared

/// Protocol the state machine talks to (lets us inject a test double).
protocol AudioControlling {
    func playArmChirp()
    func playGraceChirp()
    func playDisarmChirp()
    func startAlarm(audible: Bool)
    func stopAlarm()
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
final class AudioController: AudioControlling {

    private let engine = AVAudioEngine()
    private let synth = AVSpeechSynthesizer()
    private let chirps = ChirpPlayer()

    // Saved-state snapshot so we restore exactly what the user had.
    private struct Snapshot {
        let volume: Float32
        let muted: UInt32
    }
    private var snapshot: Snapshot?

    private var isPlayingAlarm = false
    private var voiceTimer: DispatchSourceTimer?

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
        guard !isPlayingAlarm else { return }
        isPlayingAlarm = true

        if audible {
            snapshotSystemAudio()
            forceMaxOutput()
            startSiren()
            startVoiceCueLoop()
        } else {
            // Library-mode-equivalent: skip siren; just play the elevated chirp
            // pattern (TODO) so it's audible but not blaring.
            NSLog("[Audio] alarm started (inaudible mode)")
        }
    }

    func stopAlarm() {
        guard isPlayingAlarm else { return }
        isPlayingAlarm = false
        voiceTimer?.cancel(); voiceTimer = nil
        synth.stopSpeaking(at: .immediate)
        if engine.isRunning { engine.stop() }
        restoreSystemAudio()
        NSLog("[Audio] alarm stopped")
    }

    // MARK: System audio override (CoreAudio)

    private func snapshotSystemAudio() {
        guard let dev = defaultOutputDevice() else { return }
        var vol: Float32 = 0
        var mute: UInt32 = 0
        _ = readFloat32(dev, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, &vol)
        _ = readUInt32(dev, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, &mute)
        snapshot = Snapshot(volume: vol, muted: mute)
        NSLog("[Audio] snapshot: vol=%.2f mute=%u", vol, mute)
    }

    private func forceMaxOutput() {
        guard let dev = defaultOutputDevice() else { return }
        _ = writeUInt32(dev, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, 0)
        _ = writeFloat32(dev, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, 1.0)
        // TODO(week-4): if non-internal device is default, switch to internal
        // speakers via kAudioHardwarePropertyDefaultOutputDevice.
    }

    private func restoreSystemAudio() {
        guard let snap = snapshot, let dev = defaultOutputDevice() else { return }
        _ = writeFloat32(dev, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, snap.volume)
        _ = writeUInt32(dev, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, snap.muted)
        snapshot = nil
    }

    // MARK: Siren

    private func startSiren() {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        var phase = 0.0
        let freq = 880.0
        let twoPi = 2.0 * .pi

        let src = AVAudioSourceNode(format: fmt) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buf in buffers {
                guard let ptr = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
                var local = phase
                for i in 0..<Int(frameCount) {
                    ptr[i] = Float(sin(local)) * 0.6
                    local += twoPi * freq / 48000
                    if local > twoPi { local -= twoPi }
                }
                phase = local
            }
            return noErr
        }

        engine.attach(src)
        engine.connect(src, to: engine.mainMixerNode, format: fmt)
        do {
            try engine.start()
            NSLog("[Audio] siren started")
        } catch {
            NSLog("[Audio] engine start FAILED: %@", error.localizedDescription)
        }
    }

    // MARK: Voice cue

    private func startVoiceCueLoop() {
        let utterance: () -> Void = { [weak self] in
            guard let self = self, self.isPlayingAlarm else { return }
            let phrase = AVSpeechUtterance(string: "This MacBook is being tracked. Please put it down.")
            phrase.voice = AVSpeechSynthesisVoice(language: "en-US")
            phrase.volume = 1.0
            phrase.rate = AVSpeechUtteranceDefaultSpeechRate
            self.synth.speak(phrase)
        }

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
