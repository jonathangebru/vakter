import Foundation
import AVFoundation
import AnchorShared

protocol PhotoCapturing {
    /// Begin a capture burst with the given cadence. Calls `done` once
    /// with the final list of filenames written to disk.
    func startBurst(cadence: PhotoCadence, done: @escaping @Sendable ([String]) -> Void)
}

/// Captures photos from the built-in FaceTime camera during an ALARM event.
///
/// Stub for v1 — full implementation arrives week 4. See design.md
/// § Photo capture for the per-mode cadence pattern.
final class PhotoCapture: PhotoCapturing {

    func startBurst(cadence: PhotoCadence, done: @escaping @Sendable ([String]) -> Void) {
        NSLog("[PhotoCapture] would start burst (cadence=%@)", String(describing: cadence))
        // TODO(week-4):
        //  - AVCaptureSession with .photo preset
        //  - AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        //  - AVCapturePhotoOutput, capture at cadence times
        //  - Write JPEGs into AnchorConstants.eventsDirectoryURL/<timestamp>/
        //  - Invoke `done` with the file URLs
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            done([])
        }
    }
}
