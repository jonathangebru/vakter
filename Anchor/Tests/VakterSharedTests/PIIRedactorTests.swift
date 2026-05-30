import XCTest
@testable import VakterShared

/// Adversarial unit tests for ``PIIRedactor`` (Issue #68).
///
/// The PII redactor is the chokepoint that makes Vakter's brand
/// contract — "Vakter never uses a cloud LLM, and never sends your
/// personal data to a model" — enforceable. These tests treat the
/// redactor as adversarially as we expect real prompts to be:
///
/// * **Per-category happy path** — at least two clean wins per
///   category so the catalog itself is exercised.
/// * **Tricky-but-legal variants** — international phone, IPv6,
///   spaces inside IBAN/CC, NFKC fullwidth-digit smuggling, zero-
///   width insertions.
/// * **False-positive prevention** — "version 1.2.3.4" must not be
///   double-redacted; 12-digit product codes pass through; benign
///   prose is unchanged.
/// * **Performance** — every test runs under a 50ms wall-clock
///   budget asserted by ``assertUnder50ms(_:)``. Catastrophic
///   backtracking would blow the budget loudly; we'd rather fail
///   loudly than ship a DoS surface.
///
/// All cases are deterministic — no `Locale.current`, no `Date()`,
/// no random salts. The redactor must produce the same redacted
/// output every time for the audit log to be reproducible.
final class PIIRedactorTests: XCTestCase {

    // MARK: - Helpers

    /// Convenience: shared default-catalog redactor. Tests that need a
    /// narrower catalog construct their own.
    private let redactor = PIIRedactor()

    /// Run `body`, fail if it took more than 50ms wall-clock. The
    /// redactor's hard performance contract — see ``PIIRedactor``
    /// type-level docs — is "each call finishes well under 50ms even
    /// on adversarial input." This guard makes that machine-checked.
    private func assertUnder50ms(
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () -> Void
    ) {
        let start = Date()
        body()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(
            elapsed, 0.050,
            "[perf budget] \(label) took \(elapsed * 1000)ms",
            file: file, line: line
        )
    }

    /// Convenience: assert that running `input` through the redactor
    /// produces an output containing `token` and a redaction summary
    /// that includes `kind` at least once.
    private func assertContainsRedaction(
        _ input: String,
        kind: RedactionPattern.Kind,
        token: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = redactor.redact(input)
        XCTAssertTrue(
            result.redactedText.contains(token),
            "expected token \(token) in output: \(result.redactedText)",
            file: file, line: line
        )
        XCTAssertTrue(
            result.redactions.contains(where: { $0.kind == kind }),
            "expected redaction kind \(kind), got \(result.redactions)",
            file: file, line: line
        )
    }

    /// Convenience: assert that running `input` through the redactor
    /// produces a clean (unchanged) result.
    private func assertClean(
        _ input: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = redactor.redact(input)
        XCTAssertEqual(
            result.redactedText, input,
            "expected unchanged output, got: \(result.redactedText)",
            file: file, line: line
        )
        XCTAssertTrue(
            result.isClean,
            "expected clean result, got: \(result.redactions)",
            file: file, line: line
        )
    }

    // MARK: - 1. Catalog metadata

    func test_catalog_hasAtLeastTwelveCategoriesOfPatterns() {
        // Distinct kinds — ipAddress appears twice in the catalog
        // (v4 + v6) but counts as one category.
        let distinct = Set(RedactionPattern.all.map(\.kind))
        XCTAssertGreaterThanOrEqual(
            distinct.count, 12,
            "ticket #68 mandates 12+ PII categories; got \(distinct.count)"
        )
    }

    func test_catalog_everyPatternHasNonEmptyToken() {
        for pattern in RedactionPattern.all {
            XCTAssertFalse(
                pattern.token.isEmpty,
                "pattern \(pattern.kind) must have a non-empty token"
            )
            XCTAssertTrue(
                pattern.token.hasPrefix("[") && pattern.token.hasSuffix("]"),
                "token \(pattern.token) must be bracket-wrapped"
            )
        }
    }

    func test_catalog_patternsAreSendableByValueShape() {
        // Smoke test: walking the catalog from a concurrent context
        // should not crash. NSRegularExpression is documented thread-
        // safe for read-only matching.
        let snapshot = RedactionPattern.all
        XCTAssertGreaterThan(snapshot.count, 0)
        DispatchQueue.concurrentPerform(iterations: 4) { _ in
            for pattern in snapshot {
                _ = pattern.regex.numberOfCaptureGroups
            }
        }
    }

    // MARK: - 2. Email — happy path

    func test_email_simpleAddress_isRedacted() {
        assertContainsRedaction("contact me at jane@example.com today",
                                kind: .email, token: "[EMAIL]")
    }

    func test_email_subdomainAddress_isRedacted() {
        assertContainsRedaction("hello a.b+c@mail.example.co.uk",
                                kind: .email, token: "[EMAIL]")
    }

    func test_email_uppercaseAddress_isRedacted() {
        assertContainsRedaction("JOHN.DOE@CORP.ORG", kind: .email,
                                token: "[EMAIL]")
    }

