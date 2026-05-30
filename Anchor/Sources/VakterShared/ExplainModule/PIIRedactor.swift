import Foundation

/// One row of the redaction audit summary — how many times a given
/// ``RedactionPattern/Kind`` was substituted in the most recent
/// ``PIIRedactor/redact(_:)`` call.
///
/// Exposed as its own type (rather than a `[Kind: Int]` dictionary)
/// so the audit panel can iterate in declaration order — Swift
/// dictionaries don't promise that — and so future fields (e.g. byte
/// span, capture-group hash) can be added without breaking the
/// `Codable` shape on disk.
public struct Redaction: Sendable, Codable, Equatable {

    /// Which category the count belongs to.
    public let kind: RedactionPattern.Kind

    /// How many distinct matches in the input were replaced with this
    /// category's token. Always ≥ 1 — categories that didn't fire are
    /// omitted from ``RedactionResult/redactions``.
    public let count: Int

    public init(kind: RedactionPattern.Kind, count: Int) {
        self.kind = kind
        self.count = count
    }
}

/// Bundle of (redacted string, per-category counts) returned by
/// ``PIIRedactor/redact(_:)``.
///
/// Both fields are needed:
///   - ``redactedText`` is what the ``ExplainModule`` will forward to
///     the on-device model. It is fully token-substituted; no partial
///     PII remains.
///   - ``redactions`` is what the "Show me what you see" audit panel
///     (#71) renders so the user can see *what kinds* of things were
///     stripped, without ever exposing the originals.
///
/// `Codable` because audit-log rows may persist the summary alongside
/// the request/response pair.
public struct RedactionResult: Sendable, Codable, Equatable {

    /// The input string with every matched PII span replaced by its
    /// category token (`[EMAIL]`, `[CC]`, …). Safe to forward to the
    /// on-device model.
    public let redactedText: String

    /// Per-category match counts, in declaration order of
    /// ``RedactionPattern/Kind``. Categories with zero matches are
    /// omitted — `isEmpty` means "no PII detected."
    public let redactions: [Redaction]

    public init(redactedText: String, redactions: [Redaction]) {
        self.redactedText = redactedText
        self.redactions = redactions
    }

    /// True iff the redactor changed nothing. Convenience for tests
    /// and audit-row rendering.
    public var isClean: Bool { redactions.isEmpty }

    /// Total redactions across all categories.
    public var totalCount: Int { redactions.reduce(0) { $0 + $1.count } }
}

/// The Vakter PII redactor.
///
/// **Why this code exists.** Every prompt that reaches Apple Foundation
/// Models on the user's Mac flows through ``ExplainModule``, and the
/// module's brand contract — "Vakter never uses a cloud LLM" — extends
/// to a stricter privacy contract: "Vakter never sends *anything that
/// looks like the user's personal data* to the model, even on-device."
/// This type is the chokepoint that makes the second contract true.
///
/// ## Defence-in-depth posture
///
/// The redactor is a generic, domain-agnostic pass. The Watch domains
/// (Mail, Messages, Web, Mac) are expected to run their own domain-
/// aware redactor *before* calling ``ExplainModule/explain(request:)``
/// — for example, Mail strips `From:` headers and contact-list names
/// because it knows which fields exist. This redactor is the second
/// belt around the first one. The cost of over-redaction here is low
/// (a token swap in the prompt); the cost of under-redaction is the
/// brand contract.
///
/// ## Hardening choices
///
/// 1. **Unicode normalisation pre-pass.** Inputs are converted to NFKC
///    so lookalike-digit attacks (full-width `４１１１` → `4111`) don't
///    bypass the digit-class regexes. Zero-width characters
///    (`U+200B…U+200F`, `U+FEFF`, etc.) are stripped because they're
///    known to split PII patterns (a Twitter trick: `41￼11`).
/// 2. **Luhn validation for credit cards.** The CC regex is a
///    candidate filter; the Luhn check is the decision. Without this,
///    any product code that happens to be 16 digits gets redacted as
///    a CC, which annoys users without improving privacy. *With* it,
///    only realistic CC sequences are flagged.
/// 3. **Per-category match order.** Patterns walk in
///    ``RedactionPattern/all``'s declaration order. URLs match before
///    emails so a URL-encoded email stays inside the URL token rather
///    than getting half-redacted. File paths match before bundle IDs.
///    This ordering is the type's load-bearing contract and is locked
///    by tests.
/// 4. **Bounded regexes.** Every pattern uses character classes and
///    bounded quantifiers — no `.*`, no `.+?`-on-`.+?` backtracking
///    trees. Attacker-controlled prompts cannot DoS the redactor;
///    each test in the suite finishes well under the 50ms budget.
/// 5. **Deterministic output.** No random salts, no time-based
///    decisions. Same input always produces the same redacted output
///    so the audit log is reproducible across runs.
///
/// ## What this redactor does NOT do
///
/// - **Email-in-contacts allowlisting** (per ticket #68 acceptance
///   criteria: "Email addresses NOT in user's contacts" → redact, "IN
///   user's contacts" → preserve). The Contacts integration is
///   out-of-scope for this ticket per the GitHub-issue scope note;
///   v1.5 ships the conservative default (always-redact-emails). A
///   later ticket plumbs a `ContactsLookup` protocol through.
/// - **Name redaction.** The ticket lists "Names of people not in
///   user's approved-contacts list" as a category, but without
///   contacts (above) we cannot distinguish names from common nouns
///   without an NLP pass. Rather than ship a noisy name regex now,
///   this redactor leaves the category for a later ticket and
///   compensates by being aggressive on adjacent categories
///   (handles, emails, phones) that carry the same identity signal.
/// - **Streaming.** Inputs are processed in one shot. The on-device
///   model prompts are bounded, so a single `redact(_:)` call is
///   adequate; streaming-redaction would only matter for arbitrarily-
///   large logs which never reach this type.
///
/// ## Thread-safety
///
/// `Sendable`. The type holds no mutable state — every call is pure.
/// `NSRegularExpression` instances inside ``RedactionPattern`` are
/// safe to share across threads for read-only matching.
public struct PIIRedactor: Sendable {

