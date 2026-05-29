import Foundation

/// The single, in-process bridge between Vakter and Apple Foundation
/// Models.
///
/// **Brand contract — locked.** Every Watch domain (Mail, Messages,
/// Web, Mac) and every Defenses explainer call routes through this
/// type. No other code path is allowed to construct an Apple FM
/// `LanguageModelSession` (or any equivalent) — and no other code
/// path is allowed to open a socket on the user's behalf for the
/// purpose of asking a model a question. That promise — "Vakter
/// never uses a cloud LLM" — is enforceable by code review precisely
/// because there is exactly one place in the binary where a model
/// call originates.
///
/// Concretely, this module is responsible for:
///   1. **Defence-in-depth PII redaction.** The caller's domain-aware
///      redactor runs first; this module re-runs a generic pass
///      before any prompt reaches the on-device model. (#68 lands the
///      shared `PIIRedactor` and the exact rule set.)
///   2. **On-device-only model dispatch.** The actual
///      FoundationModels call (#69) lives behind a single private
///      method here. The macOS-14 fallback returns
///      ``ExplainError/modelUnavailable``.
///   3. **Confidence-aware output handling.** Below medium
///      confidence, the module returns ``ExplainResponse/unsure(reason:)``
///      rather than forwarding low-confidence prose. (#70 defines the
///      exact threshold and the mapping from raw model signal to the
///      ``ExplainResponse/Confidence`` ladder.)
///   4. **Audit logging.** Every call writes one
///      ``ExplainAuditEntry`` to the on-disk log so the user can
///      inspect their model history from Settings → Privacy → LLM
///      History (#71 ships the UI).
///
/// **This file is scaffold-only.** Every method here either returns
/// a placeholder or throws ``ExplainError/internalFailure(errorIdentifier:)``
/// with a `"#68/#69/#70-not-implemented"` identifier. The follow-on
/// tickets in Epic #59 fill in each responsibility — see the per-
/// method doc-comments for the exact mapping.
///
/// ## Type shape
///
/// `ExplainModule` is an `actor` rather than a `struct` because:
///   - The audit log is shared mutable state (append-only file
///     handle). An actor gives us natural serialisation of writes.
///   - The on-device model session is expensive to construct;
///     #69 will cache one inside the actor and re-use it across
///     calls.
///   - All call sites are already in async contexts (the menubar
///     app's settings UI, the daemon's threat-feed-driven scans).
public actor ExplainModule {

    /// The single shared instance every call site uses. Exposed as a
    /// `static let` rather than dependency-injected because the brand
    /// contract — "exactly one bridge" — is easier to enforce when
    /// the type is a process-wide singleton. Tests construct their
    /// own private instance via the internal initialiser.
    public static let shared = ExplainModule()

    /// Public initialiser is intentionally absent — call sites use
    /// ``shared``. Tests use the internal initialiser (which exists
    /// implicitly because there are no stored properties at scaffold
    /// time; #69 will add an explicit `internal init` once the model
    /// session and audit-writer become stored properties).

    // MARK: - Public surface

    /// Ask the on-device model the question encoded in `request` and
    /// return either an answer with confidence, or an explicit
    /// "I'm not sure" — never a low-confidence forwarding.
    ///
    /// At scaffold time this method always returns
    /// ``ExplainResponse/unsure(reason:)`` with
    /// ``ExplainResponse/UnsureReason/outOfScope``. That's the
    /// safest placeholder behaviour: every existing call site (none
    /// at v1.5 yet) gets a well-formed response shape it can render,
    /// and no real model output flows until #69 ships.
    ///
    /// Implemented in:
    ///  - #68 — wires the PII-redaction pre-pass over `request.redactedPrompt`.
    ///  - #69 — replaces the placeholder body with the real
    ///    FoundationModels call.
    ///  - #70 — adds the confidence-threshold gate that decides
    ///    answer-vs-unsure.
    public func explain(request: ExplainRequest) async -> ExplainResponse {
        // Scaffold placeholder. Returning `.unsure(.outOfScope)`
        // rather than `fatalError` so the type-system contract is
        // exercisable in tests and downstream code can compile
        // against a real return path. The audit-log write is
        // intentionally NOT performed here — #69 will gate the
        // write on a real model call having happened.
        _ = request
        return .unsure(reason: .outOfScope)
    }

    /// Whether the on-device model is reachable on this Mac.
    ///
    /// At scaffold time this returns `false`. #69 wires the real
    /// availability probe (Apple FoundationModels requires
    /// macOS 15.1+; below that the answer is always `false`).
    ///
    /// Call sites use this to decide whether to show the
    /// "AI features require macOS 15.1+" affordance vs. enabling
    /// the LLM chat panel.
    public func isModelAvailable() -> Bool {
        // Scaffold placeholder — see #69.
        return false
    }

    /// Returns the audit log as an array of entries, newest first.
    ///
    /// At scaffold time this returns an empty array. #71 will read
    /// the on-disk JSON the audit writer (added in #69) produces.
    ///
    /// The method is async because the disk read (once wired) is an
    /// I/O operation and should not block any caller's main actor.
    public func recentAuditEntries(limit: Int = 100) async -> [ExplainAuditEntry] {
        // Scaffold placeholder — see #71.
        _ = limit
        return []
    }
}