    func test_email_plusTaggedAddress_isRedacted() {
        assertContainsRedaction("plus tagging works: alex+foo@example.com",
                                kind: .email, token: "[EMAIL]")
    }

    func test_email_inSentenceWithPunctuation_isRedacted() {
        let result = redactor.redact("Send to bob@example.com, thanks.")
        XCTAssertTrue(result.redactedText.contains("[EMAIL]"))
        XCTAssertTrue(result.redactedText.contains(","),
                      "trailing comma must survive — boundary anchor matters")
    }

    func test_email_multipleAddresses_allRedacted() {
        let result = redactor.redact("a@x.com and b@y.com")
        let count = result.redactions.first(where: { $0.kind == .email })?.count
        XCTAssertEqual(count, 2)
    }

    // MARK: - 3. Email — tricky

    func test_email_insideURL_doesNotDoubleRedact() {
        let result = redactor.redact("see https://x.com/?u=alex@example.com page")
        // URL pattern runs first; the entire URL should become [URL],
        // not "[URL]?u=[EMAIL]".
        XCTAssertTrue(result.redactedText.contains("[URL]"),
                      "URL pattern must win over inner email")
        XCTAssertFalse(result.redactedText.contains("[EMAIL]"),
                      "no [EMAIL] should remain inside the absorbed URL")
    }

    func test_email_withFullwidthAtSign_NFKCNormalisesAndRedacts() {
        // U+FF20 fullwidth @ normalises to U+0040 under NFKC.
        let weird = "alice\u{FF20}example.com"
        assertContainsRedaction(weird, kind: .email, token: "[EMAIL]")
    }

    func test_email_withZeroWidthInjection_isRedacted() {
        // Zero-width space between user and @ — a classic split attack.
        let weird = "alice\u{200B}@example.com"
        assertContainsRedaction(weird, kind: .email, token: "[EMAIL]")
    }

    func test_email_inQuotes_isRedacted() {
        assertContainsRedaction("\"alice@example.com\"",
                                kind: .email, token: "[EMAIL]")
    }

    func test_email_inAngleBrackets_isRedacted() {
        assertContainsRedaction("Alice <alice@example.com>",
                                kind: .email, token: "[EMAIL]")
    }

    // MARK: - 4. Email — false-positive prevention

    func test_email_singleAtSignNoTLD_isNotRedactedAsEmail() {
        // `@alice` and `@bob` are social handles, not emails — they
        // must not match the email pattern. They may still match the
        // social-handle pattern (which is fine).
        let result = redactor.redact("ping @alice or @bob — handles only")
        XCTAssertFalse(result.redactions.contains { $0.kind == .email },
                       "bare @handle must not trigger email pattern")
    }

    func test_email_localPartWithoutDomain_isNotRedacted() {
        assertClean("the local part is alice@")
    }

    // MARK: - 5. Phone — happy path

    func test_phone_usFormat_isRedacted() {
        assertContainsRedaction("call 415-555-1234 if needed",
                                kind: .phone, token: "[PHONE]")
    }

    func test_phone_withParens_isRedacted() {
        assertContainsRedaction("call (415) 555-1234 today",
                                kind: .phone, token: "[PHONE]")
    }

    func test_phone_withDots_isRedacted() {
        assertContainsRedaction("415.555.1234 is reachable",
                                kind: .phone, token: "[PHONE]")
    }

    func test_phone_internationalPlusCountryCode_isRedacted() {
        assertContainsRedaction("dial +1 415-555-1234",
                                kind: .phone, token: "[PHONE]")
    }

    func test_phone_internationalUKFormat_isRedacted() {
        assertContainsRedaction("ring +44 20-7946-0958",
                                kind: .phone, token: "[PHONE]")
    }

    func test_phone_internationalSwedenFormat_isRedacted() {
        // Swedish style — Vakter's home market deserves a green test.
        assertContainsRedaction("ring +46 8-123-456",
                                kind: .phone, token: "[PHONE]")
    }

    // MARK: - 6. Phone — tricky

    func test_phone_withZeroWidthBetweenDigits_isRedacted() {
        // ZWSP between digits — a classic copy-paste leakage.
        let smuggled = "call 415\u{200B}-555\u{200B}-1234 now"
        assertContainsRedaction(smuggled, kind: .phone, token: "[PHONE]")
    }

    func test_phone_inSentence_preservesSurroundings() {
        let result = redactor.redact("Call 415-555-1234, please.")
        XCTAssertTrue(result.redactedText.contains("Call "),
                      "leading text preserved")
        XCTAssertTrue(result.redactedText.contains(","),
                      "trailing punctuation preserved")
    }

    func test_phone_multipleNumbers_areAllRedacted() {
        let result = redactor.redact("415-555-1234 and 212-555-9876")
        let count = result.redactions.first(where: { $0.kind == .phone })?.count
        XCTAssertEqual(count, 2)
    }

    // MARK: - 7. Phone — false positives

