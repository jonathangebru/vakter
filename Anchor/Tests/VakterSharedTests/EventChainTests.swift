import XCTest
@testable import VakterShared

/// Verifies the tamper-evident event-log chain.
///
/// The contract:
///   - `seal()` produces a deterministic hash for identical inputs
///   - `verify()` returns `intact` on an honest chain
///   - mutating ANY content field of ANY event breaks verification
///   - reordering events breaks verification
///   - deleting an event breaks verification
///   - pre-v1.3 events (no `eventHash`) are gracefully skipped
final class EventChainTests: XCTestCase {

    // Convenience: a fresh, hash-free event for a given step in a sequence.
    private func makeEvent(step: Int) -> VakterEvent {
        VakterEvent(
            timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + step)),
            fromState: .unarmed,
            toState: step.isMultiple(of: 2) ? .armed : .alarm,
            trigger: .userAction,
            photoFilenames: ["photo-0\(step).jpg"],
            modeAtEvent: .normal,
            audioFilenames: nil,
            previousEventHash: nil,
            eventHash: nil,
            locationLat: nil,
            locationLon: nil
        )
    }

    func test_hash_isDeterministic() {
        let e = makeEvent(step: 1)
        let h1 = EventChain.hash(for: e)
        let h2 = EventChain.hash(for: e)
        XCTAssertFalse(h1.isEmpty)
        XCTAssertEqual(h1, h2)
        // SHA-256 hex = 64 chars.
        XCTAssertEqual(h1.count, 64)
    }

    func test_seal_populatesBothChainFields() {
        let raw = makeEvent(step: 1)
        let sealed = EventChain.seal(raw, previousHash: "prev-hash-abc")
        XCTAssertEqual(sealed.previousEventHash, "prev-hash-abc")
        XCTAssertNotNil(sealed.eventHash)
        XCTAssertEqual(sealed.eventHash?.count, 64)
        // ID, timestamp, content all unchanged.
        XCTAssertEqual(sealed.id, raw.id)
        XCTAssertEqual(sealed.timestamp, raw.timestamp)
    }

    func test_verify_intactChain() {
        var events: [VakterEvent] = []
        var prev: String? = nil
        for i in 0..<5 {
            let sealed = EventChain.seal(makeEvent(step: i), previousHash: prev)
            events.append(sealed)
            prev = sealed.eventHash
        }
        let result = EventChain.verify(events)
        XCTAssertTrue(result.intact)
        XCTAssertEqual(result.totalEvents, 5)
        XCTAssertNil(result.firstBreakIndex)
    }

    func test_verify_detectsContentMutation() {
        var events: [VakterEvent] = []
        var prev: String? = nil
        for i in 0..<5 {
            let sealed = EventChain.seal(makeEvent(step: i), previousHash: prev)
            events.append(sealed)
            prev = sealed.eventHash
        }
        // Tamper with the photos on event 2 (mutation should be detected).
        let original = events[2]
        events[2] = VakterEvent(
            id: original.id,
            timestamp: original.timestamp,
            fromState: original.fromState,
            toState: original.toState,
            trigger: original.trigger,
            photoFilenames: ["tampered.jpg"],
            modeAtEvent: original.modeAtEvent,
            audioFilenames: original.audioFilenames,
            previousEventHash: original.previousEventHash,
            eventHash: original.eventHash,        // keep stale hash
            locationLat: original.locationLat,
            locationLon: original.locationLon
        )
        let result = EventChain.verify(events)
        XCTAssertFalse(result.intact)
        XCTAssertEqual(result.firstBreakIndex, 2)
        XCTAssertTrue(result.firstBreakReason?.contains("hash mismatch") == true)
    }

    func test_verify_detectsReordering() {
        var events: [VakterEvent] = []
        var prev: String? = nil
        for i in 0..<5 {
            let sealed = EventChain.seal(makeEvent(step: i), previousHash: prev)
            events.append(sealed)
            prev = sealed.eventHash
        }
        // Swap events 1 and 2 — content hashes still match each event,
        // but the previousEventHash links are now inconsistent.
        events.swapAt(1, 2)
        let result = EventChain.verify(events)
        XCTAssertFalse(result.intact)
        // The break should be detected at index 1 (the first link that
        // points at the wrong previous hash).
        XCTAssertEqual(result.firstBreakIndex, 1)
    }

    func test_verify_detectsDeletion() {
        var events: [VakterEvent] = []
        var prev: String? = nil
        for i in 0..<5 {
            let sealed = EventChain.seal(makeEvent(step: i), previousHash: prev)
            events.append(sealed)
            prev = sealed.eventHash
        }
        // Remove event 2. Events 0, 1 still link correctly. Event 3's
        // previousEventHash now points at event 1's stored hash, but
        // its `previousEventHash` actually still records event 2's hash
        // — so the link breaks at index 2 (the now-event-3).
        events.remove(at: 2)
        let result = EventChain.verify(events)
        XCTAssertFalse(result.intact)
        XCTAssertEqual(result.firstBreakIndex, 2)
    }

    func test_verify_skipsPreV13Events() {
        // Mixed chain: 2 pre-v1.3 events (no hashes) followed by 3
        // chained events. Verification should pass cleanly.
        let preChain: [VakterEvent] = (0..<2).map { i in
            VakterEvent(
                fromState: .unarmed, toState: .armed,
                trigger: .userAction, modeAtEvent: .normal
            )
        }
        var chained: [VakterEvent] = []
        var prev: String? = nil
        for i in 2..<5 {
            let sealed = EventChain.seal(makeEvent(step: i), previousHash: prev)
            chained.append(sealed)
            prev = sealed.eventHash
        }
        let result = EventChain.verify(preChain + chained)
        XCTAssertTrue(result.intact)
        XCTAssertEqual(result.totalEvents, 5)
    }

    func test_verify_emptyLog() {
        let result = EventChain.verify([])
        XCTAssertTrue(result.intact)
        XCTAssertEqual(result.totalEvents, 0)
    }
}
