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
}