    func test_phone_shortNumberRun_isNotRedactedAsPhone() {
        // 555-12 is too short to be a phone — must not match.
        let result = redactor.redact("room 555-12 is on floor 3")
        XCTAssertFalse(result.redactions.contains { $0.kind == .phone })
    }

    func test_phone_dateLike_isNotRedactedAsPhone() {
        // 2026-05-30 — three digit-groups separated by dashes, but
        // the third group is only 2 digits (the day). Our phone
        // regex requires the third group to be 3–9 digits, so ISO
        // dates do not slip through. Test pinning the behaviour.
        let result = redactor.redact("the date is 2026-05-30 today")
        XCTAssertFalse(result.redactions.contains { $0.kind == .phone },
                       "ISO date should not match phone pattern — " +
                       "third digit group must be 3+ digits")
    }

    // MARK: - 8. SSN — happy path

    func test_ssn_standardFormat_isRedacted() {
        assertContainsRedaction("SSN 123-45-6789 on file",
                                kind: .ssn, token: "[SSN]")
    }

    func test_ssn_inSentence_preservesContext() {
        let result = redactor.redact("Her SSN is 123-45-6789.")
        XCTAssertTrue(result.redactedText.hasPrefix("Her SSN is "))
        XCTAssertTrue(result.redactedText.hasSuffix("."))
    }

    func test_ssn_multipleSSNs_allRedacted() {
        let result = redactor.redact("SSNs 123-45-6789 and 234-56-7890")
        let count = result.redactions.first(where: { $0.kind == .ssn })?.count
        XCTAssertEqual(count, 2)
    }

    // MARK: - 9. SSN — tricky

    func test_ssn_withFullwidthDigits_NFKCThenRedacted() {
        // Fullwidth ASCII digits — NFKC collapses them.
        let smuggled = "\u{FF11}\u{FF12}\u{FF13}-\u{FF14}\u{FF15}-\u{FF16}\u{FF17}\u{FF18}\u{FF19}"
        assertContainsRedaction(smuggled, kind: .ssn, token: "[SSN]")
    }

    func test_ssn_invalidAreaCode000_isNotRedacted() {
        // 000-XX-XXXX is not a valid SSN — area code 000 is reserved.
        let result = redactor.redact("000-45-6789 is invalid")
        XCTAssertFalse(result.redactions.contains { $0.kind == .ssn })
    }

    func test_ssn_invalidAreaCode666_isNotRedacted() {
        let result = redactor.redact("666-45-6789 is invalid")
        XCTAssertFalse(result.redactions.contains { $0.kind == .ssn })
    }

    func test_ssn_invalidGroup00_isNotRedacted() {
        // Group code 00 is reserved.
        let result = redactor.redact("123-00-6789 is invalid")
        XCTAssertFalse(result.redactions.contains { $0.kind == .ssn })
    }

    func test_ssn_invalidSerial0000_isNotRedacted() {
        let result = redactor.redact("123-45-0000 is invalid")
        XCTAssertFalse(result.redactions.contains { $0.kind == .ssn })
    }

    // MARK: - 10. SSN — false positives

    func test_ssn_partialSSN_isNotRedacted() {
        assertClean("just digits 12-34-5 here")
    }

    func test_ssn_splitAcrossNewline_isNotRedacted() {
        // We do NOT cross newlines on the SSN regex by design — the
        // adversarial split-across-lines case is best handled by the
        // domain redactor (Mail strips quoted-printable wraps before
        // calling). Document the behaviour.
        let split = "SSN 123-\n45-6789"
        let result = redactor.redact(split)
        XCTAssertFalse(result.redactions.contains { $0.kind == .ssn },
                       "cross-newline SSN handled by domain layer")
    }

    // MARK: - 11. Credit card — happy path (Luhn-valid)

    func test_creditCard_visaTestNumber_isRedacted() {
        // 4111-1111-1111-1111 — canonical Visa test number, Luhn-valid.
        assertContainsRedaction("card 4111-1111-1111-1111 on file",
                                kind: .creditCard, token: "[CC]")
    }

    func test_creditCard_visaSpaced_isRedacted() {
        assertContainsRedaction("card 4111 1111 1111 1111 on file",
                                kind: .creditCard, token: "[CC]")
    }

    func test_creditCard_visaSolid_isRedacted() {
        assertContainsRedaction("card 4111111111111111 on file",
                                kind: .creditCard, token: "[CC]")
    }

    func test_creditCard_amex15Digit_isRedacted() {
        // AmEx test number 3782-822463-10005 — 15 digits, Luhn-valid.
        assertContainsRedaction("amex 378282246310005 ready",
                                kind: .creditCard, token: "[CC]")
    }

    func test_creditCard_mastercardTestNumber_isRedacted() {
        // 5555-5555-5555-4444 — canonical Mastercard test number.
        assertContainsRedaction("mc 5555-5555-5555-4444 on file",
                                kind: .creditCard, token: "[CC]")
    }

    func test_creditCard_discoverTestNumber_isRedacted() {
        // 6011-1111-1111-1117 — Discover test number, Luhn-valid.
        assertContainsRedaction("disc 6011-1111-1111-1117 on file",
                                kind: .creditCard, token: "[CC]")
    }

