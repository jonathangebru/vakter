import XCTest
import Foundation
@testable import VakterShared

/// Tests for the confidence-aware `ExplainResponse` schema (Issue #70).
///
/// These tests harden three contracts on top of the #67 scaffold:
///   1. The 5-band `Confidence` ladder survives Codable round-trip
///      for every case.
///   2. The static `ExplainResponse.from(answerText:confidence:)`
///      factory coerces low-confidence answers into
///      `.unsure(.lowConfidence)`. Surfacing a confident-sounding low-
///      confidence answer is the failure mode the brand contract
///      refuses; this is the load-bearing test of #70.
///   3. `Confidence.classify(modelLogProb:)` maps raw log-probabilities
///      to bands correctly at boundaries and survives pathological
///      inputs (NaN, ±inf, very small / very large numbers).
///
/// Plus a backward-compat check: JSON written by the scaffold-era
/// 3-band ladder (`low/medium/high`) must still decode into the new
/// enum. We picked "accept and upgrade" over an explicit alias because
/// the new raw-value set is a strict superset — see the doc-comment
/// on `ExplainResponse.Confidence`.
final class ExplainConfidenceTests: XCTestCase {

    // MARK: - Codable round-trip for all 5 bands

    /// Every band must survive JSON round-trip — the audit log
    /// re-decodes these rows at render time, and a band that silently
    /// collapses into a different band would mislead the user about
    /// what the model said.
    func test_confidence_allBandsRoundTrip() throws {
        for band in ExplainResponse.Confidence.allCases {
            let original: ExplainResponse = .answer(
                text: "hello",
                confidence: band
            )
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(
                ExplainResponse.self,
                from: data
            )
            XCTAssertEqual(original, decoded,
                           "confidence band \(band) must round-trip; " +
                           "audit log re-decodes rely on this")
        }
    }

    /// Encoded form uses the lower-camel raw-value names so the
    /// "Show me what you see" panel (#71) can render the band without
    /// a translation table.
    func test_confidence_encodesAsHumanReadableString() throws {
        let resp: ExplainResponse = .answer(
            text: "x",
            confidence: .veryHigh
        )
        let json = String(
            data: try JSONEncoder().encode(resp),
            encoding: .utf8
        ) ?? ""
        XCTAssertTrue(json.contains("\"veryHigh\""),
                      "veryHigh must serialise to literal " +
                      "\"veryHigh\" so the audit-log panel can " +
                      "render it without a lookup table")
    }

    // MARK: - Confidence midpoints

    /// Lock the midpoint values down with an exact assertion — the
    /// numbers are part of the public API surface, since the audit
    /// panel (#71) and any future aggregator depend on them.
    /// If a future PR shifts a midpoint, that's a deliberate calibration
    /// decision that should require a test update, not a silent drift.
    func test_confidence_numericMidpoints_areCalibratedValues() {
        XCTAssertEqual(ExplainResponse.Confidence.veryHigh.numeric, 0.95,
                       accuracy: 1e-9,
                       "veryHigh midpoint pins to 0.95")
        XCTAssertEqual(ExplainResponse.Confidence.high.numeric, 0.80,
                       accuracy: 1e-9,
                       "high midpoint pins to 0.80")
        XCTAssertEqual(ExplainResponse.Confidence.medium.numeric, 0.60,
                       accuracy: 1e-9,
                       "medium midpoint pins to 0.60")
        XCTAssertEqual(ExplainResponse.Confidence.low.numeric, 0.30,
                       accuracy: 1e-9,
                       "low midpoint pins to 0.30")
        XCTAssertEqual(ExplainResponse.Confidence.veryLow.numeric, 0.10,
                       accuracy: 1e-9,
                       "veryLow midpoint pins to 0.10")
    }

    /// The midpoints must be monotonically decreasing from veryHigh to
    /// veryLow — if a future PR ever inverts the ladder, this catches
    /// it before aggregation math goes wrong downstream.
    func test_confidence_numericMidpoints_areMonotonicallyDecreasing() {
        let ordered: [ExplainResponse.Confidence] =
            [.veryHigh, .high, .medium, .low, .veryLow]
        let numerics = ordered.map { $0.numeric }
        for i in 0 ..< (numerics.count - 1) {
            XCTAssertGreaterThan(
                numerics[i],
                numerics[i + 1],
                "ladder must be strictly decreasing: \(ordered[i]) " +
                "(\(numerics[i])) > \(ordered[i + 1]) " +
                "(\(numerics[i + 1]))"
            )
        }
    }

