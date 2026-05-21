import Foundation
import CoreLocation
import VakterShared

/// Assembles a fresh `EvidenceBundle` at alarm time and (optionally)
/// kicks off off-Mac delivery via `iMessageEvidenceDelivery`. Lives
/// in VakterHelper because it needs `LocationProbe` (CoreLocation
/// runloop) and access to the events directory layout.
///
/// **Flow on alarm trigger:**
///   1. State machine transitions to `.alarm`.
///   2. PhotoCapture starts its burst, writing JPEGs into
///      `<eventsDir>/<ISO-ts>/photo-NN.jpg`.
///   3. `EvidenceBundleBuilder.fireAndForget(...)` is dispatched on a
///      background queue. It waits ~3 s for the first 2 photos to land,
///      probes location (10 s timeout), reads DefensesProbe snapshot,
///      builds the bundle, and hands off to the delivery layer.
///   4. If `EvidenceRecipientStore.load()` is nil (no recipient set),
///      we skip delivery. Photos still land locally.
///
/// **Why fire-and-forget?** The state machine must NOT block on
/// network / CoreLocation. The alarm continues firing regardless of
/// whether the iMessage delivers.
final class EvidenceBundleBuilder: @unchecked Sendable {

    private let delivery: EvidenceDelivering
    private let locationProbe: LocationProbe

    init(delivery: EvidenceDelivering = iMessageEvidenceDelivery(),
         locationProbe: LocationProbe = .shared) {
        self.delivery = delivery
        self.locationProbe = locationProbe
    }

    /// Build + deliver. Fire-and-forget — caller doesn't await.
    func fireAndForget(trigger: VakterTrigger?,
                       mode: VakterMode,
                       eventTimestamp: Date,
                       eventDirectory: URL) {
        Task.detached(priority: .utility) { [weak self] in
            await self?.run(trigger: trigger,
                            mode: mode,
                            eventTimestamp: eventTimestamp,
                            eventDirectory: eventDirectory)
        }
    }

    /// Async core. Public so tests can await it.
    func run(trigger: VakterTrigger?,
             mode: VakterMode,
             eventTimestamp: Date,
             eventDirectory: URL) async {
        // Gate on recipient — no point doing the work otherwise.
        guard let recipient = EvidenceRecipientStore.load() else {
            NSLog("[EvidenceBundle] no recipient configured — skipping delivery")
            return
        }

        // Give PhotoCapture ~3 s to land at least the first frame.
        // Cafe-mode burst captures at t=0 and t=2, so 3 s catches both.
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        let photos = collectPhotos(from: eventDirectory)
        let snapshot = DefensesProbe.snapshot()
        // (defensesSnapshot is included in the zip-form bundle but not
        // in the iMessage body — too noisy to read on a phone.)
        let zipURL = writeDefensesJSON(snapshot, into: eventDirectory)
        _ = zipURL // future: attach zip; for now just inline the photos.

        // Location: fresh probe with 10 s timeout, fallback to cache.
        let freshLocation = await locationProbe.currentCoordinate()
        let cachedLocation = locationProbe.lastKnown()

        let reasonLine = reasonText(for: trigger)

        let bundle = EvidenceBundle(
            timestamp: eventTimestamp,
            reasonLine: reasonLine,
            mode: mode,
            photoURLs: photos,
            location: freshLocation,
            lastKnownLocation: freshLocation == nil ? cachedLocation?.0 : nil,
            lastKnownLocationAge: freshLocation == nil ? cachedLocation?.1 : nil,
            locale: .current
        )

        NSLog("[EvidenceBundle] delivering — %d photos, location=%@",
              photos.count,
              freshLocation == nil ? "cached/none" : "fresh")

        let result = await delivery.deliver(bundle, to: recipient)
        switch result {
        case .success:
            NSLog("[EvidenceBundle] iMessage handoff ok")
        case .failure(let err):
            NSLog("[EvidenceBundle] delivery FAILED: %@", err.localizedDescription)
        }

        // v1.4: parallel cloud upload. Survives a wipe — the evidence is
        // already off-device by the time the thief gets past Vakter's
        // auth wall. No-op if the user hasn't configured a bucket.
        await uploadToCloud(
            eventDirectory: eventDirectory,
            eventTimestamp: eventTimestamp
        )
    }

    /// Uploads everything in the per-alarm event directory to the user's
    /// cloud bucket. Fire-and-forget — silently no-ops if there's no
    /// configured bucket (the common case for non-paranoid users).
    private func uploadToCloud(eventDirectory: URL, eventTimestamp: Date) async {
        guard let config = CloudEvidenceConfig.load() else { return }

        // Sub-folder under the bucket so each incident is self-contained.
        // Format: `vakter/<iso-timestamp>/`. The same prefix is used by
        // the live web dashboard view (v1.4 follow-on) to enumerate
        // an incident's contents from one URL.
        let ts = ISO8601DateFormatter().string(from: eventTimestamp)
            .replacingOccurrences(of: ":", with: "-")
        let prefix = "vakter/\(ts)"

        let files = (try? FileManager.default.contentsOfDirectory(
            at: eventDirectory, includingPropertiesForKeys: nil
        )) ?? []

        var successCount = 0
        for url in files {
            let result = await CloudEvidenceUpload.upload(
                fileURL: url,
                keyPrefix: prefix,
                config: config
            )
            switch result {
            case .success:
                successCount += 1
            case .failure(let err):
                NSLog("[CloudUpload] %@ → %@",
                      url.lastPathComponent, err.localizedDescription)
            }
        }
        NSLog("[CloudUpload] %d/%d files uploaded to %@ bucket=%@ prefix=%@",
              successCount, files.count, config.provider.rawValue,
              config.bucket, prefix)
    }

    // MARK: - Helpers

    private func collectPhotos(from dir: URL) -> [URL] {
        guard let items = try? FileManager.default
                .contentsOfDirectory(at: dir,
                                     includingPropertiesForKeys: nil)
        else { return [] }
        return items
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            // Send at most 4 photos via iMessage — more = throttling risk.
            .prefix(4)
            .map { $0 }
    }

    private func writeDefensesJSON(_ snapshot: DefensesSnapshot,
                                   into dir: URL) -> URL? {
        let url = dir.appendingPathComponent("defenses.json")
        guard let data = try? JSONEncoder().encode(snapshot) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        return url
    }

    private func reasonText(for trigger: VakterTrigger?) -> String {
        switch trigger {
        case .findMyCleared:
            return LocalePhrases.text(.findMyClearedReason)
        case .appleIDChanged:
            return LocalePhrases.text(.appleIDChangedReason)
        default:
            // Generic — the timestamp + photos carry the rest of the
            // story. We don't try to translate every trigger because
            // the localised text table would balloon.
            return LocalePhrases.text(.evidenceMessageHeader)
        }
    }
}
