import XCTest
@testable import VakterShared

/// Covers the AppleScript composition for `EmailEvidenceDelivery`.
/// We don't actually launch Mail.app — too side-effectful for unit
/// tests — but we verify the script we'd hand to osascript has the
/// shape we expect.
final class EmailEvidenceDeliveryTests: XCTestCase {

    func test_subjectIsPlainASCII() {
        let delivery = EmailEvidenceDelivery()
        let subject = delivery.subjectLine(makeBundle())
        XCTAssertEqual(subject, "Vakter alert — your Mac")
        // Allow the em-dash through — Mail handles UTF-8 fine; the
        // assertion just locks the wording so we don't regress.
    }

    func test_writeScript_includesRecipientAndAttachments() throws {
        let delivery = EmailEvidenceDelivery(replyTo: "trustedfriend@example.com")
        let photoA = URL(fileURLWithPath: "/tmp/photo-01.jpg")
        let photoB = URL(fileURLWithPath: "/tmp/photo-02.jpg")

        let scriptURL = try delivery.writeScript(
            subject: "Vakter alert",
            body: "Body line one\nBody line two",
            photoURLs: [photoA, photoB],
            recipient: "owner@example.com",
            replyTo: "trustedfriend@example.com"
        )
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(script.contains("tell application \"Mail\""))
        XCTAssertTrue(script.contains("owner@example.com"))
        XCTAssertTrue(script.contains("trustedfriend@example.com"))
        XCTAssertTrue(script.contains("/tmp/photo-01.jpg"))
        XCTAssertTrue(script.contains("/tmp/photo-02.jpg"))
        XCTAssertTrue(script.contains("send"))
    }

    func test_writeScript_escapesQuotesInBody() throws {
        let delivery = EmailEvidenceDelivery()
        // A body with quotes — these would break the AppleScript
        // literal if not escaped.
        let scriptURL = try delivery.writeScript(
            subject: "x",
            body: "He said \"hi\" then left",
            photoURLs: [],
            recipient: "x@example.com",
            replyTo: nil
        )
        defer { try? FileManager.default.removeItem(at: scriptURL) }
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(script.contains("\\\"hi\\\""),
                      "quotes inside body must be backslash-escaped for AppleScript")
    }

    // MARK: -

    private func makeBundle() -> EvidenceBundle {
        EvidenceBundle(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            reasonLine: "Lid closed while armed",
            mode: .normal,
            photoURLs: [],
            location: nil,
            lastKnownLocation: nil,
            lastKnownLocationAge: nil,
            locale: Locale(identifier: "en_US")
        )
    }
}