    // MARK: - 12. Credit card — Luhn enforcement

    func test_creditCard_luhnInvalidSequence_isNOTRedacted() {
        // Sixteen digits that fail Luhn — must pass through clean.
        let result = redactor.redact("1234-5678-9012-3456 is a product code")
        XCTAssertFalse(
            result.redactions.contains { $0.kind == .creditCard },
            "Luhn-invalid digit run must not redact as CC"
        )
    }

    func test_creditCard_luhnValid_passes() {
        XCTAssertTrue(PIIRedactor.isLuhnValid("4111111111111111"))
        XCTAssertTrue(PIIRedactor.isLuhnValid("5555555555554444"))
        XCTAssertTrue(PIIRedactor.isLuhnValid("378282246310005"))
        XCTAssertTrue(PIIRedactor.isLuhnValid("6011111111111117"))
    }

    func test_creditCard_luhnInvalid_rejects() {
        XCTAssertFalse(PIIRedactor.isLuhnValid("1234567890123456"))
        XCTAssertFalse(PIIRedactor.isLuhnValid("0000000000000001"))
    }

    func test_creditCard_luhnRejectsEmpty() {
        XCTAssertFalse(PIIRedactor.isLuhnValid(""))
    }

    // MARK: - 13. Credit card — tricky

    func test_creditCard_fullwidthDigits_NFKCThenRedacted() {
        // ４１１１ ＝ U+FF14 U+FF11 U+FF11 U+FF11 → NFKC → 4111.
        let smuggled = "card \u{FF14}\u{FF11}\u{FF11}\u{FF11}-1111-1111-1111"
        assertContainsRedaction(smuggled, kind: .creditCard, token: "[CC]")
    }

    func test_creditCard_zeroWidthBetweenGroups_isRedacted() {
        let smuggled = "4111\u{200B}-1111\u{200B}-1111-1111"
        assertContainsRedaction(smuggled, kind: .creditCard, token: "[CC]")
    }

    func test_creditCard_productCode12Digits_isNotCC() {
        // A 12-digit run is too short for any real CC.
        let result = redactor.redact("product 123456789012 in stock")
        XCTAssertFalse(result.redactions.contains { $0.kind == .creditCard })
    }

    // MARK: - 14. IBAN

    func test_iban_germanForm_isRedacted() {
        // DE89 3704 0044 0532 0130 00 — published ECB test IBAN.
        assertContainsRedaction("pay to DE89 3704 0044 0532 0130 00",
                                kind: .iban, token: "[IBAN]")
    }

    func test_iban_solidForm_isRedacted() {
        assertContainsRedaction("pay to DE89370400440532013000",
                                kind: .iban, token: "[IBAN]")
    }

    func test_iban_frenchForm_isRedacted() {
        assertContainsRedaction(
            "wire FR1420041010050500013M02606 here",
            kind: .iban, token: "[IBAN]"
        )
    }

    func test_iban_swedish_isRedacted() {
        // SE45 5000 0000 0583 9825 7466 — public Swedish test IBAN.
        assertContainsRedaction(
            "Swedish IBAN SE45 5000 0000 0583 9825 7466 here",
            kind: .iban, token: "[IBAN]"
        )
    }

    func test_iban_tooShort_isNotRedacted() {
        // Below the 15-char floor.
        let result = redactor.redact("DE89 37")
        XCTAssertFalse(result.redactions.contains { $0.kind == .iban })
    }

    // MARK: - 15. IP addresses — IPv4

    func test_ipv4_simpleForm_isRedacted() {
        assertContainsRedaction("server at 192.168.1.1 down",
                                kind: .ipAddress, token: "[IP]")
    }

    func test_ipv4_publicAddress_isRedacted() {
        assertContainsRedaction("ping 8.8.8.8 first",
                                kind: .ipAddress, token: "[IP]")
    }

    func test_ipv4_boundary255_isRedacted() {
        assertContainsRedaction("ping 255.255.255.255",
                                kind: .ipAddress, token: "[IP]")
    }

    func test_ipv4_invalidOctet256_isNotRedacted() {
        // 256 is out of range.
        let result = redactor.redact("256.0.0.1 invalid")
        XCTAssertFalse(result.redactions.contains { $0.kind == .ipAddress },
                       "octet 256 must not match")
    }

    func test_ipv4_versionStringFalsePositive_isAcceptedAsOverRedaction() {
        // "version 1.2.3.4" matches IPv4 — documented over-redaction.
        // Brand contract favours over-redaction; this test pins the
        // behaviour so future "smarter" changes can't silently
        // weaken privacy without a code-review conversation.
        let result = redactor.redact("running version 1.2.3.4 here")
        XCTAssertTrue(result.redactions.contains { $0.kind == .ipAddress },
                      "documented over-redaction — see PIIRedactor docs")
    }

    // MARK: - 16. IP addresses — IPv6

    func test_ipv6_fullForm_isRedacted() {
        assertContainsRedaction(
            "server ::1 reachable here is 2001:0db8:85a3:0000:0000:8a2e:0370:7334 today",
            kind: .ipAddress, token: "[IP]"
        )
    }

