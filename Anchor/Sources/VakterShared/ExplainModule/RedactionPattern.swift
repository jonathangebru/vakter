import Foundation

/// One entry in the PII pattern catalog used by ``PIIRedactor``.
///
/// Each pattern is a triple of (stable identifier, anchored regex,
/// replacement token). The redactor walks the catalog in deterministic
/// order, replacing every match with the pattern's token and tallying a
/// count per category so the "Show me what you see" audit panel (#71)
/// can show the user *what* was stripped without exposing the raw
/// values.
///
/// ## Why a separate type
///
/// Holding the catalog as data — rather than burying every regex inline
/// in ``PIIRedactor`` — makes three things easier:
///
/// 1. **Unit testing.** The 100+ adversarial test cases reach in and
///    assert on individual ``RedactionPattern`` matches without going
///    through the full pipeline.
/// 2. **Auditability.** A reviewer can read ``RedactionPattern/all`` and
///    see every category Vakter strips, in one place. No hidden regexes.
/// 3. **Performance hardening.** Each pattern's regex is compiled
///    exactly once at static-let init time. Catastrophic-backtracking
///    risk is contained to this file — anchored character classes,
///    bounded quantifiers, and possessive-style "no `.*.*`" rules
///    apply uniformly across the catalog.
///
/// ## Replacement token format
///
/// Tokens are square-bracketed UPPER_SNAKE strings (`[EMAIL]`, `[CC]`,
/// `[FILEPATH]`, …). The format is intentionally narrow:
///   - Square brackets so the audit panel can syntax-highlight matches.
///   - No category-specific suffixes (e.g. no `[EMAIL:****@example.com]`)
///     because preserving even partial PII inside the redacted prompt
///     widens the surface area an attacker — or a hallucinating model —
///     could exfiltrate. The brand contract is "Vakter never sends PII
///     to a model"; partial preservation is the start of a slippery
///     slope toward "but the domain is fine," so the redactor commits
///     to full-token replacement and lets the audit panel handle
///     transparency separately.
///
/// All patterns are `Sendable`-safe; the type holds only value-type
/// storage. The `NSRegularExpression` instance is itself thread-safe
/// for read-only `matches(in:options:range:)` calls.
public struct RedactionPattern: Sendable {

    /// Stable identifier — case-of of ``RedactionPattern/Kind``. Used as
    /// the dictionary key in ``RedactionResult/counts`` so callers can
    /// branch on a typed value rather than parsing the replacement
    /// token.
    public let kind: Kind

    /// Pre-compiled regex. Held by value (NSRegularExpression instances
    /// are reference types, but conform to `Sendable` via being
    /// immutable after construction). Compiled at module load via the
    /// `try!` in ``RedactionPattern/init(kind:rawPattern:token:options:)``
    /// — a failed compile is a programmer error, not a runtime
    /// condition, so crashing here is correct.
    public let regex: NSRegularExpression

    /// What gets substituted in place of each match. Includes the
    /// surrounding square brackets and ends with the upper-snake
    /// category name (e.g. `[EMAIL]`). The audit panel uses both the
    /// `kind` and the token to render a row like
    /// `EMAIL × 2 — replaced with [EMAIL]`.
    public let token: String

    /// Categories Vakter recognises and strips. Adding a new case is
    /// the supported extension point; the redactor walks every case
    /// in this enum's declaration order, so new categories must be
    /// appended at the end to keep test snapshots stable.
    public enum Kind: String, Sendable, Codable, Equatable, CaseIterable {
        /// Email addresses — `local@host.tld`.
        case email
        /// Phone numbers — international or domestic, 10–15 digits.
        case phone
        /// US Social Security Numbers — `XXX-XX-XXXX`.
        case ssn
        /// Credit-card numbers — 13–19 digits, Luhn-validated.
        case creditCard
        /// International Bank Account Numbers — `XX## …` 15–34 chars.
        case iban
        /// IPv4 / IPv6 addresses.
        case ipAddress
        /// Hardware MAC addresses — `XX:XX:XX:XX:XX:XX` or `XX-XX-…`.
        case macAddress
        /// Geographic GPS coordinates — `lat, long` decimal pairs.
        case gpsCoordinate
        /// macOS-style file paths under user folders (`~/Documents`, …).
        case filePath
        /// Apple-style bundle identifiers — `com.apple.foo.bar`.
        case bundleIdentifier
        /// HTTP / HTTPS / file / mailto URLs.
        case url
        /// API tokens — Bearer/Authorization secrets, base64-style.
        case apiToken
        /// 12+ consecutive digits not matched as CC, phone, or IBAN.
        /// Catches generic bank / account numbers.
        case accountNumber
        /// Social handles — `@username` at start of word.
        case socialHandle
    }
}

extension RedactionPattern {

