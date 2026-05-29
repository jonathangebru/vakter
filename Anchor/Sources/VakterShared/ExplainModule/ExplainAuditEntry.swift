import Foundation

/// One row of the "Show me what you see" audit log.
///
/// Every successful ``ExplainModule/explain(request:)`` call writes
/// one of these to the on-disk audit store (under
/// `~/Library/Application Support/Vakter/explain-audit.json` —
/// path locked in #71). The user can browse the log from
/// Settings → Privacy → LLM History.
///
/// The audit row's purpose is *transparency*, not telemetry. It is
/// never transmitted off the user's Mac. The fields are chosen so a
/// non-technical user can read a row and understand exactly what
/// happened: "On 2026-05-29 at 14:32 the Mail Watch asked the model
/// about an email and the model said it wasn't sure."
///
/// Design notes:
///  - `request` is stored **post-redaction** (same shape that was
///    sent to the model). Anything the redactor stripped never lands
///    on disk. This is enforced at the module level — the audit
///    writer only sees the already-redacted request.
///  - `response` is the full ``ExplainResponse`` including the
///    `.unsure` discriminator. The UI renders the `.unsure(reason:)`
///    cases with a distinct visual treatment so the user can spot
///    "the model declined" without reading prose.
///  - `timestamp` is wall-clock UTC. The UI converts to user's local
///    time on render. We store UTC because audit logs are read on
///    other machines (support, the user's Mac at a different
///    timezone after travel, etc.).
///  - `durationMilliseconds` lets the user spot performance issues
///    in their model setup. Optional because at scaffold time we
///    don't measure it; #69 wires the timing.
///  - `Codable` so the audit-log writer can JSON-encode rows in
///    append-only mode. Hand-rolled `CodingKeys` use lowerCamelCase
///    on the wire to match the existing on-disk JSON conventions
///    elsewhere in `Sources/VakterShared/` (see `EventChain.swift`).
///
/// Implemented further in:
///  - #69 — populates `durationMilliseconds` from the real model call.
///  - #71 — the audit-panel UI consumes this type from disk.
public struct ExplainAuditEntry: Sendable, Codable, Equatable, Identifiable {

    /// Stable per-row identifier so SwiftUI list rendering doesn't
    /// flicker on re-decode. Generated at construction time; persisted.
    public let id: UUID

    /// When the call happened, UTC wall-clock. Converted to local
    /// time only at the UI layer.
    public let timestamp: Date

    /// The exact (already-redacted) request the module forwarded to
    /// the on-device model. Storing this verbatim is the whole
    /// point of the audit log — the user can verify nothing they
    /// didn't expect went into the model.
    public let request: ExplainRequest

    /// What the model produced — including the `.unsure` cases. The
    /// audit log treats `.unsure` as a first-class outcome (matching
    /// the response type's design contract); a row with an `.unsure`
    /// response is just as informative as one with an `.answer`.
    public let response: ExplainResponse

    /// How long the model call took. `nil` at scaffold time;
    /// populated by #69 once the real FoundationModels bridge is wired.
    public let durationMilliseconds: Int?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        request: ExplainRequest,
        response: ExplainResponse,
        durationMilliseconds: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.request = request
        self.response = response
        self.durationMilliseconds = durationMilliseconds
    }
}