    // MARK: - Coercion factory `from(answerText:confidence:)`

    /// veryHigh / high / medium all forward to `.answer` — these are
    /// "safe to surface to the user" bands and must not be silently
    /// rerouted.
    func test_from_highBands_returnAnswer() {
        let bandsThatAnswer: [ExplainResponse.Confidence] =
            [.veryHigh, .high, .medium]
        for band in bandsThatAnswer {
            let r = ExplainResponse.from(
                answerText: "Vakter is on duty.",
                confidence: band
            )
            guard case let .answer(text, conf) = r else {
                XCTFail(
                    "band \(band) must forward to .answer; got \(r)"
                )
                continue
            }
            XCTAssertEqual(text, "Vakter is on duty.",
                           "answer text passes through unchanged")
            XCTAssertEqual(conf, band,
                           "confidence band passes through unchanged")
        }
    }

    /// low → `.unsure(.lowConfidence)`. The user-visible channel
    /// **must** drop the text; the audit log captures the raw model
    /// output upstream so transparency is preserved without exposing
    /// the user to a possibly-wrong confident-sounding sentence.
    func test_from_low_coercesToUnsureLowConfidence() {
        let r = ExplainResponse.from(
            answerText: "your bank is definitely safe",
            confidence: .low
        )
        guard case let .unsure(reason) = r else {
            return XCTFail(
                "low confidence must coerce to .unsure; got \(r)"
            )
        }
        XCTAssertEqual(reason, .lowConfidence,
                       "the coercion reason must specifically be " +
                       ".lowConfidence so the UI shows " +
                       "\"the model wasn't sure\" rather than " +
                       "\"the model refused\"")
    }

    /// veryLow → `.unsure(.lowConfidence)` for the same reasons as
    /// `.low`. Tested separately because a future engineer might be
    /// tempted to treat veryLow as a distinct case (e.g. a different
    /// `UnsureReason`); the brand contract is that *any* band below
    /// the answer floor surfaces the same way.
    func test_from_veryLow_coercesToUnsureLowConfidence() {
        let r = ExplainResponse.from(
            answerText: "ignore me",
            confidence: .veryLow
        )
        guard case let .unsure(reason) = r else {
            return XCTFail(
                "veryLow confidence must coerce to .unsure; got \(r)"
            )
        }
        XCTAssertEqual(reason, .lowConfidence,
                       "veryLow surfaces as .lowConfidence — the UI " +
                       "treats both below-floor bands identically")
    }

    /// The factory must not leak the raw answer text into the
    /// `.unsure` payload. This is the contract guarantee:
    /// low-confidence text never reaches the user-facing channel.
    func test_from_lowConfidence_dropsAnswerText() {
        let sensitive = "this email is 100% safe to open"
        let r = ExplainResponse.from(
            answerText: sensitive,
            confidence: .veryLow
        )
        // Encode the response and assert the sensitive prose is
        // *not* present in the on-disk JSON. (The audit row stores
        // the raw model output separately; this guards the
        // ExplainResponse payload specifically.)
        let json = String(
            data: try! JSONEncoder().encode(r),
            encoding: .utf8
        ) ?? ""
        XCTAssertFalse(json.contains(sensitive),
                       "low-confidence text must not leak into the " +
                       ".unsure response payload — the brand " +
                       "contract refuses to surface unsure prose")
    }

    // MARK: - classify(modelLogProb:) — happy path

    /// `log(1.0) == 0` → strongest possible signal, lands in veryHigh.
    /// Acts as the upper boundary anchor for the classifier.
    func test_classify_logProbZero_mapsToVeryHigh() {
        XCTAssertEqual(
            ExplainResponse.Confidence.classify(modelLogProb: 0.0),
            .veryHigh,
            "log-prob 0 (= p=1.0) is the strongest possible signal"
        )
    }