    /// Convenience initialiser used by the static catalog. Force-tries
    /// the regex compile — see the type-level docs for why a failed
    /// compile is a programmer error rather than a runtime condition.
    init(
        kind: Kind,
        rawPattern: String,
        token: String,
        options: NSRegularExpression.Options = []
    ) {
        self.kind = kind
        // swiftlint:disable:next force_try
        self.regex = try! NSRegularExpression(pattern: rawPattern, options: options)
        self.token = token
    }

    /// The full pattern catalog, walked top-down by ``PIIRedactor``.
    ///
    /// Order matters — earlier patterns get first crack at a span of
    /// text, so categories that overlap (e.g. emails embedded inside
    /// URLs) need their precedence pinned here, not divined at runtime.
    /// The chosen order is roughly *most-specific first* so that:
    ///
    ///   - URLs match before emails (so `https://x.com/?u=a@b.com` becomes
    ///     a single `[URL]` rather than `https://x.com/?u=[EMAIL]`).
    ///   - File paths match before bundle IDs (so a path containing
    ///     `com.apple.foo` doesn't get half-redacted).
    ///   - Credit cards (Luhn-validated, post-pass) match before generic
    ///     account-number runs of digits.
    ///
    /// Each regex is **anchored with bounded quantifiers** — no `.*` at
    /// the start, no `.+` that can re-traverse the input. This is
    /// load-bearing for the <50ms per-test budget: catastrophic
    /// backtracking on attacker-controlled input would let a malicious
    /// prompt DoS the on-device model pipeline.
    public static let all: [RedactionPattern] = [

        // ---- URLs ---------------------------------------------------
        // Anchored at scheme so we don't match bare "host.com".
        // Bounded char class — no `.+` — to keep backtracking linear.
        // Two variants: `scheme://…` (http, https, ftp, file) and
        // `mailto:…` (no slashes — RFC 6068). Both branches share the
        // same bounded payload class so worst-case backtracking is
        // constant.
        RedactionPattern(
            kind: .url,
            rawPattern: #"\b(?:(?:https?|ftp|file):\/\/|mailto:)[^\s<>"'\\\\^`{|}]{1,2048}"#,
            token: "[URL]"
        ),

        // ---- File paths --------------------------------------------
        // macOS-style absolute paths under common user folders.
        // We accept `~` or `/Users/<name>` prefixes; the char class
        // permits spaces (real Mac paths have them) but is bounded.
        RedactionPattern(
            kind: .filePath,
            rawPattern: #"(?:~|\/Users\/[A-Za-z0-9_.-]{1,64})\/(?:Documents|Desktop|Downloads|Library|Movies|Music|Pictures|Public)\/[^\n\r\t<>"'|*?]{0,1024}"#,
            token: "[FILEPATH]"
        ),

        // ---- API tokens --------------------------------------------
        // Bearer-style secrets. We look for "Authorization", "Bearer",
        // "api_key", or "token" preceding a high-entropy run. The run
        // is constrained to 20–256 chars of `[A-Za-z0-9._\-+/=]` —
        // base64-ish with optional dots/dashes for JWTs.
        RedactionPattern(
            kind: .apiToken,
            rawPattern: #"(?i)(?:authorization|bearer|api[_-]?key|x-api-key|access[_-]?token|secret[_-]?key)\s*[:=]?\s*['"]?([A-Za-z0-9._\-+\/=]{20,256})['"]?"#,
            token: "[API_TOKEN]"
        ),

        // ---- Email --------------------------------------------------
        // Standard but conservative: ASCII local-part of 1–64 chars,
        // domain of 1–253 chars with at least one dot. Anchored at word
        // boundary so we don't match the inside of an opaque token.
        RedactionPattern(
            kind: .email,
            rawPattern: #"(?i)\b[A-Z0-9._%+\-]{1,64}@(?:[A-Z0-9](?:[A-Z0-9\-]{0,61}[A-Z0-9])?\.){1,8}[A-Z]{2,24}\b"#,
            token: "[EMAIL]"
        ),

        // ---- IBAN ---------------------------------------------------
        // 2 letters + 2 digits + 11–30 alnum. Allows internal spaces
        // (common in printed IBANs) but caps total span. We match
        // EAGERLY then verify in code via length+letter rules, so
        // the regex itself stays anchored and linear.
        RedactionPattern(
            kind: .iban,
            rawPattern: #"\b[A-Z]{2}[0-9]{2}(?:[ ]?[A-Z0-9]){11,30}\b"#,
            token: "[IBAN]"
        ),

        // ---- Credit card -------------------------------------------
        // 13–19 digits, optionally split by single spaces or dashes
        // every 4. Luhn-validated post-match in PIIRedactor — the
        // regex by itself is the *candidate* gate, not the decision.
        RedactionPattern(
            kind: .creditCard,
            rawPattern: #"\b(?:[0-9]{4}[ \-]?){2,4}[0-9]{1,4}\b"#,
            token: "[CC]"
        ),

        // ---- US SSN -------------------------------------------------
        // XXX-XX-XXXX, anchored so a 9-digit run inside a larger
        // number doesn't trigger.
        RedactionPattern(
            kind: .ssn,
            rawPattern: #"\b(?!000|666|9\d{2})[0-9]{3}-(?!00)[0-9]{2}-(?!0000)[0-9]{4}\b"#,
            token: "[SSN]"
        ),

        // ---- Phone --------------------------------------------------
        // International + domestic. Two branches separated by `|`,
        // each anchored with a negative-lookbehind/lookahead pair so
        // the phone class doesn't slurp adjacent digits or letters.
        //
        // Branch A (parens form, e.g. "(415) 555-1234"):
        //   optional `+CC `, then `(<area>)`, then 3–4 digits, then
        //   separator, then 3–4 digits, then optional separator and
        //   1–4 extension digits.
        //
        // Branch B (separator form, e.g. "415-555-1234",
        //   "+46 8-123-456", "+44 20-7946-0958"):
        //   optional `+CC`, then three digit groups separated by
        //   `[-. ]` — group lengths chosen so total digits stay in
        //   the 7–15 range typical for E.164.
        //
        // Both branches are bounded; the inner char classes are
        // explicit, no `.+`. Lookbehind/lookahead reject adjacent
        // word characters so dates like "2026-05-30" (no third
        // separator-padding) don't slip through.
        RedactionPattern(
            kind: .phone,
            rawPattern: #"(?<![A-Za-z0-9])(?:(?:\+[0-9]{1,3}[ ])?\([0-9]{1,4}\)[\-. ]?[0-9]{3,4}[\-. ][0-9]{3,4}|(?:\+[0-9]{1,3}[ ])?[0-9]{1,4}[\-. ][0-9]{2,4}[\-. ][0-9]{3,9})(?![A-Za-z0-9])"#,
            token: "[PHONE]"
        ),

        // ---- IPv6 --------------------------------------------------
        // Match before IPv4 because IPv6 can contain embedded v4 forms.
        // Bounded to <=8 groups of 1–4 hex chars.
        RedactionPattern(
            kind: .ipAddress,
            rawPattern: #"\b(?:[0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4}\b|\b(?:[0-9A-Fa-f]{1,4}:){1,7}:\b|\b(?:[0-9A-Fa-f]{1,4}:){1,6}(?::[0-9A-Fa-f]{1,4}){1,1}\b"#,
            token: "[IP]"
        ),

        // ---- IPv4 (separate pattern, same kind) ---------------------
        // Each octet 0–255. Anchored to word boundaries so the version
        // string "1.2.3.4" inside "ChangeLog v1.2.3.4-beta" still
        // matches (we don't try to be cleverer than the spec here;
        // false positives on version strings are acceptable — the
        // brand contract favours over-redaction over under-redaction).
        RedactionPattern(
            kind: .ipAddress,
            rawPattern: #"\b(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"#,
            token: "[IP]"
        ),

        // ---- MAC address -------------------------------------------
        // 6 groups of 2 hex chars, separated by `:` or `-`. Anchored.
        RedactionPattern(
            kind: .macAddress,
            rawPattern: #"\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b"#,
            token: "[MAC]"
        ),

        // ---- GPS coordinates ---------------------------------------
        // Decimal lat,long pair. Optional sign, 1–3 integer digits,
        // 1+ fractional digits, separator (comma + optional space),
        // same shape for longitude. Bounded.
        RedactionPattern(
            kind: .gpsCoordinate,
            rawPattern: #"(?<![0-9.])-?(?:90(?:\.0+)?|[0-8]?[0-9](?:\.[0-9]{1,10}))\s*,\s*-?(?:180(?:\.0+)?|1[0-7][0-9](?:\.[0-9]{1,10})|[0-9]?[0-9](?:\.[0-9]{1,10}))(?![0-9.])"#,
            token: "[GPS]"
        ),

        // ---- Bundle identifier -------------------------------------
        // Reverse-DNS style — 3+ dot-separated lowercase chunks.
        // Bounded to 5 chunks to avoid runaway matches.
        RedactionPattern(
            kind: .bundleIdentifier,
            rawPattern: #"\b(?:com|org|net|io|co|app|dev|me)\.[a-z][a-z0-9\-]{1,32}(?:\.[a-z][a-z0-9\-]{1,32}){1,4}\b"#,
            token: "[BUNDLE_ID]"
        ),

        // ---- Social handle -----------------------------------------
        // `@username` at start of word — 3–30 chars, alnum + `_`.
        // Anchored so we don't match the local-part of an email (the
        // email pattern ran earlier and replaced those already).
        RedactionPattern(
            kind: .socialHandle,
            rawPattern: #"(?<![A-Za-z0-9._%+\-])@[A-Za-z0-9_]{3,30}\b"#,
            token: "[HANDLE]"
        ),

        // ---- Generic account number (12+ digits) -------------------
        // Run after credit card (Luhn) so we don't double-flag. The
        // 12-digit floor is intentional: shorter runs are too noisy.
        RedactionPattern(
            kind: .accountNumber,
            rawPattern: #"\b[0-9]{12,24}\b"#,
            token: "[ACCOUNT_NUM]"
        )
    ]
}
