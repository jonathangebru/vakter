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