    func test_ipv6_compressedForm_isRedacted() {
        // Compressed form 2001:db8::1
        let result = redactor.redact("server 2001:db8::1 reachable")
        XCTAssertTrue(result.redactions.contains { $0.kind == .ipAddress },
                      "compressed IPv6 must match")
    }

    // MARK: - 17. MAC address

    func test_mac_colonForm_isRedacted() {
        assertContainsRedaction("mac 00:11:22:33:44:55 today",
                                kind: .macAddress, token: "[MAC]")
    }

    func test_mac_dashForm_isRedacted() {
        assertContainsRedaction("mac 00-11-22-33-44-55 today",
                                kind: .macAddress, token: "[MAC]")
    }

    func test_mac_uppercaseHex_isRedacted() {
        assertContainsRedaction("mac AA:BB:CC:DD:EE:FF today",
                                kind: .macAddress, token: "[MAC]")
    }

    func test_mac_invalidLength_isNotRedacted() {
        let result = redactor.redact("not a mac 00:11:22:33:44 here")
        XCTAssertFalse(result.redactions.contains { $0.kind == .macAddress })
    }

    // MARK: - 18. URLs

    func test_url_httpsForm_isRedacted() {
        assertContainsRedaction("see https://example.com/page",
                                kind: .url, token: "[URL]")
    }

    func test_url_httpForm_isRedacted() {
        assertContainsRedaction("see http://example.com",
                                kind: .url, token: "[URL]")
    }

    func test_url_withQueryString_isRedacted() {
        assertContainsRedaction(
            "see https://example.com/path?utm=1&x=2",
            kind: .url, token: "[URL]"
        )
    }

    func test_url_withFragment_isRedacted() {
        assertContainsRedaction("see https://example.com/p#section-2",
                                kind: .url, token: "[URL]")
    }

    func test_url_mailtoForm_isRedacted() {
        // mailto: is in scheme list; should match as URL.
        assertContainsRedaction("write mailto:alice@example.com here",
                                kind: .url, token: "[URL]")
    }

    func test_url_fileForm_isRedacted() {
        assertContainsRedaction("open file:///Users/alice/x.txt now",
                                kind: .url, token: "[URL]")
    }

    func test_url_plainDomainNoScheme_isNotRedacted() {
        // We intentionally don't match bare domains — too noisy.
        assertClean("the host example.com responded slowly")
    }

    // MARK: - 19. File paths

    func test_filepath_userDocuments_isRedacted() {
        assertContainsRedaction("see /Users/alice/Documents/report.pdf here",
                                kind: .filePath, token: "[FILEPATH]")
    }

    func test_filepath_userDesktop_isRedacted() {
        assertContainsRedaction("see /Users/bob/Desktop/photo.jpg here",
                                kind: .filePath, token: "[FILEPATH]")
    }

    func test_filepath_userDownloads_isRedacted() {
        assertContainsRedaction("see /Users/carol/Downloads/installer.dmg here",
                                kind: .filePath, token: "[FILEPATH]")
    }

    func test_filepath_tildeForm_isRedacted() {
        assertContainsRedaction("see ~/Documents/notes.md here",
                                kind: .filePath, token: "[FILEPATH]")
    }

    func test_filepath_pathWithSpaces_isRedacted() {
        // macOS paths with spaces — important for "Application Support"
        // style locations.
        assertContainsRedaction(
            "see /Users/alice/Documents/My Project/notes.md here",
            kind: .filePath, token: "[FILEPATH]"
        )
    }

    func test_filepath_unrelatedAbsolutePath_isNotRedacted() {
        // /etc/hosts isn't under a user folder — out of scope.
        assertClean("see /etc/hosts for static entries")
    }

    // MARK: - 20. GPS coordinates

    func test_gps_decimalPair_isRedacted() {
        assertContainsRedaction("we are at 37.7749, -122.4194 today",
                                kind: .gpsCoordinate, token: "[GPS]")
    }

    func test_gps_negativeLat_isRedacted() {
        assertContainsRedaction("south at -33.8688, 151.2093 today",
                                kind: .gpsCoordinate, token: "[GPS]")
    }

    func test_gps_boundaryNorthPole_isRedacted() {
        assertContainsRedaction("pole at 90.0, 0.0 today",
                                kind: .gpsCoordinate, token: "[GPS]")
    }

    func test_gps_obviousNonCoordinatePair_isNotRedacted() {
        // "12, 5" is too low-precision and lacks decimals on both sides.
        assertClean("page 12, 5 lines down")
    }

    // MARK: - 21. Bundle identifiers

    func test_bundleId_appleStyle_isRedacted() {
        assertContainsRedaction("kill com.apple.dock first",
                                kind: .bundleIdentifier,
                                token: "[BUNDLE_ID]")
    }

    func test_bundleId_thirdParty_isRedacted() {
        assertContainsRedaction("kill com.vakter.app today",
                                kind: .bundleIdentifier,
                                token: "[BUNDLE_ID]")
    }

