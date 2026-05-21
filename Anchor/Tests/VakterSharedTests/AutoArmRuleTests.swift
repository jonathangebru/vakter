import XCTest
@testable import VakterShared

/// Covers AutoArmRule's Codable round-trip — important because the
/// rule file on disk must survive across Vakter releases. Schema breakage
/// here means users lose their rules silently on upgrade.
final class AutoArmRuleTests: XCTestCase {

    func test_geofenceRule_codableRoundTrip() throws {
        let original = AutoArmRule(
            name: "Leaving home",
            trigger: .geofenceExit(latitude: 52.379, longitude: 4.900, radiusMeters: 80)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AutoArmRule.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_wifiRule_codableRoundTrip() throws {
        let original = AutoArmRule(
            name: "Off home Wi-Fi",
            trigger: .wifiDisconnect(ssids: ["HomeNet", "HomeNet-5G"])
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AutoArmRule.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_idleRule_codableRoundTrip() throws {
        let original = AutoArmRule(
            name: "Idle 5 minutes",
            trigger: .idleForSeconds(seconds: 300)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AutoArmRule.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_dailyRule_codableRoundTrip() throws {
        let original = AutoArmRule(
            name: "End of workday",
            trigger: .dailyAt(hour: 18, minute: 0)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AutoArmRule.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_storeRoundTrip() {
        let rules = [
            AutoArmRule(name: "Off home Wi-Fi",
                        trigger: .wifiDisconnect(ssids: ["HomeNet"])),
            AutoArmRule(name: "Idle 10 minutes",
                        trigger: .idleForSeconds(seconds: 600))
        ]
        XCTAssertTrue(AutoArmRuleStore.save(rules))
        let loaded = AutoArmRuleStore.load()
        // Each test runs against the user's real support directory —
        // we can't guarantee 0 pre-existing rules. Just assert ours
        // round-tripped.
        XCTAssertTrue(loaded.contains(rules[0]))
        XCTAssertTrue(loaded.contains(rules[1]))
        // Clean up.
        let filtered = loaded.filter { rules.firstIndex(of: $0) == nil }
        _ = AutoArmRuleStore.save(filtered)
    }
}
