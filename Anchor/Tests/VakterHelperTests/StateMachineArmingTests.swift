import XCTest
import Foundation
@testable import VakterHelper
import VakterShared

/// Tests covering the three arming-path bug fixes:
///
///   • Bug #2 — the state-machine lock must NOT be held while the
///     privileged auth prompt is up. Verified by issuing a concurrent
///     `snapshot()` call while `sleepDisabler.engage()` is sleeping
///     and checking it returns within a tiny budget.
///
///   • Bug #3 — `runArmDemo()` must engage `SleepGuard` AND
///     `SleepDisabler` (the previous implementation skipped both,
///     leaving demo-armed Macs free to fall asleep mid-grace).
///
///   • Bonus — `pendingArm` deduplication prevents two concurrent
///     arms from both blocking on the auth dialog.
final class StateMachineArmingTests: XCTestCase {

    // MARK: - Bug #2: lock not held during auth

    /// While `sleepDisabler.engage()` is blocking (simulating the
    /// privileged-auth dialog), a concurrent `snapshot()` call must
    /// return without waiting. Pre-fix, both shared `lock`, and the
    /// snapshot would block until the user dismissed the dialog.
    func test_bug2_snapshot_doesNotBlockDuringAuthDialog() async {
        let blockingDisabler = BlockingSleepDisabler(holdFor: .seconds(0.40))
        let sm = makeStateMachine(sleepDisabler: blockingDisabler)

        // Kick off armFromUser on a background queue — it'll spend
        // ~400 ms inside sleepDisabler.engage(). `skipScreenLock` so
        // the test doesn't schedule a real screen-lock side effect
        // (private API is a no-op in xctest, but cheap insurance).
        DispatchQueue.global().async {
            sm.armFromUser(skipScreenLock: true)
        }

        // Give the arm a moment to enter Phase 2 (where it has
        // released the lock and is now blocked inside engage()).
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50 ms

        // Now call snapshot(). Pre-fix this would block ~350 ms.
        // Post-fix it returns in microseconds because Phase 2 is
        // lockless.
        let start = Date()
        _ = sm.snapshot()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.05,
                          "snapshot() blocked for \(elapsed)s — the state-machine lock is being held during the auth dialog (bug #2 regression)")

        // Wait for the arm to settle so the next test starts clean.
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    // MARK: - Bug #2: cancel rolls back

    /// If the user cancels the auth prompt, state must stay .unarmed
    /// and `sleepGuard.release()` must be called.
    func test_bug2_userCancelled_rollsBack() async {
        let sg = SpyingSleepGuard()
        let sd = MockSleepDisabler(result: .userCancelled)
        let sm = makeStateMachine(sleepGuard: sg, sleepDisabler: sd)

        sm.armFromUser(skipScreenLock: true)
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(sm.state, .unarmed, "cancelled arm must leave state at .unarmed")
        XCTAssertEqual(sg.engageCount, 1, "sleepGuard.engage was called in Phase 2")
        XCTAssertEqual(sg.releaseCount, 1, "sleepGuard.release was called to roll back")
    }

    /// Happy path: .engaged → state becomes .armed.
    func test_bug2_engaged_armsSuccessfully() async {
        let sd = MockSleepDisabler(result: .engaged)
        let sm = makeStateMachine(sleepDisabler: sd)

        sm.armFromUser(skipScreenLock: true)  // skip screen-lock side effect in tests
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(sm.state, .armed)
        XCTAssertEqual(sd.engageCount, 1)
    }

    // MARK: - Bug #3: runArmDemo engages sleep guards

    /// The whole point of bug #3: pre-fix, `runArmDemo()` skipped
    /// `sleepGuard.engage()` and `sleepDisabler.engage()` entirely.
    /// Demo-armed Macs would fall asleep mid-grace.
    func test_bug3_runArmDemo_engagesSleepGuards() async {
        let sg = SpyingSleepGuard()
        let sd = MockSleepDisabler(result: .engaged)
        let sm = makeStateMachine(sleepGuard: sg, sleepDisabler: sd)

        sm.runArmDemo()
        // Give Phase 2 + Phase 3 a moment to settle.
        try? await Task.sleep(nanoseconds: 60_000_000)

        XCTAssertEqual(sg.engageCount, 1,
                       "runArmDemo must call sleepGuard.engage() (bug #3 regression)")
        XCTAssertEqual(sd.engageCount, 1,
                       "runArmDemo must call sleepDisabler.engage() (bug #3 regression)")
        XCTAssertEqual(sm.state, .armed,
                       "runArmDemo should transition to .armed after engaging sleep blockers")
    }

    /// Demo arm should still respect a user cancellation: state stays
    /// .unarmed and the deferred lid-close signal is a no-op.
    func test_bug3_runArmDemo_userCancelled_doesNotArm() async {
        let sg = SpyingSleepGuard()
        let sd = MockSleepDisabler(result: .userCancelled)
        let sm = makeStateMachine(sleepGuard: sg, sleepDisabler: sd)

        sm.runArmDemo()
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(sm.state, .unarmed,
                       "cancelled demo arm must stay .unarmed")
        XCTAssertEqual(sg.releaseCount, 1,
                       "cancelled demo arm must roll back the sleep guard")

        // Wait past the demo's 1 s lid-close dispatch and confirm
        // state is STILL .unarmed (lid-close on .unarmed is a no-op).
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertEqual(sm.state, .unarmed)
    }

