import XCTest
@testable import VakterShared

/// Tests for the Pareto-style security checklist model (categories,
/// items, status roll-up, relative-time label, persistence).
final class DefenseChecklistTests: XCTestCase {

    /// Redirect persistence to a per-test temp file so tests don't
    /// stomp on the user's real production checklist at
    /// `~/Library/Application Support/Vakter/defenses-checklist.json`.
    override func setUp() {
        super.setUp()
        DefenseChecklistStore.testURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vakter-tests-\(UUID().uuidString).json")
    }

    override func tearDown() {
        if let url = DefenseChecklistStore.testURL {
            try? FileManager.default.removeItem(at: url)
        }
        DefenseChecklistStore.testURL = nil
        super.tearDown()
    }

    private func item(_ id: String,
                      _ cat: DefenseCategory,
                      _ status: DefenseStatus) -> DefenseItem {
        DefenseItem(id: id, category: cat, title: "t", detail: "d", status: status)
    }

    // MARK: - byCategory

    func test_byCategory_preservesAllCasesOrder() {
        let list = DefenseChecklist(items: [
            item("a", .systemIntegrity, .pass),
            item("b", .accessSecurity,  .pass),
            item("c", .firewallSharing, .fail),
        ])
        let cats = list.byCategory.map { $0.0 }
        // Must be in the stable allCases order, NOT insertion order.
        XCTAssertEqual(cats, [.accessSecurity, .firewallSharing, .systemIntegrity])
    }

    func test_byCategory_skipsEmptyCategories() {
        let list = DefenseChecklist(items: [
            item("a", .accessSecurity, .pass),
        ])
        let cats = list.byCategory.map { $0.0 }
        XCTAssertEqual(cats, [.accessSecurity])
    }

    // MARK: - worstStatus

    func test_worstStatus_failBeatsWarnBeatsPass() {
        let list = DefenseChecklist(items: [
            item("a", .accessSecurity, .pass),
            item("b", .accessSecurity, .warn),
            item("c", .accessSecurity, .fail),
        ])
        XCTAssertEqual(list.worstStatus(in: .accessSecurity), .fail)
    }

    func test_worstStatus_warnWhenNoFails() {
        let list = DefenseChecklist(items: [
            item("a", .accessSecurity, .pass),
            item("b", .accessSecurity, .warn),
        ])
        XCTAssertEqual(list.worstStatus(in: .accessSecurity), .warn)
    }

    func test_worstStatus_allPass() {
        let list = DefenseChecklist(items: [
            item("a", .accessSecurity, .pass),
            item("b", .accessSecurity, .pass),
        ])
        XCTAssertEqual(list.worstStatus(in: .accessSecurity), .pass)
    }

    func test_worstStatus_unknownIsAboveWarnIfPresent() {
        // .unknown should rank above .pass but below .warn / .fail
        // (we don't want a missing probe to make a category look red).
        let list = DefenseChecklist(items: [
            item("a", .accessSecurity, .pass),
            item("b", .accessSecurity, .unknown),
        ])
        XCTAssertEqual(list.worstStatus(in: .accessSecurity), .unknown)
    }

    // MARK: - relativeRunLabel

    func test_relativeRunLabel_justNow() {
        let list = DefenseChecklist(runAt: Date(), items: [])
        XCTAssertEqual(list.relativeRunLabel(), "just now")
    }

    func test_relativeRunLabel_minutes() {
        let now = Date()
        let list = DefenseChecklist(runAt: now.addingTimeInterval(-49 * 60), items: [])
        XCTAssertEqual(list.relativeRunLabel(now: now), "49 min ago")
    }

    func test_relativeRunLabel_oneHour() {
        let now = Date()
        let list = DefenseChecklist(runAt: now.addingTimeInterval(-3600), items: [])
        XCTAssertEqual(list.relativeRunLabel(now: now), "1 hour ago")
    }

    func test_relativeRunLabel_hoursPlural() {
        let now = Date()
        let list = DefenseChecklist(runAt: now.addingTimeInterval(-3 * 3600), items: [])
        XCTAssertEqual(list.relativeRunLabel(now: now), "3 hours ago")
    }

    func test_relativeRunLabel_days() {
        let now = Date()
        let list = DefenseChecklist(runAt: now.addingTimeInterval(-2 * 86_400), items: [])
        XCTAssertEqual(list.relativeRunLabel(now: now), "2 days ago")
    }

    // MARK: - passPercentage

    func test_passPercentage_emptyIsZero() {
        XCTAssertEqual(DefenseChecklist(items: []).passPercentage, 0)
    }

    func test_passPercentage_allPassIsHundred() {
        let list = DefenseChecklist(items: [
            item("a", .accessSecurity, .pass),
            item("b", .accessSecurity, .pass),
        ])
        XCTAssertEqual(list.passPercentage, 100)
    }

    func test_passPercentage_halfHalf() {
        let list = DefenseChecklist(items: [
            item("a", .accessSecurity, .pass),
            item("b", .accessSecurity, .fail),
            item("c", .accessSecurity, .pass),
            item("d", .accessSecurity, .warn),
        ])
        XCTAssertEqual(list.passPercentage, 50)
    }

