import Foundation
import AVFoundation
import VakterShared

protocol AudioCapturing {
    /// Record ambient audio for `duration` seconds into the given event
    /// directory. Calls `done` once with the filename written (or nil on
    /// failure). Subsequent calls during a recording are ignored.
    func captureClip(
        duration: TimeInterval,
        eventDirectory: URL,
        done: @escaping @Sendable (String?) -> Void
    )

    /// Stop any in-flight recording immediately. Called on disarm.
    func stop()
}

/// Captures a short ambient-audio clip during an ALARM event.
///
/// Photos catch a face if the thief is in front of the camera; audio
/// catches *everything else* — voices, names, the room they walked into,
/// the car they got into. The 10-second default is a deliberate tradeoff:
/// long enough to capture a meaningful exchange, short enough that we
/// don't keep the mic warm for an hour after a real theft.
///
/// File format: AAC in an M4A container, mono, 22.05 kHz, 64 kbps. That's
/// ~80 KB per 10-second clip — trivially attachable to an iMessage.
///
/// Permissions:
///   First capture triggers macOS's microphone-permission prompt IF
///   this binary's TCC entry has not previously been granted. Without
///   permission, captures silently fail (we log and `done(nil)`).
final class AudioCapture: NSObject, AudioCapturing, AVAudioRecorderDelegate, @unchecked Sendable {

    private let queue = DispatchQueue(label: "app.vakter.mac.audio-capture", qos: .userInitiated)

    // Per-recording state — guarded by `queue`.
    private var recorder: AVAudioRecorder?
    private var pendingDone: (@Sendable (String?) -> Void)?
    private var pendingFilename: String?
    private var stopTimer: DispatchSourceTimer?

    func captureClip(
        duration: TimeInterval,
        eventDirectory: URL,
        done: @escaping @Sendable (String?) -> Void
    ) {
        queue.async { [self] in
            guard self.recorder == nil else {
                NSLog("[AudioCapture] capture already in flight — ignoring request")
                done(nil)
                return
            }

            // Permission gate. macOS will surface a prompt on first start;
            // we still log explicit denials so debugging is straightforward.
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .denied || status == .restricted {
                NSLog("[AudioCapture] microphone permission %@ — capture disabled",
                      status == .denied ? "denied" : "restricted")
                done(nil)
                return
            }

            try? FileManager.default.createDirectory(
                at: eventDirectory, withIntermediateDirectories: true
            )

            // Filename sequence within an event dir is independent of the
            // photo sequence — each modality counts up from 01.
            let existing = (try? FileManager.default.contentsOfDirectory(atPath: eventDirectory.path)) ?? []
            let next = existing.filter { $0.hasPrefix("audio-") }.count + 1
            let filename = String(format: "audio-%02d.m4a", next)
            let url = eventDirectory.appendingPathComponent(filename)

            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 22_050.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]

            do {
                let r = try AVAudioRecorder(url: url, settings: settings)
                r.delegate = self
                r.isMeteringEnabled = false
                guard r.prepareToRecord() else {
                    NSLog("[AudioCapture] prepareToRecord failed")
                    done(nil)
                    return
                }
                guard r.record(forDuration: duration) else {
                    NSLog("[AudioCapture] record(forDuration:) failed")
                    done(nil)
                    return
                }
                self.recorder = r
                self.pendingDone = done
                self.pendingFilename = filename

                // Belt-and-braces stop timer in case the AVAudioRecorder
                // delegate callback doesn't fire (rare on locked-down
                // systems). Adds 0.5s of slack so we don't fight the
                // recorder's own scheduling.
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + duration + 0.5)
                timer.setEventHandler { [weak self] in
                    self?.forceFinish()
                }
                timer.resume()
                self.stopTimer = timer

                NSLog("[AudioCapture] recording %0.1fs → %@", duration, filename)
            } catch {
                NSLog("[AudioCapture] recorder init failed: %@", error.localizedDescription)
                done(nil)
            }
        }
    }

    func stop() {
        queue.async { [self] in
            self.recorder?.stop()
            self.forceFinish()
        }
    }

    /// Resolve the pending `done` callback exactly once, regardless of
    /// whether the AVAudioRecorder delegate fired or the safety timer did.
    private func forceFinish() {
        stopTimer?.cancel()
        stopTimer = nil
        guard let done = pendingDone else { return }
        let name = pendingFilename
        pendingDone = nil
        pendingFilename = nil
        recorder = nil
        done(name)
    }

    // MARK: AVAudioRecorderDelegate

    func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder, successfully flag: Bool
    ) {
        queue.async { [self] in
            if !flag { NSLog("[AudioCapture] recorder reported failure") }
            self.forceFinish()
        }
    }

    func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder, error: Error?
    ) {
        NSLog("[AudioCapture] encode error: %@",
              error?.localizedDescription ?? "unknown")
        queue.async { [self] in self.forceFinish() }
    }
}