    /// The catalog of categories this instance will recognise.
    /// Defaults to ``RedactionPattern/all``; tests may inject a
    /// narrower catalog to assert on a single pattern in isolation.
    public let patterns: [RedactionPattern]

    public init(patterns: [RedactionPattern] = RedactionPattern.all) {
        self.patterns = patterns
    }

    // MARK: - Public API

    /// Run every pattern in ``patterns`` over `input` and return the
    /// redacted string plus a per-category tally.
    ///
    /// Algorithm:
    ///   1. Normalise input to NFKC and strip zero-width characters.
    ///   2. Walk `patterns` in declaration order; for each pattern,
    ///      collect every non-overlapping match.
    ///   3. For credit-card matches, drop any candidate whose digit
    ///      string fails the Luhn check.
    ///   4. Sort all surviving matches by start offset; resolve
    ///      overlaps by keeping the earliest start, then the longest.
    ///   5. Rebuild the output string by walking the input and
    ///      substituting tokens at the kept-match offsets.
    ///
    /// Returns ``RedactionResult/isClean`` when no pattern fired.
    public func redact(_ input: String) -> RedactionResult {

        let normalised = Self.normalise(input)

        // Collect candidate matches across all patterns.
        var candidates: [Candidate] = []
        for pattern in patterns {
            let nsRange = NSRange(normalised.startIndex..<normalised.endIndex,
                                  in: normalised)
            let matches = pattern.regex.matches(
                in: normalised,
                options: [],
                range: nsRange
            )
            for match in matches {
                guard let swiftRange = Range(match.range, in: normalised) else {
                    continue
                }
                let matchedText = String(normalised[swiftRange])

                // Credit card: only keep if Luhn-valid.
                if pattern.kind == .creditCard {
                    let digits = matchedText.filter(\.isNumber)
                    guard digits.count >= 13,
                          digits.count <= 19,
                          Self.isLuhnValid(digits) else {
                        continue
                    }
                }

                // IBAN: spec demands 15–34 chars after stripping
                // separators. The regex is permissive; reject here.
                if pattern.kind == .iban {
                    let condensed = matchedText.filter { $0.isLetter || $0.isNumber }
                    guard condensed.count >= 15, condensed.count <= 34 else {
                        continue
                    }
                }

                candidates.append(
                    Candidate(
                        kind: pattern.kind,
                        token: pattern.token,
                        range: swiftRange,
                        text: matchedText
                    )
                )
            }
        }

        // Resolve overlaps. Earlier-starting wins; on ties, longest
        // span wins; on further ties, declaration-order wins (we
        // appended in catalog order so the existing order suffices).
        let resolved = Self.resolveOverlaps(
            candidates,
            in: normalised
        )

        // Substitute, walking the input once.
        var output = ""
        var cursor = normalised.startIndex
        var counts: [RedactionPattern.Kind: Int] = [:]
        for candidate in resolved {
            output += normalised[cursor..<candidate.range.lowerBound]
            output += candidate.token
            counts[candidate.kind, default: 0] += 1
            cursor = candidate.range.upperBound
        }
        output += normalised[cursor..<normalised.endIndex]

        // Build the per-category summary in catalog order.
        var seenKinds: [RedactionPattern.Kind] = []
        for pattern in patterns where counts[pattern.kind] != nil {
            if !seenKinds.contains(pattern.kind) {
                seenKinds.append(pattern.kind)
            }
        }
        let summary = seenKinds.map { kind in
            Redaction(kind: kind, count: counts[kind] ?? 0)
        }

        return RedactionResult(redactedText: output, redactions: summary)
    }

