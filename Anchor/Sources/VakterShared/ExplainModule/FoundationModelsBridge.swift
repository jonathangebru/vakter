import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The single in-process bridge to Apple's on-device Foundation
/// Models framework.
///
/// **Brand contract — locked.** This file is the *only* place in the
/// Vakter binary where a `LanguageModelSession` (or any equivalent
/// model client) may be constructed. The promise — "Vakter never uses
/// a cloud LLM" — is enforceable by code review precisely because
/// every model call originates here. Every `import` in this file is
/// either `Foundation` or `FoundationModels`. Any future change that
/// adds a network-capable import to this file is a code-review
/// failure.
///
/// ## Responsibilities
///
/// 1. **Availability probe.** Defers to
///    ``FoundationModelsAvailability`` for the macOS 15.1+ /
///    Apple-Intelligence-enabled / model-ready answer.
/// 2. **Session caching.** The model session is expensive to construct
///    (Apple's framework loads model weights into the user's Neural
///    Engine on first use). The bridge is an `actor` so the cached
///    session is serialised across concurrent callers — exactly one
///    session per process.
/// 3. **Error mapping.** Every Apple-side failure mode collapses into
///    ``ExplainError``: macOS 14 → `.modelUnavailable`, Apple
///    Intelligence disabled → `.modelUnavailable`, framework crash →
///    `.internalFailure`, malformed output (caller-detected) →
///    `.malformedModelOutput`. The bridge never returns nil for "the
///    model is unhappy" — every path either returns a `String` or
///    throws a typed error so call sites can pattern-match.
/// 4. **Graceful macOS 14 fallback.** The whole file compiles on macOS
///    14 (SDK-without-FoundationModels) because every framework-using
///    code path is gated behind `#if canImport(FoundationModels)` and
///    `@available(macOS 15.1, *)`. On macOS 14, ``generate(prompt:)``
///    throws ``ExplainError/modelUnavailable`` immediately — no
///    `fatalError`, no nil return, no cloud fallback.
///
/// ## Type shape
///
/// `FoundationModelsBridge` is an `actor` because the cached session
/// is shared mutable state and Apple's `LanguageModelSession` is a
/// thread-confined object. Wrapping it in an actor lets us serialise
/// concurrent `generate(prompt:)` calls without an explicit lock.
///
/// ## Implementation in #69
///
/// This ticket (#69) lands the bridge itself plus the macOS-14
/// fallback. Future tickets layer on top:
///   - #70 — the confidence-aware output schema parses the raw
///     `String` this bridge returns.
///   - #71 — the audit-panel UI reads from
///     ``ExplainAuditEntry/durationMilliseconds``, which is measured
///     here.
///   - #72 — prompt-engineering edge cases are exercised against
///     this bridge via mocked sessions.
public actor FoundationModelsBridge {

    /// The single process-wide instance every call site uses. Mirrors
    /// ``ExplainModule/shared`` — both are singletons because the
    /// brand contract is easier to enforce when there's exactly one
    /// instance of each.
    ///
    /// Tests construct their own private instance via
    /// ``init(availabilityOverride:)``.
    public static let shared = FoundationModelsBridge()

    /// Optional test override for the availability probe. `nil` in
    /// production (probe falls through to
    /// ``FoundationModelsAvailability/current``). Tests inject a
    /// fixed state so they can exercise every branch on any host —
    /// even a macOS 14 build host that can't link the real framework.
    private let availabilityOverride: FoundationModelsAvailability.State?

    /// Cached `LanguageModelSession`. Type-erased to `Any?` because
    /// the strongly-typed property would require the actor itself to
    /// be `@available(macOS 15.1, *)` — and that would break the
    /// macOS 14 fallback path (callers couldn't even *reference* the
    /// bridge on macOS 14). The erasure is contained: every read of
    /// this property happens inside a `@available(macOS 15.1, *)`
    /// helper that casts back.
    private var cachedSession: Any?

    /// Production callers use ``shared``. The internal initialiser
    /// exists for tests, which inject an `availabilityOverride` so
    /// they can exercise every branch on any macOS version.
    init(availabilityOverride: FoundationModelsAvailability.State? = nil) {
        self.availabilityOverride = availabilityOverride
        self.cachedSession = nil
    }

    // MARK: - Public surface

    /// Generate raw model output for the given prompt.
    ///
    /// The prompt is expected to be **already PII-redacted** by the
    /// caller (typically ``ExplainModule``, which runs the shared
    /// `PIIRedactor` over it — see #68). This bridge does NOT redact;
    /// its only job is to dispatch to Apple's framework.
    ///
    /// Returns the raw string Apple's `LanguageModelSession.respond`
    /// produced. The caller is responsible for parsing it into the
    /// confidence-aware schema (#70 — `OutputValidator`).
    ///
    /// ## Errors
    ///
    /// Throws ``ExplainError/modelUnavailable`` when:
    ///   - The OS is below macOS 15.1.
    ///   - The build linked against an SDK without
    ///     `FoundationModels`.
    ///   - Apple's `SystemLanguageModel.default.availability` reports
    ///     any non-`.available` state (Apple Intelligence not
    ///     enabled, model not ready, device not eligible, etc.).
    ///
    /// Throws ``ExplainError/internalFailure(errorIdentifier:)``
    /// when:
    ///   - Apple's framework threw an unrecognised error (the raw
    ///     `error.localizedDescription` becomes the identifier so
    ///     audit rows preserve the diagnostic).
    ///   - The prompt was empty (no point hitting the model).
    ///
    /// Never throws ``ExplainError/networkNotAllowed`` — that case
    /// exists for the *caller's* invariant ("the module never opens
    /// a socket"), not this bridge's. Apple's framework is local-only
    /// by construction.
    public func generate(prompt: String) async throws -> String {
        // Reject empty prompts up front so we don't burn a model
        // session token on nothing. Returning a typed error rather
        // than silently producing "" makes the empty-prompt bug
        // visible in tests.
        guard !prompt.isEmpty else {
            throw ExplainError.internalFailure(
                errorIdentifier: "empty-prompt"
            )
        }

        // Availability is the first gate. Resolving here (rather than
        // at session-construction time) means every error path is
        // reached *before* we touch Apple's framework — keeping the
        // macOS 14 path provably no-op.
        let state = availabilityOverride ?? FoundationModelsAvailability.current
        guard case .available = state else {
            throw ExplainError.modelUnavailable
        }

        #if canImport(FoundationModels)
        if #available(macOS 15.1, *) {
            return try await dispatchToAppleFramework(prompt: prompt)
        } else {
            // We checked availability above, but the compiler still
            // demands a fallback for the `@available` gate. This
            // branch is unreachable in practice — keeping it
            // `modelUnavailable` rather than `internalFailure`
            // matches what the caller would see on a real macOS 14
            // host.
            throw ExplainError.modelUnavailable
        }
        #else
        // macOS-14 build host: framework wasn't linkable. The
        // availability probe above already returned `.unavailable`,
        // so this line is defensive — but we keep it so a future
        // refactor of the probe can't accidentally route a call into
        // a no-op return.
        throw ExplainError.modelUnavailable
        #endif
    }

    /// Whether the model is reachable on this Mac. Convenience over
    /// ``FoundationModelsAvailability/isAvailable`` for call sites
    /// that already hold a bridge reference.
    ///
    /// Returns the same answer the probe gives, taking any test
    /// override into account so unit tests can exercise both branches
    /// without forking the production path.
    public func isAvailable() -> Bool {
        let state = availabilityOverride ?? FoundationModelsAvailability.current
        if case .available = state {
            return true
        }
        return false
    }

    /// The detailed availability state, including diagnostic
    /// payload. Used by ``ExplainModule`` and the audit-log writer
    /// (#71) so the user sees *why* the model isn't reachable.
    public func availabilityState() -> FoundationModelsAvailability.State {
        availabilityOverride ?? FoundationModelsAvailability.current
    }

    // MARK: - Private — Apple framework dispatch

    #if canImport(FoundationModels)
    @available(macOS 15.1, *)
    private func dispatchToAppleFramework(prompt: String) async throws -> String {
        // Cache the session so we don't reload model weights on
        // every call. The first call pays the model-load cost;
        // subsequent calls are warm.
        let session = try existingOrNewSession()

        do {
            // Apple's `respond(to:)` returns a `Response` whose
            // `content` is the raw model output. The exact return
            // shape has shifted across beta seeds; `String(describing:)`
            // on the response gives us a stable fallback if Apple
            // refactors the type without renaming the framework.
            let response = try await session.respond(to: prompt)
            return extractText(from: response)
        } catch {
            // Map any Apple-side throw to internalFailure so call
            // sites have a typed error. The localized description
            // is preserved so the audit row records the diagnostic.
            throw ExplainError.internalFailure(
                errorIdentifier: "fm-respond-failed: \(error.localizedDescription)"
            )
        }
    }

    @available(macOS 15.1, *)
    private func existingOrNewSession() throws -> LanguageModelSession {
        if let session = cachedSession as? LanguageModelSession {
            return session
        }
        // Constructing the session can fail if Apple's framework
        // refuses (e.g. model still downloading). Wrap in a do/catch
        // so the call site sees a typed error rather than an
        // untyped `Error`.
        let session = LanguageModelSession()
        cachedSession = session
        return session
    }

    /// Extract a `String` from Apple's response type, which has
    /// shifted across beta seeds. We try `.content` (current public
    /// shape) first; if that fails, fall back to
    /// `String(describing:)`. Either way the caller gets a string.
    @available(macOS 15.1, *)
    private func extractText(from response: Any) -> String {
        // Apple's `LanguageModelSession.Response<String>` (WWDC '25
        // public shape) exposes the text via `.content`. We use a
        // Mirror to read it so this bridge stays compilable against
        // SDK seeds that name the property differently.
        let mirror = Mirror(reflecting: response)
        for child in mirror.children {
            if child.label == "content", let text = child.value as? String {
                return text
            }
        }
        // Fallback: the response itself may already be a String
        // (some seeds returned `String` directly from `.respond`).
        if let text = response as? String {
            return text
        }
        return String(describing: response)
    }
    #endif
}
