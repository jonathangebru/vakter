import XCTest
import CoreLocation
@testable import VakterShared

/// Unit tests for the v0.9 shared-module features:
///   - `LocalePhrases`         — locale resolution + substitution
///   - `EvidenceDelivery`      — body composition + script generation
///   - `EvidenceRecipientStore`— round-trip persistence
///   - `MenubarAppearance`     — enum + store round-trip
///   - `AlarmSound`            — new locale-specific siren cases
///   - `Zipper`                — error semantics on edge cases
final class V09FeaturesTests: XCTestCase {

    // MARK: LocalePhrases

    func test_localePhrases_englishDefault() {
        let s = LocalePhrases.text(.alarmVoiceCue, locale: Locale(identifier: "en-US"))
        XCTAssertTrue(s.contains("MacBook"), "English phrase should reference MacBook")
    }

    func test_localePhrases_dutchLookup() {
        let s = LocalePhrases.text(.alarmVoiceCue, locale: Locale(identifier: "nl-NL"))
        XCTAssertTrue(s.contains("MacBook"), "Dutch phrase still references MacBook brand term")
        XCTAssertTrue(s.contains("wordt") || s.contains("gevolgd"),
                      "Dutch phrase should contain Dutch words — got '\(s)'")
    }

    func test_localePhrases_japaneseLookup() {
        let s = LocalePhrases.text(.alarmVoiceCue, locale: Locale(identifier: "ja-JP"))
        XCTAssertTrue(s.contains("MacBook"), "Japanese phrase still references MacBook")
        XCTAssertTrue(s.contains("追跡"), "Japanese phrase should contain 追跡 (track)")
    }

    func test_localePhrases_unknownLocaleFallsBackToEnglish() {
        let s = LocalePhrases.text(.alarmVoiceCue, locale: Locale(identifier: "zu-ZA"))
        // Should be English fallback
        XCTAssertTrue(s.contains("MacBook"))
    }

    func test_localePhrases_substitution_replacesTokens() {
        let s = LocalePhrases.text(
            .evidenceLocationLine,
            locale: Locale(identifier: "en-US"),
            substitutions: ["maps_url": "https://maps.apple.com/?ll=1,2"]
        )
        XCTAssertTrue(s.contains("https://maps.apple.com/?ll=1,2"))
        XCTAssertFalse(s.contains("{maps_url}"), "raw token must be replaced")
    }

    func test_voiceLanguageTag_perLocale() {
        XCTAssertEqual(LocalePhrases.voiceLanguageTag(for: Locale(identifier: "en-US")), "en-US")
        XCTAssertEqual(LocalePhrases.voiceLanguageTag(for: Locale(identifier: "nl-NL")), "nl-NL")
        // macOS canonicalises "no" → "nb" — both should map to our .no entry.
        XCTAssertEqual(LocalePhrases.voiceLanguageTag(for: Locale(identifier: "nb-NO")), "nb-NO")
        XCTAssertEqual(LocalePhrases.voiceLanguageTag(for: Locale(identifier: "no")),    "nb-NO")
        XCTAssertEqual(LocalePhrases.voiceLanguageTag(for: Locale(identifier: "ja-JP")), "ja-JP")
        // Unknown locale → en-US fallback
        XCTAssertEqual(LocalePhrases.voiceLanguageTag(for: Locale(identifier: "zu-ZA")), "en-US")
    }

    // MARK: EvidenceDelivery

    func test_evidenceDelivery_bodyContainsTimestampReasonAndFooter() {
        let delivery = iMessageEvidenceDelivery()
        let bundle = EvidenceBundle(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            reasonLine: "Reason X",
            mode: .normal,
            photoURLs: [],
            location: nil,
            lastKnownLocation: nil,
            lastKnownLocationAge: nil,
            locale: Locale(identifier: "en-US")
        )
        let body = delivery.renderBody(bundle)
        XCTAssertTrue(body.contains("Reason X"), "body should include the reason line")
        XCTAssertTrue(body.contains("Photos attached") || body.contains("Vakter"),
                      "body should include footer")
    }

    func test_evidenceDelivery_bodyUsesFreshLocationWhenAvailable() {
        let delivery = iMessageEvidenceDelivery()
        let bundle = EvidenceBundle(
            reasonLine: "x",
            mode: .normal,
            photoURLs: [],
            location: CLLocationCoordinate2D(latitude: 52.3676, longitude: 4.9041),
            lastKnownLocation: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            lastKnownLocationAge: 9999
        )
        let body = delivery.renderBody(bundle)
        XCTAssertTrue(body.contains("52.367600"), "fresh location wins")
        XCTAssertFalse(body.contains("Last-known"), "should not include stale-line when fresh available")
    }

