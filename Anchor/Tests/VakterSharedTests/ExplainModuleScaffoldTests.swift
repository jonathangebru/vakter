import XCTest
@testable import VakterShared

/// Scaffold-level tests for the EXPLAIN module (Issue #67).
///
/// These tests verify the *type-level* contracts the follow-on
/// tickets (#68 / #69 / #70 / #71) will build on. They deliberately
/// do NOT exercise model behaviour, PII redaction, or audit-log
/// persistence — those land with their respective tickets.
///
/// What we cover here:
///   - The public types exist and the public facade methods compile.
///   - `ExplainResponse` round-trips through `Codable` *including
///     the `.unsure` discriminator*. This is the load-bearing
///     property: the audit log persists responses as JSON, and the
///     "Show me what you see" panel (#71) re-decodes them to
///     render. If `.unsure` collapsed into `.answer` on round-trip
///     the audit log would lie to the user about what the model
///     said — exactly the bug the type's design is meant to make
///     impossible.
///   - The scaffold `explain(request:)` returns a well-formed
///     `.unsure` response so downstream code can compile against a
///     real return path before #69 ships the real model call.
///   - `ExplainAuditEntry` round-trips through `Codable` as a whole
///     so the on-disk audit-log format is stable before #69 starts
///     writing rows.
///
/// All cases are pure value-level checks — no Keychain, no
/// filesystem, no network. Fast and deterministic.
final class ExplainModuleScaffoldTests: XCTestCase {

    // MARK: - Public facade exists

    func test_sharedInstance_isReachable() async {
        // Just touching the shared singleton verifies the type
        // compiles and the actor's implicit init exists.
        let module = ExplainModule.shared
        let available = await module.isModelAvailable()
        // Scaffold placeholder always returns false; this both
        // documents the placeholder and ensures #69 has to update
        // the test when it wires the real probe.
        XCTAssertFalse(available,
                       "scaffold isModelAvailable() must be false " +
                       "until #69 wires the FoundationModels probe")
    }

    func test_explain_returnsUnsureAtScaffoldTime() async {
        let request = ExplainRequest(
            domain: "defenses",
            redactedPrompt: "What does FileVault do?"
        )
        let response = await ExplainModule.shared.explain(request: request)
        // The scaffold body returns `.unsure(.outOfScope)` so the
        // type contract is exercisable. Once #69 ships, this test
        // moves into the #69 test file and is replaced here with a
        // type-only existence check.
        guard case let .unsure(reason) = response else {
            return XCTFail("scaffold must return .unsure, got \(response)")
        }
        XCTAssertEqual(reason, .outOfScope,
                       "scaffold placeholder must surface " +
                       "`outOfScope` so call sites can detect " +
                       "'no real model wired yet'")
    }

    func test_recentAuditEntries_isEmptyAtScaffoldTime() async {
        let entries = await ExplainModule.shared.recentAuditEntries()
        XCTAssertEqual(entries.count, 0,
                       "no audit log writer exists until #69; the " +
                       "scaffold must return an empty array rather " +
                       "than crash or block on disk I/O")
    }

    // MARK: - ExplainResponse Codable round-trip

    func test_explainResponse_answerCase_roundTripsThroughCodable() throws {
        let original: ExplainResponse = .answer(
            text: "FileVault encrypts your disk.",
            confidence: .high
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            ExplainResponse.self,
            from: encoded
        )
        XCTAssertEqual(original, decoded,
                       ".answer must survive JSON round-trip; the " +
                       "audit log depends on this for #71")
    }

    func test_explainResponse_unsureCase_roundTripsThroughCodable() throws {
        // The most important round-trip in the module. If the
        // `.unsure` discriminator gets lost on the way through
        // JSON, the "Show me what you see" panel will silently
        // render unsure responses as if the model had answered —
        // exactly the bug the type's design forbids.
        for reason in ExplainResponse.UnsureReason.allCases {
            let original: ExplainResponse = .unsure(reason: reason)
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(
                ExplainResponse.self,
                from: encoded
            )
            XCTAssertEqual(original, decoded,
                           ".unsure(\(reason)) must survive JSON " +
                           "round-trip — first-class unsure-state is " +
                           "the load-bearing design decision")
        }
    }

    func test_explainResponse_jsonShape_isHumanReadable() throws {
        // The on-disk audit log will be visible to the user via the
        // "Show me what you see" panel (#71). Verify the JSON keys
        // are human-readable strings, not Swift's default enum
        // discriminator scheme.
        let response: ExplainResponse = .unsure(reason: .lowConfidence)
        let data = try JSONEncoder().encode(response)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"kind\""),
                      "audit-log JSON must use a `kind` " +
                      "discriminator — visible in the panel")
        XCTAssertTrue(json.contains("\"unsure\""),
                      "the unsure case must serialise to the " +
                      "literal string `unsure`")
        XCTAssertTrue(json.contains("\"lowConfidence\""),
                      "reason enum must serialise to its lowerCamel " +
                      "name; #71 will key UI affordances off these " +
                      "string values")
    }

    // MARK: - ExplainAuditEntry Codable round-trip

    func test_explainAuditEntry_roundTripsThroughCodable() throws {
        // The audit log writes one of these per call. Stable JSON
        // shape is the contract between #69 (writer) and #71
        // (reader). Locking it in at scaffold time means neither
        // ticket has to reverse-engineer the format from the other.
        let request = ExplainRequest(
            domain: "mail",
            redactedPrompt: "Should I trust [REDACTED_EMAIL]?"
        )
        let response: ExplainResponse = .answer(
            text: "I can't reach the sender's reputation feed.",
            confidence: .medium
        )
        let entry = ExplainAuditEntry(
            request: request,
            response: response,
            durationMilliseconds: 142
        )
        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(
            ExplainAuditEntry.self,
            from: encoded
        )
        XCTAssertEqual(entry, decoded,
                       "audit entry must round-trip exactly so the " +
                       "panel renders what was written")
        XCTAssertEqual(decoded.request.domain, "mail")
        XCTAssertEqual(decoded.durationMilliseconds, 142)
    }

    // MARK: - ExplainRequest defaulting

    func test_explainRequest_defaultLocale_isCurrentLocale() {
        let request = ExplainRequest(
            domain: "mac",
            redactedPrompt: "Why is sleep disabled?"
        )
        XCTAssertEqual(request.localeIdentifier, Locale.current.identifier,
                       "default locale must be Locale.current so " +
                       "most call sites don't have to pass one")
    }

    // MARK: - ExplainError shape

    func test_explainError_isEquatable() {
        // Cheap test — but it's the property tests in #68/#69 will
        // depend on (asserting `XCTAssertEqual(error, .modelUnavailable)`
        // etc.). If `Equatable` synthesis ever silently breaks
        // (e.g. someone adds an associated value of a non-Equatable
        // type), this catches it at scaffold time.
        XCTAssertEqual(ExplainError.networkNotAllowed,
                       .networkNotAllowed)
        XCTAssertNotEqual(ExplainError.networkNotAllowed,
                          .modelUnavailable)
        XCTAssertEqual(
            ExplainError.internalFailure(errorIdentifier: "x"),
            .internalFailure(errorIdentifier: "x")
        )
        XCTAssertNotEqual(
            ExplainError.internalFailure(errorIdentifier: "x"),
            .internalFailure(errorIdentifier: "y")
        )
    }
}
