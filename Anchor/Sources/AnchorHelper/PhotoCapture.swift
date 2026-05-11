import Foundation
import AVFoundation
import AnchorShared

protocol PhotoCapturing {
    /// Begin a capture burst with the given cadence. Calls `done` once
    /// with the final list of filenames written to disk.
    func startBurst(cadence: PhotoCadence, done: @escaping @Sendable ([String]) -> Void)

    /// Stop any in-flight capture session (called on disarm).
    func stop()
}

/// Captures photos from the built-in FaceTime camera during an ALARM event.
///
/// Cadence patterns (per mode, per design.md):
///   .normal : 3 frames at t=0, t=2, t=5 seconds
///   .burst  : t=0, then every 5 seconds for the first minute (≤13 frames),
///             then every 30 seconds until disarmed
///
/// Frames land in `~/Library/Application Support/Anchor/events/<ts>/`,
/// JPEG at high quality. On disarm we surface the file list to the
/// menubar's Event Log view.
///
/// Permissions:
///   First capture will trigger macOS's camera-permission prompt
///   IF this binary's TCC entry has not previously been granted.
///   Without permission, captures silently fail (we log and `done([])`).
final class PhotoCapture: NSObject, PhotoCapturing, AVCapturePhotoCaptureDelegate, @unchecked Sendable {

    private let session = AVCaptureSession()
    private var output: AVCapturePhotoOutput?
    private let queue = DispatchQueue(label: "app.anchor.mac.photo", qos: .userInitiated)
    private var configured = false

    // Per-burst state.
    private var burstStart = Date()
    private var captureTimer: DispatchSourceTimer?
    private var capturedFilenames: [String] = []
    private var eventDirectory: URL?
    private var done: (@Sendable ([String]) -> Void)?
    private var currentCadence: PhotoCadence = .normal
    private var captureIndex = 0

    // MARK: PhotoCapturing

    func startBurst(cadence: PhotoCadence, done: @escaping @Sendable ([String]) -> Void) {
        queue.async { [self] in
            self.done = done
            self.currentCadence = cadence
            self.captureIndex = 0
            self.capturedFilenames = []
            self.burstStart = Date()

            guard configureSessionIfNeeded() else {
                NSLog("[PhotoCapture] camera unavailable — completing burst with no photos")
                self.done?([])
                self.done = nil
                return
            }

            // Make the events/<ts>/ directory.
            let ts = ISO8601DateFormatter().string(from: self.burstStart)
                .replacingOccurrences(of: ":", with: "-")
            let dir = AnchorConstants.eventsDirectoryURL.appendingPathComponent(ts, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.eventDirectory = dir

            if !self.session.isRunning {
                self.session.startRunning()
            }

            // Schedule frames per cadence.
            self.scheduleCadence()
        }
    }

    func stop() {
        queue.async { [self] in
            self.captureTimer?.cancel()
            self.captureTimer = nil
            if self.session.isRunning {
                self.session.stopRunning()
            }
            if let cb = self.done {
                cb(self.capturedFilenames)
                self.done = nil
            }
        }
    }

    // MARK: Session config

    private func configureSessionIfNeeded() -> Bool {
        if configured { return true }

        // Permission gate. canBeOpened is determined by AVCaptureDevice.
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted {
            NSLog("[PhotoCapture] camera permission %@ — capture disabled",
                  status == .denied ? "denied" : "restricted")
            return false
        }
        // .notDetermined: configure anyway; AVCaptureSession will request when started.

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video) else {
            NSLog("[PhotoCapture] no front-facing camera found")
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            session.sessionPreset = .photo
            if session.canAddInput(input) {
                session.addInput(input)
            }
            let out = AVCapturePhotoOutput()
            if session.canAddOutput(out) {
                session.addOutput(out)
            }
            self.output = out
            session.commitConfiguration()
            configured = true
            NSLog("[PhotoCapture] session configured (device=%@)", device.localizedName)
            return true
        } catch {
            NSLog("[PhotoCapture] input creation failed: %@", error.localizedDescription)
            return false
        }
    }

    // MARK: Cadence scheduling

    private func scheduleCadence() {
        // Compute the time offsets for the current cadence's captures.
        let offsets = self.offsetsForCurrentCadence()
        var remaining = offsets

        let timer = DispatchSource.makeTimerSource(queue: queue)
        // First capture fires at offsets[0]; we then reschedule recursively.
        timer.schedule(deadline: .now() + remaining.first!)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.captureOneFrame()
            remaining.removeFirst()
            if remaining.isEmpty {
                // For .normal we stop after 3 frames. For .burst we continue
                // with the sustained tail (every 30s) until stop() is called.
                if self.currentCadence == .burst {
                    self.captureTimer = self.scheduleSustainedBurst()
                }
                return
            }
            // Reschedule for next offset (relative to start).
            timer.schedule(deadline: .now() + (remaining.first! - offsets[offsets.count - remaining.count - 1]))
        }
        timer.resume()
        self.captureTimer = timer
    }

    private func offsetsForCurrentCadence() -> [TimeInterval] {
        switch currentCadence {
        case .normal:
            return [0.0, 2.0, 5.0]
        case .burst:
            // t=0, 5, 10, 15, … 60 (13 frames). Tail handled separately.
            return stride(from: 0.0, through: 60.0, by: 5.0).map { $0 }
        }
    }

    private func scheduleSustainedBurst() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30.0, repeating: 30.0)
        timer.setEventHandler { [weak self] in
            self?.captureOneFrame()
        }
        timer.resume()
        return timer
    }

    private func captureOneFrame() {
        guard let output = self.output, session.isRunning else { return }
        let settings = AVCapturePhotoSettings()
        // Disable auto-flash so we don't blind anyone (and so we don't make
        // the alarm dramatically less stealthy/menacing).
        if let device = (session.inputs.first as? AVCaptureDeviceInput)?.device,
           device.hasFlash {
            settings.flashMode = .off
        }
        output.capturePhoto(with: settings, delegate: self)
    }

    // MARK: AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error = error {
            NSLog("[PhotoCapture] capture error: %@", error.localizedDescription)
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let dir = eventDirectory else { return }

        captureIndex += 1
        let filename = String(format: "photo-%02d.jpg", captureIndex)
        let url = dir.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: .atomic)
            capturedFilenames.append(filename)
            NSLog("[PhotoCapture] wrote %@ (%.1f KB)", filename, Double(data.count) / 1024.0)
        } catch {
            NSLog("[PhotoCapture] write failed: %@", error.localizedDescription)
        }
    }
}
