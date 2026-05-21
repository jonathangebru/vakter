import XCTest
@testable import VakterShared

/// Tests for the v1.4 stealth lock-screen overlay user-config model
/// and its disk-backed store.
///
/// We test:
///   - empty-field fallback behaviour (the overlay code path relies on
///     `displayMessage` never being empty)
///   - length-capping on init (oversized strings must be clipped, not
///     rejected)
///   - the loose phone-number heuristic that decides when the overlay
///     wires the callback as a tappable `tel:` link
///   - JSON round-trip persistence
///   - corrupt / missing on-disk file behaviour
///
/// These tests guard the persistence contract the menubar app
/// (Settings → General → "If found, please contact" + the alarm-state
/// transition in AppDelegate) depend on.
final class StealthOverlayConfigTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Wipe any prior on-disk config so tests don't bleed state from
        // each other (or from the user's real config when run locally).
        StealthOverlayConfigStore.reset()
    }

    override func tearDown() {
        StealthOverlayConfigStore.reset()
        super.tearDown()
    }

    // MARK: - Empty-field fallback

    func test_default_isEmpty() {
        let cfg = StealthOverlayConfig.default
        XCTAssertTrue(cfg.isEmpty)
        XCTAssertEqual(cfg.message, "")
        XCTAssertEqual(cfg.callbackNumber, "")
    }

    func test_displayMessage_fallsBackWhenBlank() {
        // The overlay code path treats `displayMessage` as the only
        // source of truth for what to render. It must never be empty.
        let cfg = StealthOverlayConfig.default
        XCTAssertFalse(cfg.displayMessage.isEmpty,
                       "empty config must produce a non-empty rendered message")
        // The default copy must be unambiguous — we verify a key phrase
        // is present so future copy edits stay visible to humans.
        XCTAssertTrue(
            cfg.displayMessage.lowercased().contains("recover"),
            "default copy should mention recovery — got '\(cfg.displayMessage)'"
        )
    }

    func test_displayMessage_returnsTrimmedUserMessageWhenSet() {
        let cfg = StealthOverlayConfig(
            message: "  Return to Jane Doe.  ",
            callbackNumber: ""
        )
        XCTAssertEqual(cfg.displayMessage, "Return to Jane Doe.",
                       "leading + trailing whitespace must be trimmed")
    }

    func test_displayMessage_blankWhitespaceCountsAsEmpty() {
        // User types only whitespace + newlines → fallback fires.
        let cfg = StealthOverlayConfig(message: "   \n\t  ", callbackNumber: "")
        XCTAssertTrue(cfg.isEmpty)
        XCTAssertFalse(cfg.displayMessage.isEmpty)
    }

    func test_displayCallback_nilWhenBlank() {
        let cfg = StealthOverlayConfig(message: "anything", callbackNumber: "  ")
        XCTAssertNil(cfg.displayCallback,
                     "whitespace-only callback must resolve to nil so the overlay omits the line")
    }

    // MARK: - Length capping

    func test_message_clippedAtMaxLength() {
        let oversized = String(repeating: "x", count: StealthOverlayConfig.maxMessageLength + 50)
        let cfg = StealthOverlayConfig(message: oversized, callbackNumber: "")
        XCTAssertEqual(cfg.message.count, StealthOverlayConfig.maxMessageLength)
    }

    func test_callback_clippedAtMaxLength() {
        let oversized = String(repeating: "1", count: StealthOverlayConfig.maxCallbackLength + 20)
        let cfg = StealthOverlayConfig(message: "", callbackNumber: oversized)
        XCTAssertEqual(cfg.callbackNumber.count, StealthOverlayConfig.maxCallbackLength)
    }

    // MARK: - Phone-number heuristic

    func test_phoneHeuristic_acceptsE164() {
        let cfg = StealthOverlayConfig(message: "", callbackNumber: "+15551234567")
        XCTAssertTrue(cfg.looksLikePhoneNumber)
        XCTAssertEqual(cfg.telURL?.absoluteString, "tel:+15551234567")
    }

    func test_phoneHeuristic_acceptsDashed() {
        let cfg = StealthOverlayConfig(message: "", callbackNumber: "555-123-4567")
        XCTAssertTrue(cfg.looksLikePhoneNumber)
        XCTAssertEqual(cfg.telURL?.absoluteString, "tel:5551234567")
    }

    func test_phoneHeuristic_acceptsParenthesised() {
        let cfg = StealthOverlayConfig(message: "", callbackNumber: "(555) 123 4567")
        XCTAssertTrue(cfg.looksLikePhoneNumber)
    }

    func test_phoneHeuristic_acceptsDottedInternational() {
        let cfg = StealthOverlayConfig(message: "", callbackNumber: "+44 20 7946 0958")
        XCTAssertTrue(cfg.looksLikePhoneNumber)
    }

    func test_phoneHeuristic_rejectsLetters() {
        // "Email: jane@example.com" must NOT be tappable as a tel: link.
        let cfg = StealthOverlayConfig(
            message: "",
            callbackNumber: "Email: jane@example.com"
        )
        XCTAssertFalse(cfg.looksLikePhoneNumber)
        XCTAssertNil(cfg.telURL)
    }

    func test_phoneHeuristic_rejectsTooShort() {
        // Less than 7 digits — could be an address ("1234"), not a phone.
        let cfg = StealthOverlayConfig(message: "", callbackNumber: "12345")
        XCTAssertFalse(cfg.looksLikePhoneNumber)
    }

    func test_phoneHeuristic_rejectsEmpty() {
        let cfg = StealthOverlayConfig(message: "", callbackNumber: "")
        XCTAssertFalse(cfg.looksLikePhoneNumber)
        XCTAssertNil(cfg.telURL)
    }

    func test_telURL_stripsFormattingButKeepsPlus() {
        let cfg = StealthOverlayConfig(message: "", callbackNumber: "+1 (555) 123.4567")
        XCTAssertEqual(cfg.telURL?.absoluteString, "tel:+15551234567")
    }

    // MARK: - Persistence round-trip

    func test_persistence_roundTrip() {
        let original = StealthOverlayConfig(
            message: "Please return to Jane Doe.",
            callbackNumber: "+1 555 123 4567"
        )
        StealthOverlayConfigStore.save(original)

        let loaded = StealthOverlayConfigStore.load()
        XCTAssertEqual(loaded.message, original.message)
        XCTAssertEqual(loaded.callbackNumber, original.callbackNumber)
        XCTAssertEqual(loaded, original)
    }

    func test_persistence_missingFileReturnsDefault() {
        // setUp() already removed the file. The first load must hand
        // back the default config — never crash, never return nil.
        let cfg = StealthOverlayConfigStore.load()
        XCTAssertEqual(cfg, .default)
        XCTAssertTrue(cfg.isEmpty)
    }

    func test_persistence_corruptFileReturnsDefault() {
        // Write garbage at the expected on-disk path. load() must
        // gracefully return the default rather than throw or crash.
        let url = VakterConstants.supportDirectoryURL
            .appendingPathComponent("stealth-overlay.json")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data("nonsense".utf8).write(to: url, options: .atomic)

        let cfg = StealthOverlayConfigStore.load()
        XCTAssertEqual(cfg, .default,
                       "corrupt JSON must recover to .default rather than crash")
    }

    func test_persistence_reset_removesFile() {
        StealthOverlayConfigStore.save(
            StealthOverlayConfig(message: "x", callbackNumber: "+15551234567")
        )
        let url = VakterConstants.supportDirectoryURL
            .appendingPathComponent("stealth-overlay.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "saved config should land on disk")

        StealthOverlayConfigStore.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "reset() must remove the on-disk file")
        XCTAssertEqual(StealthOverlayConfigStore.load(), .default)
    }

    func test_persistence_oversizedSurvivesRoundTrip_clipped() {
        // Even if a user (or our future remote-config) writes an
        // oversized config to disk, the model re-clips on decode so
        // the in-memory string always respects the cap.
        let oversized = String(repeating: "y", count: 1000)
        StealthOverlayConfigStore.save(
            StealthOverlayConfig(message: oversized, callbackNumber: "")
        )
        let loaded = StealthOverlayConfigStore.load()
        XCTAssertLessThanOrEqual(
            loaded.message.count, StealthOverlayConfig.maxMessageLength,
            "oversize message must be clipped after a save+load round trip"
        )
    }
}
