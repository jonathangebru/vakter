import XCTest
@testable import VakterShared

/// Unit tests for the FoundationModels integration wrapper (Issue #69).
///
/// **The brand-contract test surface.** Vakter's promise — "Vakter
/// never uses a cloud LLM" — is enforced by code review of
/// ``FoundationModelsBridge``. These tests cover the contract from the
/// opposite direction: they verify that on every code path where the
/// real Apple framework isn't reachable, the bridge produces a typed
/// error rather than silently falling through to a cloud call. If a
/// future change were to add a cloud fallback, the
/// ``test_bridge_neverReturnsResultWhenUnavailable`` invariants would
/// fail.
///
/// **Why mocks via `availabilityOverride` rather than protocol
/// injection:** Apple's `LanguageModelSession` is a class without a
/// public protocol, and writing our own protocol mirror would commit
/// us to keeping it in sync with every WWDC '25 / '26 update. Instead
/// we inject the availability *answer* (not the session itself) so we
/// can exercise every code path that branches on availability — which
/// covers the macOS 14 fallback, the brand contract enforcement, and
/// every Apple-reported-unavailable diagnostic. The actual
/// session-construction path is only tested on macOS 15.1+ build
/// hosts via the compile-time gate.
///
/// On macOS 14 build hosts (where `FoundationModels` can't be
/// imported), these tests cover:
///   - The graceful fallback returns
///     ``ExplainError/modelUnavailable``.
///   - The availability probe returns
///     ``FoundationModelsAvailability/Reason/frameworkNotLinked``.
///   - Empty-prompt validation runs before the availability check
///     fires.
///   - Error mapping for every Apple-reported reason via the
///     test-injected override.
final class FoundationModelsBridgeTests: XCTestCase {

    // MARK: - Availability probe

    func test_availabilityProbe_returnsAValue() {
        // The probe must always return a state — it cannot crash, it
        // cannot return nil (its return type is non-optional). This
        // test is the most defensive of the bunch: a future refactor
        // that introduces a `fatalError` in the probe path would
        // break the macOS 14 startup sequence.
        let state = FoundationModelsAvailability.current
        switch state {
        case .available, .unavailable:
            // Any concrete case is fine — we just need to know the
            // probe terminates and yields a defined value.
            break
        }
    }

    func test_availabilityProbe_isAvailableMirrorsCurrent() {
        // The boolean convenience must agree with the rich `current`
        // answer. Any drift here would mean call sites that gate UI
        // on `isAvailable` disagree with those that branch on
        // `current`.
        let isAvailable = FoundationModelsAvailability.isAvailable
        if case .available = FoundationModelsAvailability.current {
            XCTAssertTrue(isAvailable,
                          "isAvailable must be true when current == .available")
        } else {
            XCTAssertFalse(isAvailable,
                           "isAvailable must be false when current is any unavailable variant")
        }
    }

    func test_availabilityProbe_macOS14_reportsFrameworkNotLinked() {
        // On a macOS 14 build host the `FoundationModels` framework
        // can't be imported, so the probe must short-circuit to
        // `.unavailable(.frameworkNotLinked)`. On a macOS 15.1+ host
        // the framework is importable and the probe defers to
        // Apple's answer — in which case this test verifies the OS
        // gate exists (no `.frameworkNotLinked` value can leak when
        // the framework IS linked).
        #if !canImport(FoundationModels)
        guard case let .unavailable(reason) = FoundationModelsAvailability.current else {
            return XCTFail("macOS 14 build host must report unavailable")
        }
        XCTAssertEqual(reason, .frameworkNotLinked,
                       "macOS 14 build host must report frameworkNotLinked, " +
                       "not unsupportedOS — the OS may itself be 15.1+ at run time " +
                       "but the SDK we compiled against lacked the framework")
        #else
        // On a macOS 15.1+ build host, the only paths are
        // `.available`, `.unavailable(.unsupportedOS)` (if the
        // running OS is below 15.1 — but `#if canImport` already
        // checked the *build* host, so this is rare), or
        // `.unavailable(.appleReportedUnavailable)`. Crucially,
        // `.frameworkNotLinked` must NOT appear because the
        // framework IS linked.
        if case let .unavailable(reason) = FoundationModelsAvailability.current {
            XCTAssertNotEqual(reason, .frameworkNotLinked,
                              "framework IS linked on this host — probe should never " +
                              "report .frameworkNotLinked")
        }
        #endif
    }

    // MARK: - Bridge construction

    func test_bridge_sharedSingletonIsReachable() async {
        // Touching the singleton verifies the actor compiles, the
        // implicit init exists, and no startup work crashes.
        let bridge = FoundationModelsBridge.shared
        let _ = await bridge.isAvailable()
    }