    func test_evidenceDelivery_bodyFallsBackToLastKnownWhenFreshNil() {
        let delivery = iMessageEvidenceDelivery()
        let bundle = EvidenceBundle(
            reasonLine: "x",
            mode: .normal,
            photoURLs: [],
            location: nil,
            lastKnownLocation: CLLocationCoordinate2D(latitude: 52.3676, longitude: 4.9041),
            lastKnownLocationAge: 120
        )
        let body = delivery.renderBody(bundle)
        XCTAssertTrue(body.contains("52.367600"))
        XCTAssertTrue(body.contains("Last-known") || body.contains("2 min"))
    }

    func test_evidenceDelivery_unavailableMessageWhenNoLocation() {
        let delivery = iMessageEvidenceDelivery()
        let bundle = EvidenceBundle(
            reasonLine: "x",
            mode: .normal,
            photoURLs: [],
            location: nil,
            lastKnownLocation: nil
        )
        let body = delivery.renderBody(bundle)
        XCTAssertTrue(body.contains("unavailable") || body.contains("Location"),
                      "should include the unavailable line")
    }

    func test_evidenceDelivery_mapsURL_isWellFormed() {
        let delivery = iMessageEvidenceDelivery()
        let url = delivery.mapsURL(for: CLLocationCoordinate2D(latitude: 52.367600, longitude: 4.904100))
        XCTAssertEqual(url, "https://maps.apple.com/?ll=52.367600,4.904100&q=Vakter+alert")
    }

