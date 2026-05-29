import Foundation

/// Errors `ExplainModule` can throw or surface to the caller.
///
/// **Important distinction from ``ExplainResponse/unsure(reason:)``:**
/// these are *infrastructure* failures, not *epistemic* ones. A model
/// that doesn't know the answer is an `.unsure` response (and a normal
/// outcome). A model that can't be reached, returns malformed JSON, or
/// fails redaction is one of these errors (and an abnormal outcome
/// the UI should surface as "something went wrong" rather than as a
/// model answer).
///
/// All cases are `Sendable` + `Equatable` so call sites can pattern-
/// match in async contexts and tests can assert on the exact case.
///
/// Implemented further in:
///  - #68 — `redactionFailed` is thrown by the shared `PIIRedactor`
///    when it can't confidently strip a known PII class (e.g. a
///    pattern matched but normalisation hit a Unicode edge case).
///  - #69 — `modelUnavailable` covers macOS 14 fallback (Apple FM
///    requires macOS 15.1+ for the on-device path) and the
///    "FoundationModels framework refused to load" case.
///  - #70 — `malformedModelOutput` lands once we know what the raw
///    model output looks like; at scaffold time it's a placeholder.
public enum ExplainError: Error, Sendable, Equatable {

    /// The call site tried to reach a non-local model (cloud, remote
    /// process, anything not running in this binary). The module
    /// throws this rather than silently going to the network — every
    /// path that could reach the network is supposed to be impossible
    /// by construction, so seeing this in production is a code-review
    /// failure, not a runtime problem we need to recover from.
    ///
    /// Exists as a case so tests can assert "the module never opens a
    /// socket" by stubbing a network-attempt with this throw.
    case networkNotAllowed

    /// On-device model isn't available on this Mac. v1.5 ships
    /// macOS 14 as the minimum; Apple FoundationModels requires
    /// macOS 15.1+. Below that floor the call returns this error and
    /// the UI shows the "Upgrade macOS to use AI features" affordance.
    /// #69 wires the actual availability probe.
    case modelUnavailable

    /// PII redaction couldn't confidently strip a known PII class
    /// from the prompt. The module refuses to forward a prompt it
    /// can't safely redact — this is the brand contract's hard edge.
    /// #68 lands the redactor and defines the exact predicate for
    /// "couldn't confidently strip."
    case redactionFailed

    /// The model returned output that didn't match the expected
    /// confidence-aware schema (#70). The module logs the raw output
    /// to the audit log and surfaces this error so the call site
    /// shows a generic "the model gave an unusable response" message
    /// rather than rendering malformed JSON.
    case malformedModelOutput

    /// Catch-all for unanticipated failures (e.g. a future
    /// FoundationModels error code we don't recognise). Carries an
    /// `errorIdentifier` rather than the raw `Error` so the type can
    /// stay `Equatable` and tests can assert on a stable string.
    case internalFailure(errorIdentifier: String)
}