    func test_bridge_isAvailableMatchesProbe_inProductionPath() async {
        // The default-constructed bridge (no override) must agree
        // with the static availability probe — call sites use both
        // interchangeably and any drift would be a subtle bug.
        let bridge = FoundationModelsBridge.shared
        let bridgeAvailable = await bridge.isAvailable()
        XCTAssertEqual(bridgeAvailable, FoundationModelsAvailability.isAvailable,
                       "bridge.isAvailable() and the static probe must agree")
    }

    // MARK: - macOS 14 fallback (brand contract)

    func test_bridge_macOS14_throwsModelUnavailable() async {
        // The keystone test for the brand contract. On macOS 14 the
        // bridge MUST throw ``ExplainError/modelUnavailable`` — not
        // crash, not return a placeholder string, not silently fall
        // back to anything. Using the override lets us exercise this
        // even on a macOS 15.1+ build host.
        let bridge = FoundationModelsBridge(
            availabilityOverride: .unavailable(.unsupportedOS)
        )
        do {
            _ = try await bridge.generate(prompt: "Test prompt for macOS 14.")
            XCTFail("bridge must throw on macOS 14, returned a string instead")
        } catch let error as ExplainError {
            XCTAssertEqual(error, .modelUnavailable,
                           "macOS 14 path must surface .modelUnavailable, not another case")
        } catch {
            XCTFail("expected ExplainError, got \(type(of: error)): \(error)")
        }
    }

    func test_bridge_frameworkNotLinked_throwsModelUnavailable() async {
        // The companion to the macOS-14 case: when the build SDK
        // lacks the framework even though the OS supports it, the
        // bridge still must throw `.modelUnavailable`.
        let bridge = FoundationModelsBridge(
            availabilityOverride: .unavailable(.frameworkNotLinked)
        )
        do {
            _ = try await bridge.generate(prompt: "Test prompt.")
            XCTFail("bridge must throw when framework not linked")
        } catch let error as ExplainError {
            XCTAssertEqual(error, .modelUnavailable)
        } catch {
            XCTFail("expected ExplainError, got \(error)")
        }
    }

    func test_bridge_appleReportedUnavailable_throwsModelUnavailable() async {
        // Every Apple-reported unavailable case (Apple Intelligence
        // disabled, model not ready, device not eligible, etc.) maps
        // to the same Vakter error. We don't enumerate Apple's cases
        // here — the bridge is intentionally agnostic to which
        // specific case Apple returned, so the user-facing error is
        // consistent regardless of Apple's diagnostic shifts.
        let appleReasons = [
            "appleIntelligenceNotEnabled",
            "modelNotReady",
            "deviceNotEligible",
            "modelDownloading",
            "other(someFutureCase)"
        ]
        for raw in appleReasons {
            let bridge = FoundationModelsBridge(
                availabilityOverride: .unavailable(.appleReportedUnavailable(details: raw))
            )
            do {
                _ = try await bridge.generate(prompt: "ping")
                XCTFail("bridge must throw for Apple-reported reason '\(raw)'")
            } catch let error as ExplainError {
                XCTAssertEqual(error, .modelUnavailable,
                               "Apple reason '\(raw)' must map to .modelUnavailable; got \(error)")
            } catch {
                XCTFail("expected ExplainError for '\(raw)', got \(error)")
            }
        }
    }

    // MARK: - Empty-prompt validation

    func test_bridge_emptyPrompt_throwsInternalFailure() async {
        // Empty prompts are rejected before the availability check —
        // we don't want to burn a model session token on nothing,
        // and the empty case is almost always a caller bug.
        // Forcing `.available` via the override exercises the
        // empty-prompt branch even on a host where the real model
        // isn't reachable.
        let bridge = FoundationModelsBridge(
            availabilityOverride: .available
        )
        do {
            _ = try await bridge.generate(prompt: "")
            XCTFail("empty prompt must throw")
        } catch let error as ExplainError {
            if case let .internalFailure(identifier) = error {
                XCTAssertEqual(identifier, "empty-prompt",
                               "empty-prompt errors must use the stable 'empty-prompt' " +
                               "identifier so tests can pattern-match")
            } else {
                XCTFail("expected .internalFailure, got \(error)")
            }
        } catch {
            XCTFail("expected ExplainError, got \(error)")
        }
    }