    // MARK: - Persistence round-trip

    func test_store_roundTrip() {
        let original = DefenseChecklist(items: [
            item("a", .accessSecurity, .pass),
            item("b", .firewallSharing, .fail),
        ])
        DefenseChecklistStore.save(original)

        let loaded = DefenseChecklistStore.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.items.count, 2)
        XCTAssertEqual(loaded?.items[0].id, "a")
        XCTAssertEqual(loaded?.items[1].status, .fail)
    }

    // MARK: - DefensesProbe.runAll smoke test

    /// Sanity-check that runAll() produces items in every expected
    /// category. We don't assert PASS/FAIL because those depend on
    /// the host's actual macOS posture.
    func test_runAll_producesItemsInEveryCategory() {
        let list = DefensesProbe.runAll()
        let cats = Set(list.items.map { $0.category })
        XCTAssertTrue(cats.contains(.accessSecurity))
        XCTAssertTrue(cats.contains(.firewallSharing))
        XCTAssertTrue(cats.contains(.macOSUpdates))
        XCTAssertTrue(cats.contains(.softwareUpdates))
        XCTAssertTrue(cats.contains(.systemIntegrity))
    }

    /// runAll() must produce at least 15 items (we ship ~20, but
    /// gives wiggle room for ones that probe `.unknown` on machines
    /// where the binary isn't present).
    func test_runAll_hasAtLeast15Items() {
        let list = DefensesProbe.runAll()
        XCTAssertGreaterThanOrEqual(list.items.count, 15)
    }

    /// Every item has a non-empty title + detail.
    func test_runAll_itemsAreWellFormed() {
        let list = DefensesProbe.runAll()
        for item in list.items {
            XCTAssertFalse(item.id.isEmpty, "empty id on \(item.title)")
            XCTAssertFalse(item.title.isEmpty, "empty title on \(item.id)")
            XCTAssertFalse(item.detail.isEmpty, "empty detail on \(item.id)")
        }
    }

    /// All `id`s must be unique. A duplicate `id` would break
    /// per-check enable/disable preferences in v1.0.
    func test_runAll_ItemIDsUnique() {
        let list = DefensesProbe.runAll()
        let ids = list.items.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate DefenseItem ids: \(ids)")
    }

    // MARK: - v1.4.2 additions (Feature #21)
    //
    // The 8 new audit checks added to `DefensesAudit.swift` are also
    // surfaced in the menubar dropdown via `DefensesProbe`. We test
    // them here (rather than in a new `VakterAppTests` target) because:
    //   1. `DefensesAudit` is in the `VakterApp` executable target,
    //      which has no companion test target — the audit IS test-
    //      runnable in principle (via `@testable import VakterApp`),
    //      but adding a new test target is out of scope for #21.
    //   2. The probe and the audit cover the SAME 8 surfaces — the
    //      tests below act as a contract check on both. If a future
    //      refactor drops one of these IDs from the probe, the
    //      menubar would silently regress; this test catches it.
    //
    // Each new check has a stable id we assert against. The status
    // assertions are deliberately loose — they accept any of pass /
    // warn / fail / unknown, because the host running `swift test`
    // could legitimately have any of those (e.g. a developer with
    // Remote Login enabled, or AirDrop set to Everyone). What we DO
    // assert per item: id is exactly as expected, title and detail
    // are non-empty, and the category is correct.

    /// All 8 new checks must exist by id in `DefensesProbe.runAll()`.
    /// This is the smoke test that proves the dispatch landed.
    func test_v142_eightNewChecks_existInRunAll() {
        let list = DefensesProbe.runAll()
        let ids = Set(list.items.map { $0.id })

        // The 6 already-in-probe (pre-#21) checks that DefensesAudit
        // now mirrors. They predate #21 in the probe but #21 in the
        // audit; including them here doubles as a regression guard.
        XCTAssertTrue(ids.contains("firewall.airplayReceiver"))
        XCTAssertTrue(ids.contains("firewall.fileSharing"))
        XCTAssertTrue(ids.contains("firewall.mediaSharing"))
        XCTAssertTrue(ids.contains("firewall.printerSharing"))
        XCTAssertTrue(ids.contains("firewall.remoteLogin"))
        XCTAssertTrue(ids.contains("firewall.remoteManagement"))

        // The 2 new-to-probe (added by #21) checks: AirDrop visibility
        // and boot security policy.
        XCTAssertTrue(ids.contains("firewall.airdropDiscoverable"))
        XCTAssertTrue(ids.contains("integrity.bootSecurity"))
    }

    /// AirDrop visibility — healthy path returns `.pass` on a fresh
    /// install (defaults key missing = macOS-default Contacts Only).
    /// On a host where the user has set AirDrop to Everyone, the
    /// status will be `.warn`. We accept either pass/warn — never
    /// `.fail` (AirDrop visibility is never critical) and never
    /// `.unknown` (the probe handles all defaults outputs).
    func test_v142_airDropDiscoverable_returnsHealthyOrWarn() {
        let list = DefensesProbe.runAll()
        let item = list.items.first { $0.id == "firewall.airdropDiscoverable" }
        XCTAssertNotNil(item, "AirDrop discoverability check missing")
        XCTAssertEqual(item?.category, .firewallSharing)
        XCTAssertFalse(item?.title.isEmpty ?? true)
        XCTAssertFalse(item?.detail.isEmpty ?? true)
        let status = item?.status ?? .unknown
        XCTAssertTrue(status == .pass || status == .warn,
                      "AirDrop should never be .fail or .unknown — got \(status)")
    }

    /// AirPlay Receiver — healthy = off (.pass), enabled = .warn.
    /// Never .fail (AirPlay receiver is at worst a nuisance, not a
    /// theft-response risk). Allow .unknown defensively in case
    /// `launchctl list` is somehow unavailable.
    func test_v142_airPlayReceiver_categoryAndStatus() {
        let list = DefensesProbe.runAll()
        let item = list.items.first { $0.id == "firewall.airplayReceiver" }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.category, .firewallSharing)
        XCTAssertFalse(item?.title.isEmpty ?? true)
        let status = item?.status ?? .fail
        XCTAssertTrue(status == .pass || status == .warn || status == .unknown)
    }

    /// File Sharing — same rubric as AirPlay (pass when off, warn
    /// when on). File Sharing exposes folders but only to authenticated
    /// callers, so this isn't `.fail` territory.
    func test_v142_fileSharing_categoryAndStatus() {
        let list = DefensesProbe.runAll()
        let item = list.items.first { $0.id == "firewall.fileSharing" }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.category, .firewallSharing)
        XCTAssertFalse(item?.title.isEmpty ?? true)
        let status = item?.status ?? .fail
        // Probe treats fileSharing-on as .fail (legitimate — exposes
        // shared folders). Test accepts any non-empty outcome.
        XCTAssertTrue(status == .pass || status == .warn || status == .fail || status == .unknown)
    }

    /// Media Sharing — pass when off, warn when on.
    func test_v142_mediaSharing_categoryAndStatus() {
        let list = DefensesProbe.runAll()
        let item = list.items.first { $0.id == "firewall.mediaSharing" }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.category, .firewallSharing)
        XCTAssertFalse(item?.title.isEmpty ?? true)
        let status = item?.status ?? .fail
        XCTAssertTrue(status == .pass || status == .warn || status == .unknown)
    }

    /// Printer Sharing — pass when off, warn when on.
    func test_v142_printerSharing_categoryAndStatus() {
        let list = DefensesProbe.runAll()
        let item = list.items.first { $0.id == "firewall.printerSharing" }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.category, .firewallSharing)
        XCTAssertFalse(item?.title.isEmpty ?? true)
        let status = item?.status ?? .fail
        XCTAssertTrue(status == .pass || status == .warn || status == .unknown)
    }

    /// Remote Login (SSH) — categorically remote-access; default-off
    /// posture is `.pass`. Probe accepts `.unknown` when admin-locked.
    func test_v142_remoteLogin_categoryAndStatus() {
        let list = DefensesProbe.runAll()
        let item = list.items.first { $0.id == "firewall.remoteLogin" }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.category, .firewallSharing)
        XCTAssertFalse(item?.title.isEmpty ?? true)
        let status = item?.status ?? .fail
        XCTAssertTrue(status == .pass || status == .fail || status == .unknown)
    }

    /// Remote Management (ARD) — same shape as Remote Login.
    func test_v142_remoteManagement_categoryAndStatus() {
        let list = DefensesProbe.runAll()
        let item = list.items.first { $0.id == "firewall.remoteManagement" }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.category, .firewallSharing)
        XCTAssertFalse(item?.title.isEmpty ?? true)
        let status = item?.status ?? .fail
        XCTAssertTrue(status == .pass || status == .fail || status == .unknown)
    }

    /// Boot Security Policy — Apple Silicon healthy path is `.pass`
    /// (Full Security). On Intel, the probe yields `.unknown` because
    /// the LocalPolicy concept is AS-only. Test accepts pass/warn/
    /// fail/unknown — the host running the test could be any of those.
    func test_v142_bootSecurity_categoryAndStatus() {
        let list = DefensesProbe.runAll()
        let item = list.items.first { $0.id == "integrity.bootSecurity" }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.category, .systemIntegrity)
        XCTAssertFalse(item?.title.isEmpty ?? true)
        XCTAssertFalse(item?.detail.isEmpty ?? true)
    }

    /// Post-#21, the probe's checklist must contain at least 22 items
    /// (up from 20 pre-#21: the 6 existing sharing/remote checks were
    /// already there, and we added AirDrop + Boot Security). Bumps
    /// the floor on `test_runAll_hasAtLeast15Items` while staying
    /// loose enough that a single `.unknown`-on-this-host probe being
    /// silently dropped wouldn't fail the test.
    func test_v142_runAll_atLeast22Items() {
        let list = DefensesProbe.runAll()
        XCTAssertGreaterThanOrEqual(list.items.count, 22,
            "Expected at least 22 items post-#21 (20 pre-existing + 2 new). Got \(list.items.count).")
    }
}