    // MARK: - Internals (visible for testing)

    /// Normalise an input string before pattern matching.
    ///
    /// Two transformations:
    ///   - **NFKC.** Collapses compatibility forms — `４１１１` becomes
    ///     `4111` — so lookalike-digit attacks can't slip past the
    ///     `[0-9]` character classes. We use NFKC rather than NFC
    ///     because compatibility decomposition is exactly what catches
    ///     the full-width / circled / fraction lookalikes used in
    ///     real-world PII smuggling.
    ///   - **Zero-width stripping.** Removes U+200B through U+200F,
    ///     U+202A–U+202E (RTL/LTR overrides), U+2066–U+2069 (RLI/LRI/
    ///     FSI/PDI), and U+FEFF (BOM). These characters are
    ///     adversarial: they split PII patterns across what looks like
    ///     a single visual glyph.
    static func normalise(_ input: String) -> String {
        let nfkc = input.precomposedStringWithCompatibilityMapping
        var output = String.UnicodeScalarView()
        output.reserveCapacity(nfkc.unicodeScalars.count)
        for scalar in nfkc.unicodeScalars {
            if Self.isZeroWidth(scalar) { continue }
            output.append(scalar)
        }
        return String(output)
    }

    /// Whether a Unicode scalar is a known PII-bypass zero-width
    /// character. Exposed `static` so tests can pin the exact list.
    static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200B, 0x200C, 0x200D, 0x200E, 0x200F: return true
        case 0x202A...0x202E: return true
        case 0x2066...0x2069: return true
        case 0xFEFF: return true
        default: return false
        }
    }

    /// Luhn checksum validator for credit-card candidate digit
    /// strings. Walks right-to-left, doubling every second digit and
    /// summing modulo 10. Returns `true` iff the sum is 0 mod 10.
    ///
    /// Exposed `static` so tests can hit the corner cases (the all-
    /// zero string is technically Luhn-valid; reject it separately
    /// at the call site if that matters).
    static func isLuhnValid(_ digits: String) -> Bool {
        guard !digits.isEmpty else { return false }
        var sum = 0
        var alt = false
        for character in digits.reversed() {
            guard let value = character.hexDigitValue, value < 10 else {
                return false
            }
            var digit = value
            if alt {
                digit *= 2
                if digit > 9 { digit -= 9 }
            }
            sum += digit
            alt.toggle()
        }
        return sum % 10 == 0
    }

    // MARK: - Overlap resolution

    /// One candidate match plus enough metadata to substitute it.
    private struct Candidate {
        let kind: RedactionPattern.Kind
        let token: String
        let range: Range<String.Index>
        let text: String
    }

    /// Pick a non-overlapping subset of candidates. Strategy: sort by
    /// (start offset asc, length desc, declaration order asc), then
    /// sweep left-to-right keeping any candidate whose start is at or
    /// past the previous kept candidate's end.
    private static func resolveOverlaps(
        _ candidates: [Candidate],
        in source: String
    ) -> [Candidate] {
        guard !candidates.isEmpty else { return [] }
        let sorted = candidates.sorted { left, right in
            if left.range.lowerBound != right.range.lowerBound {
                return left.range.lowerBound < right.range.lowerBound
            }
            // Longer span first.
            let leftLength = source.distance(
                from: left.range.lowerBound,
                to: left.range.upperBound
            )
            let rightLength = source.distance(
                from: right.range.lowerBound,
                to: right.range.upperBound
            )
            return leftLength > rightLength
        }
        var kept: [Candidate] = []
        var lastEnd: String.Index = source.startIndex
        for candidate in sorted {
            if candidate.range.lowerBound >= lastEnd {
                kept.append(candidate)
                lastEnd = candidate.range.upperBound
            }
        }
        return kept
    }
}