    func test_evidenceDelivery_appleScript_escapesQuotes() throws {
        let delivery = iMessageEvidenceDelivery()
        let scriptURL = try delivery.writeScript(
            body: "Hello \"world\"",
            photoURLs: [],
            recipient: "+15551234567"
        )
        defer { try? FileManager.default.removeItem(at: scriptURL) }
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("\\\"world\\\""), "double quotes must be escaped")
        XCTAssertTrue(contents.contains("send \"Hello \\\"world\\\"\" to targetBuddy"))
    }

    func test_evidenceDelivery_appleScript_includesPhotoAttachments() throws {
        let delivery = iMessageEvidenceDelivery()
        let tmp1 = FileManager.default.temporaryDirectory.appendingPathComponent("a.jpg")
        let tmp2 = FileManager.default.temporaryDirectory.appendingPathComponent("b.jpg")
        let scriptURL = try delivery.writeScript(
            body: "x",
            photoURLs: [tmp1, tmp2],
            recipient: "+15551234567"
        )
        defer { try? FileManager.default.removeItem(at: scriptURL) }
        let contents = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("POSIX file \"\(tmp1.path)\""))
        XCTAssertTrue(contents.contains("POSIX file \"\(tmp2.path)\""))
    }

    // MARK: EvidenceRecipientStore

    func test_evidenceRecipientStore_roundTrip() {
        // Save → load → equal
        EvidenceRecipientStore.save(EvidenceRecipient(handle: "+15551234567"))
        let loaded = EvidenceRecipientStore.load()
        XCTAssertEqual(loaded?.handle, "+15551234567")
        // Cleanup
        EvidenceRecipientStore.save(nil)
        XCTAssertNil(EvidenceRecipientStore.load())
    }

    func test_evidenceRecipientStore_emptyHandleIsRejected() {
        EvidenceRecipientStore.save(EvidenceRecipient(handle: ""))
        XCTAssertNil(EvidenceRecipientStore.load(), "empty handle must not persist")
    }

    func test_evidenceRecipientStore_whitespaceTrimmed() {
        EvidenceRecipientStore.save(EvidenceRecipient(handle: "  +15551234567  "))
        XCTAssertEqual(EvidenceRecipientStore.load()?.handle, "+15551234567")
        EvidenceRecipientStore.save(nil)
    }

    // MARK: MenubarAppearance

    func test_menubarAppearance_roundTrip() {
        MenubarAppearanceStore.save(.fakeBattery)
        XCTAssertEqual(MenubarAppearanceStore.load(), .fakeBattery)
        MenubarAppearanceStore.save(.hidden)
        XCTAssertEqual(MenubarAppearanceStore.load(), .hidden)
        // Reset to default for following tests
        MenubarAppearanceStore.save(.lighthouse)
    }

    func test_menubarAppearance_defaultIsLighthouse() {
        // Force a missing/corrupt state by writing garbage then reading.
        let url = VakterConstants.supportDirectoryURL.appendingPathComponent("menubar-appearance.json")
        try? Data("nonsense".utf8).write(to: url, options: .atomic)
        XCTAssertEqual(MenubarAppearanceStore.load(), .lighthouse,
                       "corrupt JSON should default to lighthouse")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: AlarmSound — new cases

    func test_alarmSound_newCasesPresentAndCodable() throws {
        XCTAssertTrue(AlarmSound.allCases.contains(.japaneseTwoTone))
        XCTAssertTrue(AlarmSound.allCases.contains(.europeanNeeNaw))

        let jp = try JSONEncoder().encode(AlarmSound.japaneseTwoTone)
        let jpStr = String(data: jp, encoding: .utf8) ?? ""
        XCTAssertEqual(jpStr, #""japaneseTwoTone""#,
                       "rawValue is the persistence contract")
    }

    func test_alarmSound_userFacingStringsPresent() {
        for sound in AlarmSound.allCases {
            XCTAssertFalse(sound.displayName.isEmpty)
            XCTAssertFalse(sound.blurb.isEmpty)
            XCTAssertFalse(sound.icon.isEmpty)
        }
    }

    // MARK: AlarmSoundStore — persistence guarantees the onboarding
    //                        "Hear the alarm" step relies on (#26).

    /// When the user hasn't picked a sound yet, `.load()` must return
    /// `.classicSiren`. The onboarding step displays this back to the user
    /// as the "Selected sound" — if the default ever silently drifted to
    /// something else, the preview wouldn't match the user's expectation
    /// of "I haven't changed anything, so it should be the default."
    func test_alarmSoundStore_defaultsToClassicSiren() {
        // Wipe any persisted selection so we exercise the no-file path.
        let url = VakterConstants.supportDirectoryURL
            .appendingPathComponent("alarm-sound.json")
        try? FileManager.default.removeItem(at: url)
        XCTAssertEqual(AlarmSoundStore.load(), .classicSiren,
                       "no-file load should default to classicSiren")
    }

    /// After Settings → Sound saves a non-default selection, the same
    /// process (and any other process sharing the support directory,
    /// like the helper at alarm time) reads back the same value. This is
    /// the contract that lets the onboarding `hearAlarm` step honour the
    /// user's choice — both the helper-side `AudioController.startSiren`
    /// and the in-app `LocalAlarmPreview.play` resolve the user's
    /// selection via `AlarmSoundStore.load()`.
    func test_alarmSoundStore_persistsUserSelection() {
        let original = AlarmSoundStore.load()
        defer { AlarmSoundStore.save(original) }  // restore so we don't
                                                  // affect other tests

        for choice in [AlarmSound.sweepKlaxon, .pulseAlarm, .japaneseTwoTone] {
            AlarmSoundStore.save(choice)
            XCTAssertEqual(AlarmSoundStore.load(), choice,
                           "round-trip should return \(choice.rawValue)")
        }
    }

    /// If the persisted file is corrupt (manual edit, partial write
    /// during sudden power loss), `.load()` must still hand back a
    /// sensible value so the alarm never silently fails to play.
    func test_alarmSoundStore_corruptFileDefaultsToClassicSiren() {
        let url = VakterConstants.supportDirectoryURL
            .appendingPathComponent("alarm-sound.json")
        try? Data("not json".utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(AlarmSoundStore.load(), .classicSiren,
                       "corrupt JSON should default to classicSiren")
    }

    // MARK: Zipper

    func test_zipper_noInputsThrows() {
        XCTAssertThrowsError(try Zipper.zip(inputs: [], to: URL(fileURLWithPath: "/tmp/x.zip"))) { err in
            guard case Zipper.Error.noInputs = err else {
                XCTFail("expected .noInputs, got \(err)"); return
            }
        }
    }

    func test_zipper_zipsRealFiles() throws {
        let stage = FileManager.default.temporaryDirectory
            .appendingPathComponent("vakter-zipper-test-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }

        let f1 = stage.appendingPathComponent("a.txt")
        let f2 = stage.appendingPathComponent("b.txt")
        try "alpha".write(to: f1, atomically: true, encoding: .utf8)
        try "bravo".write(to: f2, atomically: true, encoding: .utf8)

        let outURL = stage.appendingPathComponent("out.zip")
        try Zipper.zip(inputs: [f1, f2], to: outURL, baseDirectory: stage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path))
        let size = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 0, "zip should be non-empty")
    }
}
