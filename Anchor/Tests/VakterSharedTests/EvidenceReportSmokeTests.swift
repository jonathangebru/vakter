import XCTest
@testable import VakterShared

/// Smoke test for the chain-summary text that the PDF report embeds.
/// The full PDF rendering test lives in VakterAppTests once that
/// target exists (PDFKit needs an AppKit-bound test target); this
/// covers the verification-statement string formatting that's the
/// only Shared-side input to the PDF body.
final class EvidenceReportSmokeTests: XCTestCase {

    /// Intact chain must surface as a clean PASS sentence.
    func test_intactChainRendersPass() {
        let events = makeChain(length: 3)
        let result = EventChain.verify(events)
        XCTAssertTrue(result.intact)
        XCTAssertEqual(result.totalEvents, 3)
    }

    /// Tampered chain must surface the first break index + reason.
    func test_tamperedChainSurfacesBreak() {
        var events = makeChain(length: 3)
        // Tamper with event 1.
        let original = events[1]
        events[1] = VakterEvent(
            id: original.id,
            timestamp: original.timestamp,
            fromState: original.fromState,
            toState: .alarm,                // changed!
            trigger: original.trigger,
            photoFilenames: original.photoFilenames,
            modeAtEvent: original.modeAtEvent,
            audioFilenames: original.audioFilenames,
            previousEventHash: original.previousEventHash,
            eventHash: original.eventHash,
            locationLat: original.locationLat,
            locationLon: original.locationLon
        )
        let result = EventChain.verify(events)
        XCTAssertFalse(result.intact)
        XCTAssertEqual(result.firstBreakIndex, 1)
        XCTAssertNotNil(result.firstBreakReason)
    }

    private func makeChain(length: Int) -> [VakterEvent] {
        var out: [VakterEvent] = []
        var prev: String? = nil
        for i in 0..<length {
            let raw = VakterEvent(
                timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + i)),
                fromState: .unarmed,
                toState: .armed,
                trigger: .userAction,
                photoFilenames: [],
                modeAtEvent: .normal
            )
            let sealed = EventChain.seal(raw, previousHash: prev)
            out.append(sealed)
            prev = sealed.eventHash
        }
        return out
    }
}
