import XCTest
@testable import VakterShared

/// Tests for the v1.5 license-key intake (Issue #57).
///
/// What we cover:
///   - Default state: no key stored → `.free` tier.
///   - Dev-key shortcuts: VAKTER-DEV-FREE / ESSENTIAL / BUSINESS all
///     resolve to their respective tier and persist to Keychain.
///   - Production format: VKT-XXXX-XXXX-XXXX-XXXX accepted as
///     Essential (v1.5 structural-only check; #56 adds signature).
///   - Rejection paths: empty input, malformed input, and structurally-
///     valid-but-unknown values all return a rejection without
///     mutating stored state.
///   - Normalisation: whitespace trimming + uppercasing happens before
///     validation so paste-from-email is forgiving.
///   - Survives "restart": writing a key then asking `currentTier()`
///     fresh returns the right tier (no in-process caching means the
///     restart path is the same as a re-read).
///   - Deactivation reverts to `.free`.
///
/// All tests run against the *real* Keychain on the test runner. We
/// scope ourselves to the dedicated test-only `LicenseManager.
/// resetForTests()` helper to avoid leaking state across test methods
/// or across test sessions.
final class LicenseManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Wipe any prior on-disk Keychain entry so tests don't bleed
        // state into each other or carry over from a previous local
        // run. The helper is internal (not public) so production code
        // can't reach it.
        LicenseManager.resetForTests()
    }

    override func tearDown() {
        // Same posture as setUp — leave the system clean for whoever
        // runs the suite next (CI agent, human, vakter-release-warden).
        LicenseManager.resetForTests()
        super.tearDown()
    }

    // MARK: - Default state

    func test_currentTier_isFree_whenNoKeyStored() {
        XCTAssertEqual(LicenseManager.currentTier(), .free,
                       "fresh install with no key must be on the free tier")
        XCTAssertFalse(LicenseManager.isPaid(),
                       "isPaid() must mirror currentTier() == .free")
    }

    // MARK: - Dev key shortcuts

    func test_activate_devKeyFree_returnsFreeTier() {
        let result = LicenseManager.activate(key: "VAKTER-DEV-FREE")
        XCTAssertEqual(result, .activated(.free))
        XCTAssertEqual(LicenseManager.currentTier(), .free)
        // .free is intentionally not "paid" — even after a successful
        // activate with the dev-free key, the menubar's upgrade item
        // should stay visible. Verifies the boolean isn't accidentally
        // wired to "any successful activate."
        XCTAssertFalse(LicenseManager.isPaid())
    }

    func test_activate_devKeyEssential_returnsEssentialTier() {
        let result = LicenseManager.activate(key: "VAKTER-DEV-ESSENTIAL")
        XCTAssertEqual(result, .activated(.essential))
        XCTAssertEqual(LicenseManager.currentTier(), .essential)
        XCTAssertTrue(LicenseManager.isPaid())
    }

    func test_activate_devKeyBusiness_returnsBusinessTier() {
        let result = LicenseManager.activate(key: "VAKTER-DEV-BUSINESS")
        XCTAssertEqual(result, .activated(.business))
        XCTAssertEqual(LicenseManager.currentTier(), .business)
        XCTAssertTrue(LicenseManager.isPaid())
    }

    // MARK: - Production format

    func test_activate_productionFormat_returnsEssentialTier() {
        // Any structurally-valid VKT-XXXX-XXXX-XXXX-XXXX key resolves
        // to Essential at v1.5. Issue #56 will add a cryptographic
        // signature check on top.
        let result = LicenseManager.activate(key: "VKT-ABCD-1234-EFGH-5678")
        XCTAssertEqual(result, .activated(.essential))
        XCTAssertEqual(LicenseManager.currentTier(), .essential)
    }

    func test_activate_productionFormat_lowercase_acceptsAfterNormalise() {
        // User pastes the key as it might appear in an email body
        // (lowercase). Normalisation must uppercase before validation.
        let result = LicenseManager.activate(key: "vkt-abcd-1234-efgh-5678")
        XCTAssertEqual(result, .activated(.essential))
    }

    func test_activate_productionFormat_surroundingWhitespace_tolerated() {
        let result = LicenseManager.activate(key: "  VKT-AAAA-BBBB-CCCC-DDDD\n")
        XCTAssertEqual(result, .activated(.essential))
    }

    // MARK: - Rejection paths

    func test_activate_emptyInput_rejectedAsMalformed() {
        let result = LicenseManager.activate(key: "")
        XCTAssertEqual(result, .rejectedMalformed)
        XCTAssertEqual(LicenseManager.currentTier(), .free,
                       "rejected activate must not mutate stored state")
    }

    func test_activate_whitespaceOnlyInput_rejectedAsMalformed() {
        let result = LicenseManager.activate(key: "   \n\t  ")
        XCTAssertEqual(result, .rejectedMalformed)
        XCTAssertEqual(LicenseManager.currentTier(), .free)
    }

    func test_activate_garbageInput_rejectedAsMalformed() {
        // Garbage that doesn't match VKT-XXXX-XXXX-XXXX-XXXX nor any
        // dev key. Falls through to "shape doesn't match" path.
        let result = LicenseManager.activate(key: "not-a-key")
        XCTAssertEqual(result, .rejectedMalformed)
        XCTAssertEqual(LicenseManager.currentTier(), .free)
    }

    func test_activate_truncatedKey_rejectedAsMalformed() {
        // Right prefix, wrong group count — must NOT slide through.
        let result = LicenseManager.activate(key: "VKT-AAAA-BBBB")
        XCTAssertEqual(result, .rejectedMalformed)
        XCTAssertEqual(LicenseManager.currentTier(), .free)
    }

    func test_activate_extraGroups_rejectedAsMalformed() {
        // Five groups after VKT instead of four — must fail.
        let result = LicenseManager.activate(key: "VKT-AAAA-BBBB-CCCC-DDDD-EEEE")
        XCTAssertEqual(result, .rejectedMalformed)
    }

    func test_activate_wrongPrefix_rejectedAsMalformed() {
        // Right shape, wrong leading literal. Regex must enforce VKT.
        let result = LicenseManager.activate(key: "ABC-AAAA-BBBB-CCCC-DDDD")
        XCTAssertEqual(result, .rejectedMalformed)
    }

    func test_activate_nonAlphanumericChunks_rejectedAsMalformed() {
        // Symbols in a group — must fail. (The regex is [A-Z0-9]{4}.)
        let result = LicenseManager.activate(key: "VKT-A@CD-1234-EFGH-5678")
        XCTAssertEqual(result, .rejectedMalformed)
    }

    // MARK: - Persistence

    func test_activate_persistsAcrossFreshReads() {
        // Activate, then read `currentTier()` again. The second call
        // performs an independent Keychain fetch — verifies the key
        // was actually written, not merely cached in @State.
        let result = LicenseManager.activate(key: "VAKTER-DEV-ESSENTIAL")
        XCTAssertEqual(result, .activated(.essential))

        // Defensive: every currentTier() call re-reads Keychain, so
        // calling twice is the same as a process restart.
        XCTAssertEqual(LicenseManager.currentTier(), .essential)
        XCTAssertEqual(LicenseManager.currentTier(), .essential,
                       "tier must be stable across re-reads")
    }

    func test_activate_overwritesPriorKey() {
        // Upgrade flow: user pastes a Free dev key, then later pastes
        // an Essential key. The second activate must replace, not
        // append (Keychain item is single-account so the SecItemAdd
        // delete-then-add pattern is exercised here).
        XCTAssertEqual(LicenseManager.activate(key: "VAKTER-DEV-FREE"),
                       .activated(.free))
        XCTAssertEqual(LicenseManager.currentTier(), .free)

        XCTAssertEqual(LicenseManager.activate(key: "VAKTER-DEV-ESSENTIAL"),
                       .activated(.essential))
        XCTAssertEqual(LicenseManager.currentTier(), .essential)
    }

    func test_deactivate_revertsToFree() {
        XCTAssertEqual(LicenseManager.activate(key: "VAKTER-DEV-BUSINESS"),
                       .activated(.business))
        XCTAssertEqual(LicenseManager.currentTier(), .business)

        LicenseManager.deactivate()
        XCTAssertEqual(LicenseManager.currentTier(), .free)
        XCTAssertFalse(LicenseManager.isPaid())
    }

    func test_deactivate_isIdempotent() {
        // Calling deactivate twice on an already-empty Keychain must
        // not throw or assert.
        LicenseManager.deactivate()
        LicenseManager.deactivate()
        XCTAssertEqual(LicenseManager.currentTier(), .free)
    }

    // MARK: - Validation helpers (internal surface)

    func test_validate_recognisesDevKeys() {
        XCTAssertEqual(LicenseManager.validate(key: "VAKTER-DEV-FREE"), .free)
        XCTAssertEqual(LicenseManager.validate(key: "VAKTER-DEV-ESSENTIAL"), .essential)
        XCTAssertEqual(LicenseManager.validate(key: "VAKTER-DEV-BUSINESS"), .business)
    }

    func test_validate_rejectsUnknownKeys() {
        XCTAssertNil(LicenseManager.validate(key: "VAKTER-DEV-UNKNOWN"))
        XCTAssertNil(LicenseManager.validate(key: ""))
        XCTAssertNil(LicenseManager.validate(key: "garbage"))
    }

    func test_looksWellFormed_acceptsCanonicalProductionFormat() {
        XCTAssertTrue(LicenseManager.looksWellFormed("VKT-AAAA-BBBB-CCCC-DDDD"))
        XCTAssertTrue(LicenseManager.looksWellFormed("VKT-A1B2-C3D4-E5F6-G7H8"))
    }

    func test_looksWellFormed_rejectsDevKeys() {
        // Dev keys are not "well-formed production keys" — they are
        // valid via the explicit switch case, not the regex. This
        // matters for the activate() malformed-vs-unrecognised
        // branching.
        XCTAssertFalse(LicenseManager.looksWellFormed("VAKTER-DEV-ESSENTIAL"))
    }

    func test_normalise_trimsAndUppercases() {
        XCTAssertEqual(LicenseManager.normalise("  vkt-aaaa-bbbb  "),
                       "VKT-AAAA-BBBB")
        XCTAssertEqual(LicenseManager.normalise("\n\tabc\n"), "ABC")
        XCTAssertEqual(LicenseManager.normalise(""), "")
    }
}
