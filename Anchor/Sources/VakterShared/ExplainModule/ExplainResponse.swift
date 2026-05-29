import Foundation

/// Typed output of ``ExplainModule/explain(request:)``.
///
/// **The "unsure" state is a first-class value, not an error.** This
/// is the most important shape decision in the module: hallucination
/// is the dominant failure mode of any LLM, and the only honest
/// response to a question the model cannot confidently answer is "I'm
/// not sure." Modelling that as `ExplainResponse.unsure(reason:)` —
/// rather than as a thrown error or a `confidence < threshold` flag
/// inside `.answer` — forces every call site to handle it explicitly.
/// If we made unsure-ness an error, callers would write `try?` and
/// silently drop the model's "I don't know" — exactly the bug we want
/// to make impossible.
///
/// At v1.5 the cases are:
///   - ``answer(text:confidence:)`` — the model gave a usable answer
///     and is at least ``Confidence/medium`` sure of it. The text is
///     already post-processed (trimmed, no model-side markdown
///     scaffolding) so the UI can render it verbatim.
///   - ``unsure(reason:)`` — the model declined to answer or fell
///     below the medium-confidence floor. The `reason` is a stable
///     enum the UI can branch on (`.lowConfidence`, `.refused`,
///     `.outOfScope`) so we can show the right "What now?" affordance
///     without parsing the model's prose.
///
/// `Codable` round-trip is part of the type's contract: ``ExplainAuditEntry``
/// persists responses to disk for the "Show me what you see" panel
/// (#71), and the scaffold tests verify a payload survives a JSON
/// round-trip without losing the `.unsure` discriminator. The
/// `CodingKeys` use string tags rather than numeric ones so the
/// on-disk audit log stays human-readable.
///
/// Implemented further in:
///  - #69 — Apple FoundationModels integration produces values of
///    this type from real model output.
///  - #70 — Confidence schema fleshes out the `Confidence` ladder and
///    the "below medium" rejection rule.
public enum ExplainResponse: Sendable, Equatable {

    /// The model produced an answer with at least medium confidence.
    case answer(text: String, confidence: Confidence)

    /// The model could not confidently answer. The `reason` lets the
    /// UI pick a tailored affordance ("Try rephrasing", "This is
    /// outside what I can see", etc.) without text-matching prose.
    case unsure(reason: UnsureReason)

    /// How sure the model is. The ladder is intentionally coarse —
    /// three steps — because the spec calls for "medium or above"
    /// as the answer gate and a finer ladder invites false precision.
    /// #70 will pin the exact mapping from raw model logprobs (or
    /// whatever signal Apple FM exposes) to these buckets.
    public enum Confidence: String, Sendable, Codable, Equatable, CaseIterable {
        case low
        case medium
        case high
    }

    /// Why the model declined to answer. Stable enum so the UI's
    /// branch logic doesn't depend on parsing model prose. #69/#70 add
    /// cases here as we learn what the on-device model emits in
    /// practice; the case set is deliberately small at scaffold time.
    public enum UnsureReason: String, Sendable, Codable, Equatable, CaseIterable {
        /// Model produced an answer but its confidence was below the
        /// medium-confidence floor. Most common path at v1.5.
        case lowConfidence
        /// Model explicitly refused (e.g. safety policy triggered).
        case refused
        /// The prompt asked about something the Watch domain can't
        /// observe — distinct from `lowConfidence` because the right
        /// UI affordance is "this isn't a question I can answer"
        /// rather than "try rephrasing."
        case outOfScope
    }
}

// MARK: - Codable

/// Hand-rolled `Codable` so the on-disk JSON is human-readable: each
/// case serialises to `{"kind": "answer", ...}` or `{"kind": "unsure",
/// "reason": "lowConfidence"}` rather than Swift's default
/// case-discriminator scheme. The "Show me what you see" panel (#71)
/// will display these audit rows directly, so the wire format needs
/// to be eyeball-friendly.
extension ExplainResponse: Codable {

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case confidence
        case reason
    }

    private enum Kind: String, Codable {
        case answer
        case unsure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .answer:
            let text = try container.decode(String.self, forKey: .text)
            let confidence = try container.decode(
                Confidence.self,
                forKey: .confidence
            )
            self = .answer(text: text, confidence: confidence)
        case .unsure:
            let reason = try container.decode(
                UnsureReason.self,
                forKey: .reason
            )
            self = .unsure(reason: reason)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .answer(text, confidence):
            try container.encode(Kind.answer, forKey: .kind)
            try container.encode(text, forKey: .text)
            try container.encode(confidence, forKey: .confidence)
        case let .unsure(reason):
            try container.encode(Kind.unsure, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        }
    }
}
