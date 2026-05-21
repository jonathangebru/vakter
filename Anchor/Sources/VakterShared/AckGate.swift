import Foundation

/// Single-claim gate for deduplicating two racing callbacks.
///
/// Common pattern: an XPC reply may arrive on a background queue, and
/// a timeout fallback may fire on the main queue. Both want to run
/// "the work" — but only once. `AckGate` lets the first caller claim
/// the work; the loser observes `claim() == false` and bails.
///
/// All access is hopped onto `@MainActor`, so the gate itself doesn't
/// need a lock — Swift's actor isolation guarantees serial access.
/// Final + reference type so the same instance is shared by both
/// callbacks; value-type semantics would defeat the gate.
///
/// Originally introduced for `HelperClient.testAlarm()` to fix a
/// data race where both the XPC ack and the 1.0 s fallback timeout
/// would observe `didAck == false` and both fire the alarm.
@MainActor
public final class AckGate {

    private var claimed = false

    public init() {}

    /// Returns `true` the first time it's called, `false` on every
    /// subsequent call. Idempotent.
    @discardableResult
    public func claim() -> Bool {
        if claimed { return false }
        claimed = true
        return true
    }

    /// Whether the gate has been claimed. Read-only diagnostic.
    public var isClaimed: Bool { claimed }
}
