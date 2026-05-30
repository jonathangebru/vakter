import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Probes Apple's on-device Foundation Models framework for
/// availability on the current Mac.
///
/// **Why a separate type?** The brand contract ("Vakter never uses a
/// cloud LLM") makes the availability decision security-critical: every
/// call site uses this answer to decide whether to show "AI features
/// require macOS 15.1+" vs. enabling the LLM chat panel. Concentrating
/// the probe in one type means an auditor can verify the answer is
/// always grounded in `SystemLanguageModel.default.availability` —
/// never a feature flag, never a remote config, never a heuristic.
///
/// **Two layers of gating:**
///   1. **Compile-time** — `#if canImport(FoundationModels)`. The build
///      host may be macOS 14 (where the SDK lacks the framework). If
///      the framework can't be imported at all, we hard-code
///      `isAvailable == false`. This keeps the package buildable on
///      any macOS 14+ host.
///   2. **Runtime** — `if #available(macOS 15.1, *)`. Even when the
///      framework is importable, the *running* user's Mac may be
///      macOS 14. The runtime check is what surfaces the macOS-14
///      fallback to the end user.
///
/// **Why we don't ship a typed mirror of Apple's enum:** Apple's
/// `SystemLanguageModel.Availability` enum cases (e.g. `.available`,
/// `.unavailable(.appleIntelligenceNotEnabled)`,
/// `.unavailable(.modelNotReady)`, `.unavailable(.deviceNotEligible)`,
/// `.unavailable(.other(...))`) are subject to additions across macOS
/// minor releases. Mirroring them in a Vakter-side enum would force a
/// code change every time Apple adds a case. Instead we map every
/// unavailable case to a single ``Reason`` value the UI can branch on,
/// and surface Apple's raw `String(describing:)` payload via
/// ``Reason/details`` for the audit-log row (#71). That keeps Vakter's
/// surface stable while preserving Apple's full diagnostic detail.
public enum FoundationModelsAvailability {

    /// Why the on-device model isn't available, in terms Vakter's UI
    /// can branch on. The diagnostic payload is preserved via
    /// ``Reason/details`` so the audit log (#71) shows the user the
    /// exact reason Apple's framework reported.
    public enum Reason: Sendable, Equatable {

        /// macOS version is below 15.1 — Foundation Models simply
        /// doesn't exist on this OS. The UI affordance is "Upgrade
        /// macOS to use AI features." This case is distinct from
        /// ``frameworkNotLinked`` because some hosts (e.g. an older
        /// Xcode toolchain) may compile against an SDK without the
        /// framework even on macOS 15.1+ — that path lands in
        /// ``frameworkNotLinked`` whereas this case is purely a
        /// runtime OS-version answer.
        case unsupportedOS

        /// The SDK this build was compiled against does not contain
        /// the `FoundationModels` framework. This happens when the
        /// build host is macOS 14 (the framework headers ship with
        /// the macOS 15.1+ SDK). Treated as "unavailable" with the
        /// same UX as ``unsupportedOS``.
        case frameworkNotLinked

        /// Apple's framework reported the model is unavailable.
        /// ``details`` carries `String(describing:)` of Apple's raw
        /// reason value (e.g. `"appleIntelligenceNotEnabled"`,
        /// `"modelNotReady"`, `"deviceNotEligible"`) so the audit
        /// row records Apple's verbatim diagnostic. We deliberately
        /// don't enumerate Apple's cases here — see the type-level
        /// doc-comment.
        case appleReportedUnavailable(details: String)
    }

    /// Whether Vakter can construct a real on-device
    /// `LanguageModelSession` right now.
    ///
    /// `true` only when:
    ///   1. The build linked against an SDK that contains
    ///      `FoundationModels` (`#if canImport(FoundationModels)`), AND
    ///   2. The running OS is macOS 15.1 or later
    ///      (`if #available(macOS 15.1, *)`), AND
    ///   3. `SystemLanguageModel.default.availability` reports
    ///      `.available`.
    ///
    /// Any other state — older macOS, framework missing, Apple
    /// Intelligence disabled, model still downloading — returns
    /// `false`. Call sites use this to decide whether to enable the
    /// LLM-using UI affordances.
    public static var isAvailable: Bool {
        if case .available = current {
            return true
        }
        return false
    }

    /// The richer availability answer, including *why* the model isn't
    /// reachable. Used by the audit-log writer (#71) so the user can
    /// see whether their model is missing because they're on macOS 14
    /// or because Apple Intelligence isn't enabled on their Mac.
    public static var current: State {
        #if canImport(FoundationModels)
        if #available(macOS 15.1, *) {
            return resolveWithFramework()
        } else {
            return .unavailable(.unsupportedOS)
        }
        #else
        return .unavailable(.frameworkNotLinked)
        #endif
    }

    /// Two-state availability answer. `.available` means a call to the
    /// bridge will reach Apple's framework; `.unavailable(reason)`
    /// carries the diagnostic.
    public enum State: Sendable, Equatable {
        case available
        case unavailable(Reason)
    }

    // MARK: - Private

    #if canImport(FoundationModels)
    @available(macOS 15.1, *)
    private static func resolveWithFramework() -> State {
        // `SystemLanguageModel.default.availability` is Apple's
        // canonical availability probe. The exact case names of its
        // payload have shifted across WWDC '25 beta seeds; we use
        // `String(describing:)` to capture whatever Apple's current
        // case label is, then map any non-`.available` value to our
        // single ``Reason/appleReportedUnavailable`` case. This keeps
        // Vakter compatible with future Apple case additions without
        // a code change.
        let availability = SystemLanguageModel.default.availability
        let raw = String(describing: availability)
        // Apple's enum has an `.available` case at root; checking the
        // string representation is robust to whether `Availability`
        // is a plain enum or one with associated payloads.
        if raw.hasPrefix("available") || raw == "available" {
            return .available
        }
        return .unavailable(.appleReportedUnavailable(details: raw))
    }
    #endif
}