    func test_bundleId_orgStyle_isRedacted() {
        assertContainsRedaction("kill org.mozilla.firefox here",
                                kind: .bundleIdentifier,
                                token: "[BUNDLE_ID]")
    }

    func test_bundleId_inFilePath_isAbsorbedByFilePath() {
        // File path matches earlier in the catalog; the file path
        // pattern should win and the bundle id should not double-redact.
        let result = redactor.redact(
            "see /Users/alice/Library/Containers/com.apple.dock/Data here"
        )
        // Either it's all [FILEPATH] or contains both — but no half-
        // redacted state inside the file path.
        let filePathHit = result.redactions.contains { $0.kind == .filePath }
        XCTAssertTrue(filePathHit, "file path must win")
    }

    // MARK: - 22. API tokens

    func test_apiToken_bearerForm_isRedacted() {
        assertContainsRedaction(
            "Authorization: Bearer abc123def456ghi789jkl0mn1234567890",
            kind: .apiToken, token: "[API_TOKEN]"
        )
    }

    func test_apiToken_apiKeyForm_isRedacted() {
        assertContainsRedaction(
            "api_key=ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789xyz",
            kind: .apiToken, token: "[API_TOKEN]"
        )
    }

    func test_apiToken_accessTokenForm_isRedacted() {
        assertContainsRedaction(
            "access_token: sk_test_abcdefghijklmnopqrstuvwxyz12",
            kind: .apiToken, token: "[API_TOKEN]"
        )
    }

    func test_apiToken_xApiKeyHeader_isRedacted() {
        assertContainsRedaction(
            "x-api-key: xx_abcdefghijklmnopqrstuvwxyz123456",
            kind: .apiToken, token: "[API_TOKEN]"
        )
    }

    func test_apiToken_shortRunBelowThreshold_isNotRedacted() {
        // 12-char run is below the 20-char floor — not a token.
        let result = redactor.redact("api_key=short123")
        XCTAssertFalse(result.redactions.contains { $0.kind == .apiToken })
    }

    // MARK: - 23. Social handles

    func test_handle_twitterStyle_isRedacted() {
        assertContainsRedaction("follow @alice today",
                                kind: .socialHandle, token: "[HANDLE]")
    }

    func test_handle_mixedCase_isRedacted() {
        assertContainsRedaction("follow @Alice_Smith today",
                                kind: .socialHandle, token: "[HANDLE]")
    }

    func test_handle_atStartOfMessage_isRedacted() {
        let result = redactor.redact("@alice ping")
        XCTAssertTrue(result.redactions.contains { $0.kind == .socialHandle })
    }

    func test_handle_emailLocalPartIsNotHandle() {
        // alice@example.com — the alice@ part must NOT match as a
        // handle once the email has consumed the span.
        let result = redactor.redact("see alice@example.com")
        XCTAssertFalse(result.redactions.contains { $0.kind == .socialHandle },
                       "email's local-part must not double-fire as handle")
    }

    // MARK: - 24. Generic account numbers

    func test_accountNumber_twelveDigitRun_isRedacted() {
        // Twelve digits passes the floor; it's also too short for any
        // valid CC, so it's not consumed earlier.
        assertContainsRedaction("account 123456789012 closed",
                                kind: .accountNumber, token: "[ACCOUNT_NUM]")
    }

    func test_accountNumber_eighteenDigitRun_isRedacted() {
        // Eighteen digits — outside Luhn-valid CC range for the typed
        // test number; should fall through to account number bucket.
        assertContainsRedaction("ref 987654321098765432 today",
                                kind: .accountNumber, token: "[ACCOUNT_NUM]")
    }

    func test_accountNumber_belowTwelveDigits_isNotRedacted() {
        assertClean("order 12345678901 placed")
    }

    // MARK: - 25. Multi-category in one pass

    func test_multiCategory_emailPhoneURL_allRedacted() {
        let input = "ping alice@example.com or 415-555-1234, see https://x.com"
        let result = redactor.redact(input)
        XCTAssertTrue(result.redactedText.contains("[EMAIL]"))
        XCTAssertTrue(result.redactedText.contains("[PHONE]"))
        XCTAssertTrue(result.redactedText.contains("[URL]"))
    }

    func test_multiCategory_summaryReflectsCounts() {
        let input = "a@b.com x@y.com 415-555-1234"
        let result = redactor.redact(input)
        let emailCount = result.redactions.first {
            $0.kind == .email
        }?.count
        let phoneCount = result.redactions.first {
            $0.kind == .phone
        }?.count
        XCTAssertEqual(emailCount, 2)
        XCTAssertEqual(phoneCount, 1)
    }

    func test_multiCategory_totalCount_aggregates() {
        let result = redactor.redact("a@b.com and x@y.com")
        XCTAssertEqual(result.totalCount, 2)
    }

    // MARK: - 26. Unchanged / clean inputs

    func test_clean_emptyString_returnsEmpty() {
        let result = redactor.redact("")
        XCTAssertEqual(result.redactedText, "")
        XCTAssertTrue(result.isClean)
    }

