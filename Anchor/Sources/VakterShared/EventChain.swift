import Foundation
import CryptoKit

/// Tamper-evident event-log chain.
///
/// Every `VakterEvent` published by the state machine carries:
///   - `previousEventHash` — the `eventHash` of the previous event in the
///      log, or `nil` for the first event in a chain
///   - `eventHash` — SHA-256 over the canonical encoding of *this* event's
///      content (everything except `eventHash` itself)
///
/// To verify the chain, walk the log oldest→newest:
///   1. Recompute each event's canonical encoding
///   2. Hash it and compare against `eventHash`
///   3. Compare each event's `previousEventHash` against the prior event's
///      stored `eventHash`
///
/// If any byte of any event is modified — content tampered, ordering
/// shuffled, an event deleted — the chain breaks visibly. The hash chain
/// doesn't *prevent* tampering (the log file is still on a disk the thief
/// might control once they're past authentication), but it does *prove*
/// tampering to a third party like an insurance adjuster or law-enforcement
/// officer reading the exported PDF report.
///
/// Hashing is SHA-256 (CryptoKit). Output is rendered as lowercase hex so
/// the chain links survive a JSON round-trip cleanly.
public enum EventChain {

    /// Compute the canonical hash for one event. Pass `eventBeingHashed`
    /// with `eventHash = nil` (the field we're computing) and the desired
    /// `previousEventHash` already set.
    public static func hash(for event: VakterEvent) -> String {
        // Canonical encoding: JSON with sorted keys + ISO8601 dates. Same
        // settings as `EventLogStore` so the on-disk representation and
        // the in-memory hash agree.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        // Hash the event with `eventHash` explicitly nilled out — that's
        // the field we're computing, including it would be self-referential.
        let canonical = VakterEvent(
            id: event.id,
            timestamp: event.timestamp,
            fromState: event.fromState,
            toState: event.toState,
            trigger: event.trigger,
            photoFilenames: event.photoFilenames,
            modeAtEvent: event.modeAtEvent,
            audioFilenames: event.audioFilenames,
            previousEventHash: event.previousEventHash,
            eventHash: nil,
            locationLat: event.locationLat,
            locationLon: event.locationLon
        )

        guard let bytes = try? encoder.encode(canonical) else {
            return ""
        }
        let digest = SHA256.hash(data: bytes)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Stamp an event with its chain links.
    ///
    /// - Parameters:
    ///   - event: the event to seal (with `previousEventHash`/`eventHash`
    ///     left nil by the caller)
    ///   - previousHash: the `eventHash` of the previous event in the log,
    ///     or nil if this is the first event in the chain
    /// - Returns: a new event with both hash fields populated
    public static func seal(_ event: VakterEvent, previousHash: String?) -> VakterEvent {
        let prepared = VakterEvent(
            id: event.id,
            timestamp: event.timestamp,
            fromState: event.fromState,
            toState: event.toState,
            trigger: event.trigger,
            photoFilenames: event.photoFilenames,
            modeAtEvent: event.modeAtEvent,
            audioFilenames: event.audioFilenames,
            previousEventHash: previousHash,
            eventHash: nil,
            locationLat: event.locationLat,
            locationLon: event.locationLon
        )
        let h = hash(for: prepared)
        return VakterEvent(
            id: prepared.id,
            timestamp: prepared.timestamp,
            fromState: prepared.fromState,
            toState: prepared.toState,
            trigger: prepared.trigger,
            photoFilenames: prepared.photoFilenames,
            modeAtEvent: prepared.modeAtEvent,
            audioFilenames: prepared.audioFilenames,
            previousEventHash: prepared.previousEventHash,
            eventHash: h,
            locationLat: prepared.locationLat,
            locationLon: prepared.locationLon
        )
    }

    /// Result of verifying a sequence of events.
    public struct VerificationResult: Equatable, Sendable {
        public let intact: Bool
        public let totalEvents: Int
        public let firstBreakIndex: Int?
        public let firstBreakReason: String?

        public static let empty = VerificationResult(
            intact: true, totalEvents: 0,
            firstBreakIndex: nil, firstBreakReason: nil
        )
    }

    /// Verify a chain. `events` should be in chronological order (oldest first).
    /// Skips events that have nil `eventHash` (pre-v1.3 entries on disk) —
    /// those are surfaced as "not in chain" but don't break verification of
    /// the v1.3-and-later tail.
    public static func verify(_ events: [VakterEvent]) -> VerificationResult {
        guard !events.isEmpty else { return .empty }

        var previousHash: String? = nil
        var seenFirstChainedEvent = false

        for (index, event) in events.enumerated() {
            // Skip pre-chain events (v1.2 and earlier).
            guard event.eventHash != nil else { continue }

            // Recompute the hash for this event.
            let recomputed = hash(for: event)
            if recomputed != event.eventHash {
                return VerificationResult(
                    intact: false,
                    totalEvents: events.count,
                    firstBreakIndex: index,
                    firstBreakReason: "event \(index) hash mismatch — content tampered"
                )
            }

            // Verify the link to the previous chained event.
            if seenFirstChainedEvent {
                if event.previousEventHash != previousHash {
                    return VerificationResult(
                        intact: false,
                        totalEvents: events.count,
                        firstBreakIndex: index,
                        firstBreakReason: "event \(index) previousEventHash mismatch — ordering or deletion tampered"
                    )
                }
            } else {
                seenFirstChainedEvent = true
            }

            previousHash = event.eventHash
        }

        return VerificationResult(
            intact: true,
            totalEvents: events.count,
            firstBreakIndex: nil,
            firstBreakReason: nil
        )
    }
}
