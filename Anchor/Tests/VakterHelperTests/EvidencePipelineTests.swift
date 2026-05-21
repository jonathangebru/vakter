import XCTest
import Foundation
@testable import VakterHelper
import VakterShared

/// End-to-end test of v1.3 evidence-pipeline wiring:
///   1. An `.alarm` transition seals an event into the Merkle chain
///   2. The async photo + audio capture callbacks each add an
///      appendix event whose `previousEventHash` links back to the
///      primary alarm event
///   3. `snapshot.lastEvent` exposes the most recent event
///   4. The full chain verifies clean via `EventChain.verify`
final class EvidencePipelineTests: XCTestCase {

    func test_alarmFires_writesChainedEventsWithEvidence() async {
        let photoMock = RecordedPhotos(filenames: ["photo-01.jpg", "photo-02.jpg"])
        let audioMock = RecordedAudioCapture(filename: "audio-01.m4a")
        let log = EventLogStore(url: tmpEventLogURL())

        // Real EvidenceBundleBuilder is fine — it bails out on the
        // recipient-store check in tests (no recipient configured) so
        // there's no side effect to mock around.
        let sm = StateMachine(
            audio: SilentAudio(),
            photos: photoMock,
            audioCapture: audioMock,
            log: log,
            sleepGuard: NoopSleepGuard(),
            sleepDisabler: MockSleepDisabler(result: .engaged)
        )

        // Arm → straight-to-alarm via FindMy-token-cleared (high-
        // confidence theft signal, skips grace entirely).
        sm.armFromUser(skipScreenLock: true)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(sm.state, .armed, "arm should succeed with mocked disabler")

        sm.handle(signal: .findMyTokenCleared)

        // Photo + audio mocks fire `done` on a background queue, so
        // wait briefly for the appendix events to land.
        try? await Task.sleep(nanoseconds: 200_000_000)

        let entries = log.recent(limit: 30).reversed().map { $0 }
        XCTAssertGreaterThanOrEqual(entries.count, 4,
                                    "expected arm + grace + alarm + 2 appendix events")

        // All v1.3 events should have eventHash populated.
        let chained = entries.filter { $0.eventHash != nil }
        XCTAssertGreaterThanOrEqual(chained.count, 4)

        // The chain should verify intact.
        let result = EventChain.verify(entries)
        XCTAssertTrue(result.intact,
                      "chain verify failed at index \(result.firstBreakIndex ?? -1): \(result.firstBreakReason ?? "?")")

        // The snapshot's lastEvent should be the most recent appendix
        // (the audio one, since audioCapture callback fires after the
        // primary alarm event was recorded).
        let snap = sm.snapshot()
        XCTAssertNotNil(snap.lastEvent)
        XCTAssertNotNil(snap.lastEvent?.eventHash)

        // Some appendix should carry the photo filenames and another
        // the audio filename.
        let allPhotos = entries.flatMap { $0.photoFilenames }
        XCTAssertTrue(allPhotos.contains("photo-01.jpg"))
        let allAudio = entries.compactMap { $0.audioFilenames }.flatMap { $0 }
        XCTAssertTrue(allAudio.contains("audio-01.m4a"))
    }

    // MARK: - Helpers

    private func tmpEventLogURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("VakterEvidenceTest-\(UUID().uuidString).jsonl")
    }
}

// MARK: - Test doubles (private to this file)

private final class RecordedPhotos: PhotoCapturing, @unchecked Sendable {
    let filenames: [String]
    init(filenames: [String]) { self.filenames = filenames }
    func startBurst(cadence: PhotoCadence, done: @escaping @Sendable ([String]) -> Void) {
        let fs = filenames
        DispatchQueue.global().async { done(fs) }
    }
    func stop() {}
}

private final class RecordedAudioCapture: AudioCapturing, @unchecked Sendable {
    let filename: String
    init(filename: String) { self.filename = filename }
    func captureClip(
        duration: TimeInterval,
        eventDirectory: URL,
        done: @escaping @Sendable (String?) -> Void
    ) {
        let f = filename
        DispatchQueue.global().async { done(f) }
    }
    func stop() {}
}

private final class SilentAudio: AudioControlling {
    func playArmChirp() {}
    func playGraceChirp() {}
    func playDisarmChirp() {}
    func startAlarm(audible: Bool) {}
    func startAlarm(audible: Bool, cap: TimeInterval?) {}
    func stopAlarm() {}
    func playTestAlarm(duration: TimeInterval) {}
}

private final class NoopSleepGuard: SleepGuarding {
    func engage() -> Bool { true }
    func release() {}
}

private final class MockSleepDisabler: SleepDisabling, @unchecked Sendable {
    let result: SleepDisablerResult
    init(result: SleepDisablerResult) { self.result = result }
    func engage() -> SleepDisablerResult { result }
    func release() {}
}