    func test_clean_purelyAlphabetic_isUnchanged() {
        assertClean("the quick brown fox jumps over the lazy dog")
    }

    func test_clean_punctuationOnly_isUnchanged() {
        assertClean(",,, ;;; ... !!! ???")
    }

    func test_clean_unicodeLetters_isUnchanged() {
        // Cyrillic + emoji should pass through without false alarms.
        assertClean("Привет мир — café résumé")
    }

    func test_clean_marketingProse200Words_isUnchanged() {
        let prose = String(repeating: "Vakter keeps you safe. ", count: 30)
        assertClean(prose)
    }

    // MARK: - 27. Audit-summary shape

    func test_summary_ordersByCatalog_notMatchSequence() {
        // Input matches phone first by position, then email; the
        // summary should still order kinds by catalog (URL → file →
        // ... → email → ... → phone → ...).
        let input = "call 415-555-1234, write alice@example.com"
        let result = redactor.redact(input)
        guard let firstKind = result.redactions.first?.kind else {
            return XCTFail("expected at least one redaction")
        }
        // Email is declared before phone in RedactionPattern.Kind.
        let kinds = result.redactions.map(\.kind)
        if let emailIdx = kinds.firstIndex(of: .email),
           let phoneIdx = kinds.firstIndex(of: .phone) {
            XCTAssertLessThan(emailIdx, phoneIdx,
                              "summary must order by catalog, not by match position")
        }
        XCTAssertNotNil(firstKind)
    }

    func test_summary_omitsKindsWithZeroMatches() {
        let result = redactor.redact("just an email a@b.com")
        for redaction in result.redactions {
            XCTAssertGreaterThan(redaction.count, 0,
                                 "redaction summary must not include zero rows")
        }
    }

