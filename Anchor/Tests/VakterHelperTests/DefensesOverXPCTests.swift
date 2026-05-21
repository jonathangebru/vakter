import XCTest
import Foundation
@testable import VakterHelper
import VakterShared

/// Helper-side contract tests for the Defenses-over-XPC path (closes
/// #27). The full `NSXPCConnection` plumbing can't be exercised in a
/// unit test — that requires a code-signed Mach service binary and a
/// real launchd registration. What we CAN (and must) verify here is
/// the deterministic, pure-Swift slice the XPC handler depends on:
///
///   1. `DefensesProbe.runAll()` produces a non-empty, well-formed
///      `DefenseChecklist` — the exact value the helper packages into
///      the `runPreflight` reply.
///   2. The `VakterXPC` codec round-trips the checklist losslessly.
///      A schema drift here (e.g. a forgotten `Codable` conformance
///      on a new field) would silently surface as an empty submenu
///      on the menubar — the exact regression #27 prevents.
///   3. The post-v1.4.2 floor of ≥20 checks holds. This is the user's
///      explicit acceptance criterion: "the snapshot returns ≥20
///      checks (after v1.4.2, we have 20)".
///
/// These tests live in `VakterHelperTests` rather than
/// `VakterSharedTests` because the contract is helper-owned: it's
/// the helper that builds the `DefenseChecklist` inside
/// `XPCService.runPreflight`, and the helper's @testable surface
/// is what guarantees that build hasn't drifted.
final class DefensesOverXPCTests: XCTestCase {

    // MARK: - Acceptance criterion: ≥20 checks

    /// The user-facing acceptance criterion from #27: the menubar's
    /// Defenses submenu, fed from the helper's `runPreflight` reply,
    /// must include all 20 (v1.4.2) checks. We assert the floor at
    /// 20 rather than an exact match so a future PR that ADDS a check
    /// doesn't break this test — but a removal will, by design.
    func test_runPreflightSnapshot_hasAtLeast20Checks() {
        let checklist = DefensesProbe.runAll()
        XCTAssertGreaterThanOrEqual(
            checklist.items.count, 20,
            "menubar Defenses submenu would be missing checks. Expected ≥20 (v1.4.2 floor), got \(checklist.items.count)"
        )
    }

    /// The XPC reply must cover every category — otherwise one of the
    /// menubar's category submenus ("Access Security" / "Firewall &
    /// Sharing" / "macOS Updates" / "Software Updates" / "System
    /// Integrity") would render as an empty stub.
    func test_runPreflightSnapshot_coversAllCategories() {
        let checklist = DefensesProbe.runAll()
        let cats = Set(checklist.items.map { $0.category })
        for expected in DefenseCategory.allCases {
            XCTAssertTrue(
                cats.contains(expected),
                "menubar Defenses submenu would be missing category \(expected.rawValue)"
            )
        }
    }

    // MARK: - XPC codec round-trip

    /// Simulate the exact transport the XPC reply uses:
    ///   helper-side:   `VakterXPC.encode(checklist)` → `Data`
    ///   app-side:      `VakterXPC.decode(DefenseChecklist.self, from: data)`
    ///
    /// A regression here (added a non-Codable field, broke an enum's
    /// raw value, changed a date strategy) would land as a silent
    /// "menubar dropdown shows no checks" bug — every Settings → run
    /// would look fine because it bypasses the codec.
    func test_xpcCodec_roundTripsChecklist_withoutLoss() {
        let original = DefensesProbe.runAll()
        let encoded = VakterXPC.encode(original)
        XCTAssertGreaterThan(
            encoded.count, 0,
            "encoder produced empty Data — JSONEncoder threw and we swallowed it"
        )

        guard let decoded = VakterXPC.decode(DefenseChecklist.self, from: encoded) else {
            XCTFail("decoder returned nil — schema drift between encoder/decoder")
            return
        }

        XCTAssertEqual(decoded.items.count, original.items.count)
        XCTAssertEqual(
            decoded.items.map { $0.id },
            original.items.map { $0.id },
            "item ids must survive the codec round-trip in the original order"
        )
        XCTAssertEqual(
            decoded.items.map { $0.status },
            original.items.map { $0.status },
            "item statuses must survive the codec round-trip"
        )
        XCTAssertEqual(
            decoded.items.map { $0.category },
            original.items.map { $0.category },
            "item categories must survive the codec round-trip"
        )
        // ISO-8601 dates round-trip at seconds precision via
        // JSONEncoder's `.iso8601` strategy (the default formatter
        // truncates fractional seconds). Tolerate <1 s of drift —
        // the runAt timestamp is informational ("Last check 49 min
        // ago"), not used for ordering or auth.
        XCTAssertLessThan(
            abs(decoded.runAt.timeIntervalSince(original.runAt)),
            1.0,
            "runAt must survive ISO-8601 round-trip within 1 s (encoder strategy truncates subseconds)"
        )
    }

    /// Empty `Data` reply (the literal pre-#27 stub) must NOT decode
    /// into a usable checklist. Confirms our caller-side fallback
    /// will trigger rather than silently render zero items.
    func test_xpcCodec_emptyData_decodesAsNil() {
        let decoded = VakterXPC.decode(DefenseChecklist.self, from: Data())
        XCTAssertNil(
            decoded,
            "empty Data must decode to nil so the caller falls back to a local probe — pre-#27 the stub returned exactly this"
        )
    }

    // MARK: - Off-thread shape

    /// `DefensesProbe.runAll()` is allowed to be called from any
    /// thread (XPC handler queue, helper utility queue, scheduler
    /// work queue, unit test main thread). This is the contract that
    /// lets `XPCService.runPreflight` dispatch onto
    /// `DispatchQueue.global(.utility)` without ceremony. Smoke-test
    /// by calling it off-main and asserting the same shape.
    func test_runAll_isThreadAgnostic() {
        let expectation = self.expectation(description: "runAll completes off main")
        DispatchQueue.global(qos: .utility).async {
            let checklist = DefensesProbe.runAll()
            XCTAssertGreaterThanOrEqual(checklist.items.count, 20)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 30.0)
    }
}