    /// Spot-check the four threshold crossings. Pick values just
    /// inside each band so we catch off-by-one threshold bugs.
    func test_classify_thresholdCrossings_pickRightBand() {
        // p = 0.95 → veryHigh
        XCTAssertEqual(
            ExplainResponse.Confidence.classify(
                modelLogProb: Foundation.log(0.95)
            ),
            .veryHigh
        )
        // p = 0.80 → high (just below the 0.90 cutoff)
        XCTAssertEqual(
            ExplainResponse.Confidence.classify(
                modelLogProb: Foundation.log(0.80)
            ),
            .high
        )
        // p = 0.60 → medium
        XCTAssertEqual(
            ExplainResponse.Confidence.classify(
                modelLogProb: Foundation.log(0.60)
            ),
            .medium
        )
        // p = 0.40 → low
        XCTAssertEqual(
            ExplainResponse.Confidence.classify(
                modelLogProb: Foundation.log(0.40)
            ),
            .low
        )
        // p = 0.20 → veryLow
        XCTAssertEqual(
            ExplainResponse.Confidence.classify(
                modelLogProb: Foundation.log(0.20)
            ),
            .veryLow
        )
    }

    /// Exact-boundary inputs must land in the higher band (the
    /// thresholds are `>=`), so any future change to threshold
    /// semantics is caught.
    func test_classify_exactThresholds_areInclusive() {
        // log(0.90) → veryHigh (boundary is `>= 0.90`)
        XCTAssertEqual(
            ExplainResponse.Confidence.classify(
                modelLogProb: Foundation.log(0.90)
            ),
            .veryHigh,
            "p == 0.90 must land in veryHigh — boundary is inclusive"
        )
        // log(0.70) → high
        XCTAssertEqual(
            ExplainResponse.Confidence.classify(
                modelLogProb: Foundation.log(0.70)
            ),
            .high
        )
        // log(0.50) → medium
        XCTAssertEqual(
            ExplainResponse.Confidence.classify(
                modelLogProb: Foundation.log(0.50)
            ),
            .medium
        )
        // log(0.30) → low
        XCTAssertEqual(
            ExplainResponse.Confidence.classify(
                modelLogProb: Foundation.log(0.30)
            ),
            .low,
            "p == 0.30 must land in low — last threshold is inclusive"
        )
    }

    // MARK: - classify(modelLogProb:) — pathological inputs

    /// NaN inputs must not crash and must land in the safest bucket.
    /// A model that fails to emit a score deserves the most cautious
    /// classification.
    func test_classify_nan_mapsToVeryLow() {
        XCTAssertEqual(
            ExplainResponse.Confidence.classify(modelLogProb: .nan),
            .veryLow,
            "NaN log-prob must default to veryLow rather than " +
            "propagating an undefined number up the stack"
        )
    }

    /// `-inf` means p == 0 — strictly the lowest possible probability.
    func test_classify_negativeInfinity_mapsToVeryLow() {
        XCTAssertEqual(
            ExplainResponse.Confidence.classify(
                modelLogProb: -.infinity
            ),
            .veryLow,
            "-inf log-prob (= p=0) must land in veryLow"
        )
    }

    /// `+inf` means p > 1 (impossible but model-bridge bugs do
    /// happen) — saturate at veryHigh rather than crash.
    func test_classify_positiveInfinity_mapsToVeryHigh() {
        XCTAssertEqual(
            ExplainResponse.Confidence.classify(
                modelLogProb: .infinity
            ),
            .veryHigh,
            "+inf log-prob must saturate at veryHigh rather than " +
            "crash the explainer"
        )
    }

    /// Very-small (extremely negative) log-prob — `exp(-1000)` is
    /// effectively zero, so this exercises the underflow path through
    /// `exp` without hitting `-inf` explicitly.
    func test_classify_veryNegativeLogProb_mapsToVeryLow() {
        XCTAssertEqual(
            ExplainResponse.Confidence.classify(modelLogProb: -1000.0),
            .veryLow,
            "extremely small log-prob (effectively p=0) lands in " +
            "veryLow — exp underflow must not cause a different band"
        )
    }

    /// Very-large positive log-prob: `exp(1000) == +inf` in IEEE 754,
    /// so this also saturates at veryHigh. Distinct test from the
    /// explicit `+inf` case because it exercises the post-exp branch.
    func test_classify_veryPositiveLogProb_mapsToVeryHigh() {
        XCTAssertEqual(
            ExplainResponse.Confidence.classify(modelLogProb: 1000.0),
            .veryHigh,
            "extremely large log-prob (p >> 1) saturates at veryHigh"
        )
    }