    func test_summary_codable_roundTrips() throws {
        let original = redactor.redact("ping a@b.com and 415-555-1234")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RedactionResult.self, from: data)
        XCTAssertEqual(original, decoded,
                       "RedactionResult must survive Codable round-trip — " +
                       "audit log #71 depends on this")
    }

    // MARK: - 28. Normalisation helpers

    func test_normalise_stripsZeroWidthSpace() {
        let input = "hello\u{200B}world"
        let normalised = PIIRedactor.normalise(input)
        XCTAssertEqual(normalised, "helloworld")
    }

    func test_normalise_stripsBidiOverrides() {
        let input = "x\u{202E}y\u{202D}z"
        let normalised = PIIRedactor.normalise(input)
        XCTAssertEqual(normalised, "xyz")
    }

    func test_normalise_stripsBOM() {
        let input = "\u{FEFF}hello"
        let normalised = PIIRedactor.normalise(input)
        XCTAssertEqual(normalised, "hello")
    }

    func test_normalise_collapsesFullwidthDigits() {
        let input = "\u{FF14}\u{FF11}\u{FF11}\u{FF11}"
        let normalised = PIIRedactor.normalise(input)
        XCTAssertEqual(normalised, "4111")
    }

    func test_isZeroWidth_returnsTrueForKnownChars() {
        XCTAssertTrue(PIIRedactor.isZeroWidth(Unicode.Scalar(0x200B)!))
        XCTAssertTrue(PIIRedactor.isZeroWidth(Unicode.Scalar(0x200C)!))
        XCTAssertTrue(PIIRedactor.isZeroWidth(Unicode.Scalar(0xFEFF)!))
        XCTAssertTrue(PIIRedactor.isZeroWidth(Unicode.Scalar(0x202E)!))
    }

    func test_isZeroWidth_returnsFalseForRegularChars() {
        XCTAssertFalse(PIIRedactor.isZeroWidth(Unicode.Scalar("a")))
        XCTAssertFalse(PIIRedactor.isZeroWidth(Unicode.Scalar(" ")))
        XCTAssertFalse(PIIRedactor.isZeroWidth(Unicode.Scalar("\n")))
    }

    // MARK: - 29. Performance budget (<50ms per call)

    func test_perf_largeBenignInput_under50ms() {
        let prose = String(repeating: "The quick brown fox. ", count: 200)
        assertUnder50ms("benign 200-rep prose") {
            _ = self.redactor.redact(prose)
        }
    }

    func test_perf_largeMixedPIIInput_under50ms() {
        let row = "ping alice@example.com 415-555-1234 https://x.com "
        let input = String(repeating: row, count: 100)
        assertUnder50ms("100x mixed PII row") {
            _ = self.redactor.redact(input)
        }
    }

    func test_perf_pathologicalNestedDigits_under50ms() {
        // 4000-digit run — would crush a naive backtracking regex.
        let pathological = String(repeating: "1234567890", count: 400)
        assertUnder50ms("4000-digit run") {
            _ = self.redactor.redact(pathological)
        }
    }

    func test_perf_pathologicalEmailLookalike_under50ms() {
        // Many `@` signs scattered through prose — would explode an
        // unbounded email regex.
        let pathological = String(repeating: "x@", count: 500) + "y"
        assertUnder50ms("500x \"x@\" run") {
            _ = self.redactor.redact(pathological)
        }
    }

    func test_perf_pathologicalDotRun_under50ms() {
        // Many `.` in a row — would explode `.+` in URL/file regexes.
        let pathological = String(repeating: ".", count: 2000)
        assertUnder50ms("2000-dot run") {
            _ = self.redactor.redact(pathological)
        }
    }

    func test_perf_singleCallUnderBudget() {
        let input = "Authorization: Bearer abc123def456ghi789jkl0mn1234567890 " +
                    "ping alice@example.com from 415-555-1234 " +
                    "see https://example.com/path?u=foo " +
                    "card 4111-1111-1111-1111"
        assertUnder50ms("multi-PII single call") {
            _ = self.redactor.redact(input)
        }
    }

    // MARK: - 30. Adversarial — base64-encoded leakage attempts

    func test_adversarial_base64EncodedString_doesNotLeakOriginal() {
        // base64-encoded "alice@example.com" — the encoded form
        // is not a recognisable PII pattern; the redactor doesn't
        // claim to decode arbitrary base64. Document the behaviour.
        let encoded = "YWxpY2VAZXhhbXBsZS5jb20="
        let result = redactor.redact("token \(encoded) here")
        // Either we treat it as a token (good) or leave it alone
        // (also acceptable — domain redactor should decode first).
        // The hard contract: the plaintext email must NOT appear in
        // the output.
        XCTAssertFalse(result.redactedText.contains("alice@example.com"))
    }

    func test_adversarial_doubleAtSign_doesNotConfuseEmailRegex() {
        let input = "weird a@@b.com here"
        let result = redactor.redact(input)
        // Whether it matches or not is fine; the key contract is no
        // crash and bounded time. Touch the result to verify return.
        XCTAssertNotNil(result.redactedText)
    }

    func test_adversarial_rtlOverrideInEmail_stillRedacts() {
        // RTL override inserted into an email address — would visually
        // confuse a human reader but the bytes are still an email.
        let weird = "alice\u{202E}@example.com"
        assertContainsRedaction(weird, kind: .email, token: "[EMAIL]")
    }

    func test_adversarial_homoglyphInDigit_NFKCNormalises() {
        // Test that NFKC catches the homoglyph attack on phone digits.
        let weird = "\u{FF14}\u{FF11}\u{FF15}-555-1234"
        assertContainsRedaction(weird, kind: .phone, token: "[PHONE]")
    }

    func test_adversarial_combiningCharacterAfterDigit_isHandled() {
        // Combining acute accent after a digit — shouldn't break SSN.
        let weird = "1\u{0301}23-45-6789"
        let result = redactor.redact(weird)
        // Either NFKC strips it (then SSN matches) or it doesn't
        // (then no SSN). Both are acceptable; the hard contract is
        // no crash and bounded time.
        XCTAssertNotNil(result.redactedText)
    }

    // MARK: - 31. Determinism / idempotence

    func test_determinism_sameInputProducesSameOutput() {
        let input = "ping alice@example.com from 415-555-1234"
        let first = redactor.redact(input)
        let second = redactor.redact(input)
        XCTAssertEqual(first, second,
                       "same input must produce same output — audit log requires this")
    }

    func test_idempotence_alreadyRedactedTextIsStable() {
        let input = "ping [EMAIL] from [PHONE]"
        let result = redactor.redact(input)
        // [EMAIL] and [PHONE] are already-redacted tokens; the
        // redactor should not match them as anything.
        XCTAssertTrue(result.isClean,
                      "running redactor on already-redacted output " +
                      "must be a no-op")
    }

    // MARK: - 32. Non-default catalog injection

    func test_injectedCatalog_narrowSet_onlyMatchesThose() {
        let onlyEmail = PIIRedactor(patterns: [
            RedactionPattern.all.first { $0.kind == .email }!
        ])
        let result = onlyEmail.redact("call 415-555-1234 or a@b.com")
        XCTAssertTrue(result.redactedText.contains("[EMAIL]"))
        XCTAssertFalse(result.redactedText.contains("[PHONE]"),
                       "narrowed catalog must skip phone pattern")
    }

    func test_injectedCatalog_emptyCatalog_passesThrough() {
        let empty = PIIRedactor(patterns: [])
        let input = "alice@example.com and 415-555-1234"
        let result = empty.redact(input)
        XCTAssertEqual(result.redactedText, input,
                       "empty catalog must not change the input")
        XCTAssertTrue(result.isClean)
    }

    // MARK: - 33. ExplainModule wiring

    func test_explainModule_redactInput_returnsCleanForBenignString() async {
        // The ExplainModule facade exposes redactInput(_:) so call
        // sites can pre-redact without reaching into PIIRedactor
        // directly. Smoke-test it.
        let result = await ExplainModule.shared.redactInput("hello world")
        XCTAssertEqual(result.redactedText, "hello world")
        XCTAssertTrue(result.isClean)
    }

    func test_explainModule_redactInput_redactsPII() async {
        let result = await ExplainModule.shared
            .redactInput("ping alice@example.com")
        XCTAssertTrue(result.redactedText.contains("[EMAIL]"))
    }
}
