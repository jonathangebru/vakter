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

    /// How sure the model is. A 5-step Likert scale —
    /// `veryHigh / high / medium / low / veryLow` — chosen over the
    /// scaffold's 3-step ladder because Apple Foundation Models'
    /// scoring (and on-device LMs in general) exposes a roughly
    /// continuous probability signal: 3 buckets collapse too many
    /// distinct calibration regimes (e.g. "0.92" vs "0.68" both
    /// become "high"), and 7+ buckets invite false precision the
    /// underlying model can't actually deliver.
    ///
    /// **Mapping policy (set by ``ExplainResponse/from(answerText:confidence:)``):**
    ///   - `veryHigh`, `high`, `medium` → forwarded as `.answer`.
    ///   - `low`, `veryLow` → coerced to `.unsure(.lowConfidence)`.
    ///     This is the heart of the brand contract: a confident-sounding
    ///     answer with low confidence is exactly the failure mode that
    ///     makes a security product dangerous. We refuse to surface it.
    ///
    /// **Wire compatibility with the scaffold:** the scaffold-era enum
    /// only had `low / medium / high`. Those three raw-value strings
    /// remain present in the new ladder, so any JSON written by the
    /// scaffold decodes into the new enum without translation —
    /// see `Confidence.init(from:)`'s reliance on Swift's synthesised
    /// `RawRepresentable` decoder.
    public enum Confidence: String, Sendable, Codable, Equatable, CaseIterable {
        case veryHigh
        case high
        case medium
        case low
        case veryLow

        /// Midpoint probability for the band, in `[0, 1]`. The values
        /// are intentionally not equally spaced: confidence calibration
        /// in language models is famously top-heavy (a model that says
        /// "90% sure" is usually closer to right than wrong, but a
        /// model that says "30% sure" is closer to a coin flip than
        /// the number suggests), so the high bands occupy more of the
        /// probability axis than the low ones.
        ///
        /// The numeric is exposed for two callers:
        ///   1. The audit-log "Show me what you see" panel (#71) wants
        ///      to render a numeric confidence next to the band label
        ///      so the user gets both the categorical and the
        ///      continuous read.
        ///   2. Aggregation: when several explainers agree, callers
        ///      may want to combine confidences. Doing arithmetic on
        ///      the band itself is wrong; doing arithmetic on the
        ///      midpoints is at least defensible.
        public var numeric: Double {
            switch self {
            case .veryHigh: return 0.95
            case .high:     return 0.80
            case .medium:   return 0.60
            case .low:      return 0.30
            case .veryLow:  return 0.10
            }
        }

        /// Map a raw model log-probability (or any monotone score) to
        /// a confidence band.
        ///
        /// The input is a natural-log probability — what Apple
        /// Foundation Models exposes via its per-token score API and
        /// what most on-device LMs report. The function compares the
        /// equivalent linear probability `exp(modelLogProb)` against
        /// fixed thresholds and returns the matching band:
        ///
        ///   - `p >= 0.90` → `.veryHigh`
        ///   - `p >= 0.70` → `.high`
        ///   - `p >= 0.50` → `.medium`
        ///   - `p >= 0.30` → `.low`
        ///   - otherwise   → `.veryLow`
        ///
        /// The thresholds are deliberately not "equal-width" — see
        /// the rationale on ``numeric``.
        ///
        /// **Pathological inputs:**
        ///   - `NaN` → `.veryLow`. A model that can't produce a score
        ///     deserves the most cautious bucket; we won't let an
        ///     undefined number sneak past the answer gate.
        ///   - `-Double.infinity` → `.veryLow`. `exp(-inf) == 0`, which
        ///     is the lowest probability and stays in the lowest band.
        ///   - `+Double.infinity` → `.veryHigh`. `exp(+inf) == +inf`
        ///     which is greater than any threshold; saturate at the top.
        ///     (Strictly, log-prob > 0 means p > 1 which is impossible,
        ///     but the function chooses to saturate rather than crash
        ///     so a buggy model-bridge can't take down the explainer.)
        ///   - Positive but finite values (i.e. `p > 1`) also saturate
        ///     at `.veryHigh` for the same reason.
        public static func classify(modelLogProb: Double) -> Confidence {
            // NaN compares false against every threshold, so check
            // explicitly first — otherwise we'd fall through to
            // `.veryLow`, which happens to be right but only by
            // accident. Explicit is clearer.
            if modelLogProb.isNaN {
                return .veryLow
            }
            // `+inf` exponentiates to `+inf`; the threshold ladder
            // below would still produce `.veryHigh`, but skip the
            // arithmetic to keep the intent obvious.
            if modelLogProb == .infinity {
                return .veryHigh
            }
            // `-inf` exponentiates to `0`; same story — explicit is
            // cheaper to read than "trust the ladder to handle it".
            if modelLogProb == -.infinity {
                return .veryLow
            }
            let p = Foundation.exp(modelLogProb)
            if p >= 0.90 { return .veryHigh }
            if p >= 0.70 { return .high }
            if p >= 0.50 { return .medium }
            if p >= 0.30 { return .low }
            return .veryLow
        }
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

    /// Coerce a (text, confidence) pair into the safe `ExplainResponse`
    /// shape. **This is the brand-contract chokepoint** — every code
    /// path that turns a raw model answer into an `ExplainResponse`
    /// should funnel through here rather than constructing
    /// `.answer(text:confidence:)` directly.
    ///
    /// Rule:
    ///   - `confidence` in `{ .veryHigh, .high, .medium }` →
    ///     `.answer(text:, confidence:)`.
    ///   - `confidence` in `{ .low, .veryLow }` →
    ///     `.unsure(reason: .lowConfidence)`. The text is *dropped*;
    ///     surfacing a low-confidence answer (even with a "low
    ///     confidence" badge attached) is exactly the failure mode
    ///     the brand contract refuses. The audit log still records
    ///     what the model said — the audit row stores the raw
    ///     response separately — but the user-facing channel never
    ///     sees it.
    ///
    /// Why a static factory and not a private initialiser on the
    /// `.answer` case: making this the only ergonomic way to build a
    /// response means a future engineer who writes
    /// `.answer(text: ..., confidence: .low)` is doing something
    /// visibly weird that a reviewer can flag. We considered marking
    /// `.answer`'s associated values internal-only, but that would
    /// have broken the Codable derivation and the scaffold's existing
    /// public API. The factory is the friendliest path; direct
    /// construction is the escape hatch tests use.
    public static func from(
        answerText: String,
        confidence: Confidence
    ) -> ExplainResponse {
        switch confidence {
        case .veryHigh, .high, .medium:
            return .answer(text: answerText, confidence: confidence)
        case .low, .veryLow:
            // Drop `answerText` on the floor. The audit log captures
            // the raw model output upstream; we don't want the
            // user-facing response carrying prose the model wasn't
            // sure about.
            return .unsure(reason: .lowConfidence)
        }
    }
}

// MARK: - Codable

/// Hand-rolled `Codable` so the on-disk JSON is human-readable: each
/// case serialises to `{"kind": "answer", ...}` or `{"kind": "unsure",
/// "reason": "lowConfidence"}` rather than Swift's default
/// case-discriminator scheme. The "Show me what you see" panel (#71)
/// will display these audit rows directly, so the wire format needs
/// to be eyeball-friendly.
///
/// **Backward compatibility:** the scaffold's `Confidence` enum had
/// only `low / medium / high`. All three of those raw-value strings
/// remain in the new 5-band ladder, so JSON written by the scaffold
/// decodes into the new enum verbatim — no custom decode logic, no
/// version field on the audit row. The strategy is best described as
/// "accept and upgrade": old `"low"` means `.low` in the new world
/// too (and any answer that gets re-coerced will route through
/// ``from(answerText:confidence:)`` next time it's built).
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
