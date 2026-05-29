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

    // MARK: - v1.4.4 → v1.5 grandfather migration (Issue #78)
    //
    // The migration runs once per install at `applicationDidFinishLaunching`.
    // It detects "this Mac ran v1.4.x" via the presence of the
    // `vakter.onboarding.completed` UserDefaults marker (the only key
    // v1.4.4 universally wrote past first-launch onboarding). When the
    // detection fires AND the v1.5 Keychain license row is empty, the
    // user is grandfathered into Free tier with `Origin.upgraded`. AI
    // features still gate by `isAIFeatureUnlocked()`, which delegates
    // to `isPaid()`, so a grandfathered user does NOT get paid features
    // for free — the pricing contract is "anti-theft stays free
    // forever" (which includes upgraders), not "all features stay
    // free for upgraders".

    /// Net-new v1.5 install: no Keychain row, no v1.4.x onboarding
    /// marker. Migration must NOT grandfather — origin stays at .fresh,
    /// tier stays at .free, isAIFeatureUnlocked() stays false.
    func test_migrate_freshInstall_doesNotGrandfather() {
        // Clean baseline asserted up-front so the test is self-explanatory
        // even when read in isolation.
        XCTAssertEqual(LicenseManager.currentTier(), .free)
        XCTAssertEqual(LicenseManager.currentOrigin(), .fresh)

        LicenseManager.migrateFromV144IfNeeded()

        XCTAssertEqual(LicenseManager.currentOrigin(), .fresh,
                       "net-new install must remain .fresh — NOT grandfathered")
        XCTAssertEqual(LicenseManager.currentTier(), .free,
                       "tier should remain .free on a fresh install")
        XCTAssertFalse(LicenseManager.isAIFeatureUnlocked(),
                       "AI features must remain locked on a fresh install")
    }

    /// v1.4.4 upgrader: Keychain license row is empty, but the v1.4.x
    /// onboarding marker is present. Migration must grandfather into
    /// Free tier with `Origin.upgraded` — anti-theft stays free, AI
    /// features remain gated.
    func test_migrate_v144MarkerPresent_keychainEmpty_grandfathers() {
        // Simulate the v1.4.4 install posture: the marker that v1.4.4's
        // OnboardingState writes on successful onboarding is present,
        // and the v1.5 license Keychain row is empty.
        LicenseManager._testSetV144Marker(true)
        XCTAssertEqual(LicenseManager.currentTier(), .free,
                       "precondition: no license stored")

        LicenseManager.migrateFromV144IfNeeded()

        XCTAssertEqual(LicenseManager.currentOrigin(), .upgraded,
                       "v1.4.x marker + empty Keychain must produce Origin.upgraded")
        XCTAssertEqual(LicenseManager.currentTier(), .free,
                       "grandfathered user stays on the Free tier")
        XCTAssertFalse(LicenseManager.isPaid(),
                       "grandfathered user is NOT paid — Upgrade affordance must still show")
        XCTAssertFalse(LicenseManager.isAIFeatureUnlocked(),
                       "AI features must remain gated for grandfathered users — only anti-theft is free forever")
    }

    /// Calling `migrateFromV144IfNeeded()` twice must be a no-op the
    /// second time. The first call grandfathers; the second must not
    /// re-evaluate (because if it did, a v1.5 user who later completes
    /// onboarding would be re-detected as an "upgrader" on every
    /// subsequent launch).
    func test_migrate_isIdempotent_secondCallIsNoOp() {
        LicenseManager._testSetV144Marker(true)
        LicenseManager.migrateFromV144IfNeeded()
        XCTAssertEqual(LicenseManager.currentOrigin(), .upgraded,
                       "first call should grandfather")

        // Now simulate a sequence the second call must NOT react to:
        // the user activates an Essential key. If the second migrate
        // call wrongly re-ran detection it would (incorrectly) decide
        // the user is now a fresh install and overwrite origin to
        // .fresh — losing the upgrader provenance.
        XCTAssertEqual(LicenseManager.activate(key: "VAKTER-DEV-ESSENTIAL"),
                       .activated(.essential))

        LicenseManager.migrateFromV144IfNeeded()

        XCTAssertEqual(LicenseManager.currentOrigin(), .upgraded,
                       "second call must not overwrite origin — origin is install-provenance, set once")
        XCTAssertEqual(LicenseManager.currentTier(), .essential,
                       "the activated Essential tier must survive the second migrate call")
    }

    /// Existing paid Essential license on disk + v1.4.x marker also
    /// present (rare edge case: a user who paid for v1.5 on a Mac that
    /// also previously ran v1.4.x). The migration MUST NOT downgrade
    /// them — preserving paid state is the absolute priority.
    func test_migrate_existingPaidEssential_isNotDowngraded() {
        // Establish paid state BEFORE marking the v1.4.x signal — this
        // mirrors the "user paid for v1.5, then we ship a build with
        // the migration code" production sequence.
        XCTAssertEqual(LicenseManager.activate(key: "VAKTER-DEV-ESSENTIAL"),
                       .activated(.essential))
        XCTAssertEqual(LicenseManager.currentTier(), .essential)

        // Now stamp the v1.4.x marker to simulate "this Mac also ran
        // v1.4.x at some point."
        LicenseManager._testSetV144Marker(true)

        LicenseManager.migrateFromV144IfNeeded()

        XCTAssertEqual(LicenseManager.currentTier(), .essential,
                       "paid Essential license must survive migration — never downgrade a paying user")
        XCTAssertTrue(LicenseManager.isPaid(),
                      "isPaid() must continue to report true for the paid user")
        XCTAssertTrue(LicenseManager.isAIFeatureUnlocked(),
                      "AI features must remain unlocked for the paid user")
        // Migration sees the non-empty Keychain and routes through the
        // "not a v1.4.x upgrader" branch — origin stays .fresh. This is
        // intentional: a paid v1.5 user is conceptually a fresh install
        // even if the Mac also happened to run v1.4.x in the past, because
        // the grandfather flow is for "I never paid, am I locked out?" —
        // a paid user is by definition not locked out.
        XCTAssertEqual(LicenseManager.currentOrigin(), .fresh,
                       "paid user with non-empty Keychain is treated as a fresh install for origin purposes")
    }

    /// The single source of truth for AI-feature gating. This is the
    /// contract every AI surface MUST observe, so it gets its own test
    /// independent of `isPaid()` to lock the relationship in.
    ///
    /// Specifically: `.free` AND grandfathered (`Origin.upgraded` with
    /// `Tier.free`) both block AI; `.essential` and `.business` both
    /// unlock AI.
    func test_isAIFeatureUnlocked_freeAndGrandfatheredBothLocked() {
        // 1. Net-new install on the Free tier — locked.
        XCTAssertEqual(LicenseManager.currentTier(), .free)
        XCTAssertFalse(LicenseManager.isAIFeatureUnlocked(),
                       "fresh Free tier must lock AI")

        // 2. Grandfathered v1.4.x upgrader on Free tier — STILL locked.
        //    This is the load-bearing assertion for the pricing contract:
        //    "anti-theft stays free forever" does NOT mean "AI stays
        //    free for upgraders." Upgraders see the same Upgrade
        //    affordance as fresh users.
        LicenseManager._testSetV144Marker(true)
        LicenseManager.migrateFromV144IfNeeded()
        XCTAssertEqual(LicenseManager.currentOrigin(), .upgraded)
        XCTAssertEqual(LicenseManager.currentTier(), .free)
        XCTAssertFalse(LicenseManager.isAIFeatureUnlocked(),
                       "grandfathered (Origin.upgraded + Tier.free) must lock AI")

        // 3. Essential — unlocked.
        XCTAssertEqual(LicenseManager.activate(key: "VAKTER-DEV-ESSENTIAL"),
                       .activated(.essential))
        XCTAssertTrue(LicenseManager.isAIFeatureUnlocked(),
                      "Essential tier must unlock AI")

        // 4. Business — unlocked.
        XCTAssertEqual(LicenseManager.activate(key: "VAKTER-DEV-BUSINESS"),
                       .activated(.business))
        XCTAssertTrue(LicenseManager.isAIFeatureUnlocked(),
                      "Business tier must unlock AI")

        // 5. Defensive: dev-Free key resolves to Tier.free and AI is
        //    locked (the dev key is just a deterministic way to set the
        //    Free tier; it must not accidentally unlock AI).
        XCTAssertEqual(LicenseManager.activate(key: "VAKTER-DEV-FREE"),
                       .activated(.free))
        XCTAssertFalse(LicenseManager.isAIFeatureUnlocked(),
                       "VAKTER-DEV-FREE must NOT unlock AI features")
    }
}