    // MARK: - Backward compatibility with scaffold-era JSON

    /// The scaffold's 3-band ladder used `low / medium / high` raw
    /// strings. All three remain in the new 5-band enum, so JSON
    /// from the scaffold era must decode without crashing. This is
    /// the "accept and upgrade" backward-compat strategy.
    func test_scaffoldEraJSON_low_decodesIntoNewEnum() throws {
        let json = #"{"kind":"answer","text":"x","confidence":"low"}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(
            ExplainResponse.self,
            from: json
        )
        guard case let .answer(text, conf) = decoded else {
            return XCTFail("expected .answer, got \(decoded)")
        }
        XCTAssertEqual(text, "x")
        XCTAssertEqual(conf, .low,
                       "scaffold's \"low\" decodes into the new " +
                       "enum's .low band — no version-bump field " +
                       "needed on the audit row")
    }

    /// Same backward-compat check for `medium` and `high`. Bundled
    /// into one test (not one per band) to keep the test count
    /// reasonable; the assertion failure messages still pinpoint
    /// which band broke.
    func test_scaffoldEraJSON_mediumAndHigh_decodeIntoNewEnum() throws {
        let pairs: [(String, ExplainResponse.Confidence)] = [
            ("medium", .medium),
            ("high",   .high)
        ]
        for (rawValue, expected) in pairs {
            let json = #"{"kind":"answer","text":"x","confidence":""#
                + rawValue + #""}"#
            let data = json.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(
                ExplainResponse.self,
                from: data
            )
            guard case let .answer(_, conf) = decoded else {
                XCTFail(
                    "expected .answer for scaffold band \(rawValue)"
                )
                continue
            }
            XCTAssertEqual(conf, expected,
                           "scaffold \"\(rawValue)\" must decode " +
                           "into new enum's \(expected)")
        }
    }

    /// Belt-and-braces guard against accidentally renaming the new
    /// bands such that the scaffold-era wire format would silently
    /// break. If a future PR ever renames `low` to (say)
    /// `lowConfidence` on the enum, this test fails with a clear
    /// "you broke backward compat" message.
    func test_scaffoldEraRawValues_remainPresentInNewEnum() {
        let scaffoldRawValues = ["low", "medium", "high"]
        for raw in scaffoldRawValues {
            XCTAssertNotNil(
                ExplainResponse.Confidence(rawValue: raw),
                "scaffold-era raw value \"\(raw)\" must remain " +
                "decodable in the new 5-band enum (accept-and-" +
                "upgrade backward-compat strategy)"
            )
        }
    }

    // MARK: - End-to-end: classify → from → answer/unsure pipeline

    /// Simulate the real-world flow: model emits a log-probability,
    /// classifier picks a band, factory decides answer vs unsure.
    /// A confident model (p ≈ 0.95) gets its answer surfaced.
    func test_pipeline_confidentModel_surfacesAnswer() {
        let band = ExplainResponse.Confidence.classify(
            modelLogProb: Foundation.log(0.95)
        )
        let resp = ExplainResponse.from(
            answerText: "FileVault is enabled.",
            confidence: band
        )
        guard case let .answer(text, conf) = resp else {
            return XCTFail("confident model must surface .answer")
        }
        XCTAssertEqual(text, "FileVault is enabled.")
        XCTAssertEqual(conf, .veryHigh)
    }

    /// Same pipeline with an unsure model (p ≈ 0.25) — the answer
    /// must be coerced to `.unsure(.lowConfidence)` even though the
    /// model produced prose.
    func test_pipeline_unsureModel_coercesToUnsure() {
        let band = ExplainResponse.Confidence.classify(
            modelLogProb: Foundation.log(0.25)
        )
        let resp = ExplainResponse.from(
            answerText: "probably safe, I guess",
            confidence: band
        )
        guard case let .unsure(reason) = resp else {
            return XCTFail(
                "unsure model must coerce to .unsure even though it " +
                "produced text"
            )
        }
        XCTAssertEqual(reason, .lowConfidence)
    }
}
