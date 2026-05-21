import XCTest
@testable import VakterShared

/// Tests for the `VakterMode` rename + `.cafe` case introduced in v0.9.
final class VakterModeTests: XCTestCase {

    /// rawValues must NOT change — they're persisted to disk by
    /// `ActiveModeStore`. Changing one silently resets every user's mode.
    func test_rawValues_arePersistenceStable() {
        XCTAssertEqual(VakterMode.normal.rawValue,  "normal")
        XCTAssertEqual(VakterMode.travel.rawValue,  "travel")
        XCTAssertEqual(VakterMode.library.rawValue, "library")
        XCTAssertEqual(VakterMode.loaner.rawValue,  "loaner")
        XCTAssertEqual(VakterMode.cafe.rawValue,    "cafe")
    }

    /// `VakterMode` typealias keeps old call sites compiling.
    func test_anchorModeTypealias_compiles() {
        let m: VakterMode = .cafe
        XCTAssertEqual(m, VakterMode.cafe)
    }

    /// Old saved JSON files (pre-rename, encoded as raw string "normal")
    /// must keep decoding. Decoder is keyed by raw String — that's the
    /// safety guarantee that lets us rename the type without a migration.
    func test_existingJSON_decodesIntoVakterMode() throws {
        let oldJSON = #""normal""#.data(using: .utf8)!
        let mode = try JSONDecoder().decode(VakterMode.self, from: oldJSON)
        XCTAssertEqual(mode, .normal)
    }

    /// `.cafe`-specific parameters: 12 s grace, silent, 30 s cap, calmChime.
    func test_cafeMode_hasDistinctiveParameters() {
        let p = ModeParameters.parameters(for: .cafe)
        XCTAssertEqual(p.graceSeconds, 12)
        XCTAssertEqual(p.audible, false)
        XCTAssertEqual(p.photoCadence, .normal)
        XCTAssertEqual(p.alarmCapSeconds, 30)
        XCTAssertEqual(p.defaultAlarmSound, .calmChime)
    }

    /// The other 4 modes must keep their pre-existing parameters intact.
    func test_existingModes_unchanged() {
        XCTAssertEqual(ModeParameters.parameters(for: .normal).graceSeconds, 8)
        XCTAssertTrue (ModeParameters.parameters(for: .normal).audible)
        XCTAssertNil  (ModeParameters.parameters(for: .normal).alarmCapSeconds)

        XCTAssertEqual(ModeParameters.parameters(for: .travel).graceSeconds, 5)
        XCTAssertEqual(ModeParameters.parameters(for: .travel).photoCadence, .burst)

        XCTAssertFalse(ModeParameters.parameters(for: .library).audible)
        XCTAssertEqual(ModeParameters.parameters(for: .library).photoCadence, .burst)
    }

    /// `.cafe` must be in `.allCases` for ForEach-based UIs to pick it up.
    func test_cafe_isInAllCases() {
        XCTAssertTrue(VakterMode.allCases.contains(.cafe))
        XCTAssertEqual(VakterMode.allCases.count, 5)
    }

    /// `displayName` + `blurb` must be non-empty for every case.
    func test_userFacingStrings_allPresent() {
        for mode in VakterMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "displayName missing for \(mode)")
            XCTAssertFalse(mode.blurb.isEmpty, "blurb missing for \(mode)")
        }
    }
}
