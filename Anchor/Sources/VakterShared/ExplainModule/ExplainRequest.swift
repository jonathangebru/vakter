import Foundation

/// Typed input to ``ExplainModule/explain(request:)``.
///
/// Carries the smallest possible amount of context the on-device model
/// needs to answer a Watch domain's question. Every call site (Mail,
/// Messages, Web, Mac) constructs one of these and passes it to the
/// module — no other code path is allowed to reach Apple Foundation
/// Models. That single chokepoint is what makes the brand contract
/// ("Vakter never uses a cloud LLM") enforceable by code review rather
/// than convention.
///
/// Design notes:
///  - `domain` is a free-form string at v1.5 (`"mail"`, `"messages"`,
///    `"web"`, `"mac"`, `"defenses"`) so we can add Watch domains in
///    v1.6/1.7/1.8 without a Package-level migration. A typed enum
///    will replace this once the domains stabilise.
///  - `redactedPrompt` is **already PII-redacted** by the caller's
///    domain-specific redactor (#68 lands the shared `PIIRedactor`).
///    The module re-runs a generic redaction pass as defence in depth,
///    but the contract is that the caller did the domain-aware work
///    first (e.g. Mail strips the From address before the prompt ever
///    reaches here).
///  - `locale` lets the prompt template pick the right user-facing
///    language. Defaults to `Locale.current` so most call sites can
///    omit it.
///  - `Sendable` so the type can cross actor boundaries without an
///    `@unchecked` escape hatch. All fields are value types.
///  - `Codable` so audit rows (``ExplainAuditEntry``) can persist the
///    exact request that produced a given response, for the "Show me
///    what you see" panel (#71).
///
/// Implemented further in:
///  - #68 — PII redaction pipeline (adds the generic defence-in-depth
///    pass the module runs over `redactedPrompt`).
///  - #69 — Apple FoundationModels integration (consumes this type).
///  - #70 — Confidence-aware output (no shape changes here).
public struct ExplainRequest: Sendable, Codable, Equatable {

    /// Which Watch domain originated this call. Free-form at v1.5 —
    /// see type-level note. Examples: `"mail"`, `"messages"`, `"web"`,
    /// `"mac"`, `"defenses"`.
    public let domain: String

    /// The user-or-system question the model should answer, with
    /// PII already redacted by the caller. The module will re-run a
    /// generic redaction pass before hitting the on-device model — see
    /// #68 for the shared `PIIRedactor` that does the work.
    public let redactedPrompt: String

    /// Preferred locale for the model's user-facing response. Mostly
    /// used by the prompt-template selector to pick the right language
    /// variant. Persisted as a BCP-47 identifier so an audit row from
    /// a French user reads cleanly in someone else's debug session.
    public let localeIdentifier: String

    public init(
        domain: String,
        redactedPrompt: String,
        locale: Locale = .current
    ) {
        self.domain = domain
        self.redactedPrompt = redactedPrompt
        self.localeIdentifier = locale.identifier
    }
}
