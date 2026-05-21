import XCTest
@testable import VakterShared

/// Tests for the `AckGate` single-claim primitive that powers the
/// `HelperClient.testAlarm()` race fix (bug #1).
///
/// The bug was: two racing callbacks (XPC ack on a bg queue, 1.0 s
/// fallback on main) both observed `var didAck = false` and both
/// fired the alarm. With `AckGate` only one path wins.
@MainActor
final class AckGateTests: XCTestCase {

    /// Basic semantics: first claim wins, second claim loses.
    func test_firstClaimWins_secondClaimLoses() {
        let gate = AckGate()
        XCTAssertTrue(gate.claim(), "first claim must win")
        XCTAssertFalse(gate.claim(), "second claim must lose")
        XCTAssertFalse(gate.claim(), "third claim must lose")
    }

    /// `isClaimed` reflects the gate state.
    func test_isClaimedReflectsState() {
        let gate = AckGate()
        XCTAssertFalse(gate.isClaimed)
        _ = gate.claim()
        XCTAssertTrue(gate.isClaimed)
    }

    /// Two racing async tasks both call claim(); exactly one wins.
    /// Repeats the race 200 times to shake out scheduling variation.
    func test_concurrentRace_exactlyOneWinner() async {
        for _ in 0..<200 {
            let gate = AckGate()

            // Race two tasks. Both hop onto @MainActor (gate requires it).
            async let a: Bool = MainActor.run { gate.claim() }
            async let b: Bool = MainActor.run { gate.claim() }
            let (aWon, bWon) = await (a, b)

            // Exactly one of them must be true.
            XCTAssertTrue(aWon != bWon,
                          "exactly one of the two racing claims must win — got a=\(aWon) b=\(bWon)")
        }
    }

    /// Simulates the actual testAlarm bug scenario: XPC-style "fast ack"
    /// arrives ~0 ms after the call, fallback timeout fires at +1 s.
    /// With AckGate the fallback observes the gate as already claimed
    /// and bails — no double-fire.
    func test_simulatedXpcAckBeatsTimeout() async {
        let gate = AckGate()
        var ackFired = false
        var fallbackFired = false

        // "XPC ack" arrives immediately.
        if gate.claim() {
            ackFired = true
        }

        // "Timeout" fires later.
        try? await Task.sleep(nanoseconds: 10_000_000)  // 10 ms
        if gate.claim() {
            fallbackFired = true
        }

        XCTAssertTrue(ackFired)
        XCTAssertFalse(fallbackFired, "fallback must not fire after XPC ack already claimed")
    }

    /// Reverse: helper is unreachable, the timeout wins.
    func test_simulatedTimeoutBeatsLateAck() async {
        let gate = AckGate()
        var fallbackFired = false
        var lateAckFired = false

        // Timeout fires first.
        if gate.claim() {
            fallbackFired = true
        }

        // Late XPC ack arrives after.
        try? await Task.sleep(nanoseconds: 10_000_000)
        if gate.claim() {
            lateAckFired = true
        }

        XCTAssertTrue(fallbackFired)
        XCTAssertFalse(lateAckFired, "late ack must not fire after fallback already claimed")
    }
}