    // MARK: - Bonus: pendingArm deduplication

    /// Two concurrent armFromUser calls must result in exactly one
    /// arm — the second is rejected by the `pendingArm` guard.
    func test_concurrentArms_dedupViaPendingArm() async {
        let blockingDisabler = BlockingSleepDisabler(holdFor: .seconds(0.20))
        let sm = makeStateMachine(sleepDisabler: blockingDisabler)

        DispatchQueue.global().async { sm.armFromUser(skipScreenLock: true) }
        DispatchQueue.global().async { sm.armFromUser(skipScreenLock: true) }

        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(blockingDisabler.engageCount, 1,
                       "two concurrent arms must engage the disabler exactly once")
        XCTAssertEqual(sm.state, .armed)
    }

    // MARK: - Plumbing

    private func makeStateMachine(
        sleepGuard: SleepGuarding = NoopSleepGuard(),
        sleepDisabler: SleepDisabling = MockSleepDisabler(result: .engaged)
    ) -> StateMachine {
        // Pin the event log to a tmp file so tests don't pollute
        // the user's real Vakter event log.
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("VakterTests-\(UUID().uuidString).jsonl")
        let log = EventLogStore(url: tmpURL)

        return StateMachine(
            audio: NoopAudio(),
            photos: NoopPhotos(),
            audioCapture: NoopAudioCapture(),
            log: log,
            sleepGuard: sleepGuard,
            sleepDisabler: sleepDisabler
        )
    }
}

// MARK: - Test doubles

/// SleepGuard double that just counts calls. Engage always succeeds.
private final class SpyingSleepGuard: SleepGuarding, @unchecked Sendable {
    private let lock = NSLock()
    private var _engageCount = 0
    private var _releaseCount = 0
    var engageCount: Int { lock.lock(); defer { lock.unlock() }; return _engageCount }
    var releaseCount: Int { lock.lock(); defer { lock.unlock() }; return _releaseCount }

    func engage() -> Bool {
        lock.lock(); defer { lock.unlock() }
        _engageCount += 1
        return true
    }
    func release() {
        lock.lock(); defer { lock.unlock() }
        _releaseCount += 1
    }
}

/// SleepGuard double for tests that don't care about counts.
private final class NoopSleepGuard: SleepGuarding {
    func engage() -> Bool { true }
    func release() {}
}

/// Returns a configured `SleepDisablerResult` immediately. Counts calls.
private final class MockSleepDisabler: SleepDisabling, @unchecked Sendable {
    let result: SleepDisablerResult
    private let lock = NSLock()
    private var _engageCount = 0
    var engageCount: Int { lock.lock(); defer { lock.unlock() }; return _engageCount }

    init(result: SleepDisablerResult) { self.result = result }

    func engage() -> SleepDisablerResult {
        lock.lock(); defer { lock.unlock() }
        _engageCount += 1
        return result
    }
    func release() {}
}

/// Blocks for a configured duration inside engage() to simulate
/// the privileged-auth dialog. Used to exercise bug #2.
private final class BlockingSleepDisabler: SleepDisabling, @unchecked Sendable {
    let holdFor: DispatchTimeInterval
    private let lock = NSLock()
    private var _engageCount = 0
    var engageCount: Int { lock.lock(); defer { lock.unlock() }; return _engageCount }

    init(holdFor: DispatchTimeInterval) { self.holdFor = holdFor }

    func engage() -> SleepDisablerResult {
        lock.lock(); _engageCount += 1; lock.unlock()
        let sem = DispatchSemaphore(value: 0)
        _ = sem.wait(timeout: .now() + holdFor)
        return .engaged
    }
    func release() {}
}

/// Audio test double — every call is a no-op.
private final class NoopAudio: AudioControlling {
    func playArmChirp() {}
    func playGraceChirp() {}
    func playDisarmChirp() {}
    func startAlarm(audible: Bool) {}
    func startAlarm(audible: Bool, cap: TimeInterval?) {}
    func stopAlarm() {}
    func playTestAlarm(duration: TimeInterval) {}
}

/// Photos test double — every call is a no-op.
private final class NoopPhotos: PhotoCapturing {
    func startBurst(cadence: PhotoCadence, done: @escaping @Sendable ([String]) -> Void) {
        done([])
    }
    func stop() {}
}

/// Audio-capture test double — every call returns nil immediately.
private final class NoopAudioCapture: AudioCapturing {
    func captureClip(
        duration: TimeInterval,
        eventDirectory: URL,
        done: @escaping @Sendable (String?) -> Void
    ) {
        done(nil)
    }
    func stop() {}
}

private extension DispatchTimeInterval {
    static func seconds(_ s: Double) -> DispatchTimeInterval {
        .milliseconds(Int(s * 1000))
    }
}