    func test_bridge_emptyPrompt_runsBeforeAvailabilityCheck() async {
        // Empty-prompt validation must fire even when the bridge is
        // configured as unavailable — the empty-prompt error is a
        // pure precondition failure and must be visible to tests
        // regardless of model state. (If the order were reversed,
        // callers on macOS 14 would see `.modelUnavailable` for an
        // empty prompt, masking the caller bug.)
        let bridge = FoundationModelsBridge(
            availabilityOverride: .unavailable(.unsupportedOS)
        )
        do {
            _ = try await bridge.generate(prompt: "")
            XCTFail("must throw")
        } catch let error as ExplainError {
            if case let .internalFailure(identifier) = error {
                XCTAssertEqual(identifier, "empty-prompt",
                               "empty-prompt validation must fire before availability check")
            } else {
                XCTFail("expected .internalFailure(empty-prompt), got \(error) — " +
                        "availability check fired first, masking the caller bug")
            }
        } catch {
            XCTFail("expected ExplainError, got \(error)")
        }
    }

    // MARK: - Availability state surface

    func test_bridge_availabilityState_reflectsOverride() async {
        // The override must be reflected in the state surface — tests
        // and the audit-log writer (#71) both read this to know why
        // the bridge isn't reachable.
        let overrides: [FoundationModelsAvailability.State] = [
            .available,
            .unavailable(.unsupportedOS),
            .unavailable(.frameworkNotLinked),
            .unavailable(.appleReportedUnavailable(details: "modelNotReady"))
        ]
        for override in overrides {
            let bridge = FoundationModelsBridge(availabilityOverride: override)
            let state = await bridge.availabilityState()
            XCTAssertEqual(state, override,
                           "override \(override) must round-trip through availabilityState()")
        }
    }

    func test_bridge_isAvailable_trueWhenOverrideIsAvailable() async {
        let bridge = FoundationModelsBridge(availabilityOverride: .available)
        let available = await bridge.isAvailable()
        XCTAssertTrue(available,
                      "override .available must make isAvailable() return true")
    }

    func test_bridge_isAvailable_falseForEveryUnavailableReason() async {
        // Cycle through every Reason case explicitly. CaseIterable
        // would catch additions automatically, but Reason carries an
        // associated value so we enumerate by hand. If a future case
        // is added, the test won't auto-update — that's deliberate:
        // every new Reason should have a conscious mapping decision.
        let reasons: [FoundationModelsAvailability.Reason] = [
            .unsupportedOS,
            .frameworkNotLinked,
            .appleReportedUnavailable(details: "appleIntelligenceNotEnabled"),
            .appleReportedUnavailable(details: "modelNotReady"),
            .appleReportedUnavailable(details: "deviceNotEligible")
        ]
        for reason in reasons {
            let bridge = FoundationModelsBridge(
                availabilityOverride: .unavailable(reason)
            )
            let available = await bridge.isAvailable()
            XCTAssertFalse(available,
                           "reason \(reason) must make isAvailable() return false")
        }
    }

    // MARK: - Brand contract invariants

    func test_bridge_neverReturnsResultWhenUnavailable() async {
        // The brand contract's keystone invariant. Across every
        // unavailable reason, the bridge must throw — it must never
        // return a string. If a future refactor added a cloud
        // fallback, this loop would catch it because the cloud path
        // would have to return a string somewhere.
        let unavailableStates: [FoundationModelsAvailability.State] = [
            .unavailable(.unsupportedOS),
            .unavailable(.frameworkNotLinked),
            .unavailable(.appleReportedUnavailable(details: "any reason at all"))
        ]
        for state in unavailableStates {
            let bridge = FoundationModelsBridge(availabilityOverride: state)
            do {
                let result = try await bridge.generate(prompt: "What is FileVault?")
                XCTFail("brand-contract violation: bridge returned '\(result)' " +
                        "for unavailable state \(state) — this must be impossible")
            } catch is ExplainError {
                // Expected — any ExplainError is acceptable here;
                // the keystone property is "no string return when
                // unavailable", not the specific error case.
            } catch {
                XCTFail("expected ExplainError, got \(error)")
            }
        }
    }

    // MARK: - Reason details preserved for audit log

    func test_availabilityReason_preservesAppleDiagnosticDetails() {
        // The audit log (#71) shows the user *why* the model isn't
        // reachable. The Apple-reported diagnostic string must
        // survive end-to-end so the user sees Apple's verbatim
        // reason rather than a generic "unavailable" message.
        let detail = "appleIntelligenceNotEnabled"
        let reason = FoundationModelsAvailability.Reason
            .appleReportedUnavailable(details: detail)
        if case let .appleReportedUnavailable(extracted) = reason {
            XCTAssertEqual(extracted, detail,
                           "diagnostic detail must round-trip — the audit log " +
                           "shows this verbatim to the user")
        } else {
            XCTFail("Equatable destructure failed unexpectedly")
        }
    }
}
