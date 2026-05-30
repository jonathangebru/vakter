// Sources.swift
//
// Upstream-source adapters. Each adapter is a self-contained struct with
// one job: pull from a public threat-intel feed and return parsed
// indicator lines for one of the 8 bundle categories.
//
// Per ticket #61 the v1 publisher implements at least three categories.
// We ship adapters for:
//
//   - phishing-domains:   PhishTank verified-online CSV + URLhaus URLs CSV
//   - phone-numbers:      FCC robocall consumer complaints (open dataset)
//   - apple-support-fakes: a manually-curated, source-tracked allowlist
//                          (Anchor/threat-feed/sources/apple-support-fakes-manual.txt)
//
// The other 5 categories (malware-bundle-ids, sms-templates,
// romance-scam-patterns, package-scam-templates, sources) are wired up as
// empty/minimal adapters so a v1 bundle still has 8 files and validates.
// Subsequent tickets (#65 curation review) will broaden coverage.
//
// All adapters expose a synchronous `fetch()` that returns the raw upstream
// bytes for that source. In dry-run mode the publisher feeds them fixture
// bytes instead of hitting the network — see `FetcherProtocol` below.

import Foundation

// MARK: - Source attribution

/// One row of `sources.json`. Mirrors the JSON Schema in
/// `Anchor/threat-feed/schema/categories/sources.schema.json`. Built up
/// during publishing as each adapter records what it pulled.
public struct SourceRecord: Codable, Equatable {
    public let id: String
    public let name: String
    public let url: String
    public let license: String
    public let permission_note: String?
    public let categories: [String]
    public let fetched_at: String

    public init(
        id: String,
        name: String,
        url: String,
        license: String,
        permission_note: String? = nil,
        categories: [String],
        fetched_at: String
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.license = license
        self.permission_note = permission_note
        self.categories = categories
        self.fetched_at = fetched_at
    }
}

public struct SourcesFile: Codable, Equatable {
    public let sources: [SourceRecord]
    public init(sources: [SourceRecord]) { self.sources = sources }
}

// MARK: - Fetcher abstraction

/// Indirection over HTTP so tests can supply fixture bytes instead of
/// hitting PhishTank in CI. Production uses the URLSession-backed
/// `URLSessionFetcher`.
public protocol FetcherProtocol {
    func fetch(_ url: URL) throws -> Data
}

/// Tiny synchronous URLSession fetcher. The publisher is a batch job,
/// not a server, so blocking the thread for an HTTP GET is fine.
///
/// We use a reference-typed box so the completion handler (which is
/// `@Sendable` under Swift 6) can write the result without triggering
/// the "mutation of captured var in concurrently-executing code"
/// diagnostic.
public struct URLSessionFetcher: FetcherProtocol {
    public init() {}
    public func fetch(_ url: URL) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue(
            "vakter-threat-feed-publisher/1.0 (+https://vakter.app)",
            forHTTPHeaderField: "User-Agent"
        )
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                box.set(.failure(error))
            } else if let data = data {
                box.set(.success(data))
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        return try box.get()
    }
}

/// Thread-safe reference holder for the URLSession completion result.
final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<Data, Error> = .failure(
        NSError(
            domain: "VakterPublisher",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "fetch never returned"]
        )
    )
    func set(_ r: Result<Data, Error>) {
        lock.lock(); defer { lock.unlock() }
        stored = r
    }
    func get() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        return try stored.get()
    }
}

/// Test/dry-run fetcher: in-memory map of URL -> fixture bytes.
public struct FixtureFetcher: FetcherProtocol {
    let table: [URL: Data]
    public init(_ table: [URL: Data]) { self.table = table }
    public init(_ table: [String: Data]) {
        var t = [URL: Data]()
        for (k, v) in table {
            if let u = URL(string: k) { t[u] = v }
        }
        self.table = t
    }
    public func fetch(_ url: URL) throws -> Data {
        guard let data = table[url] else {
            throw NSError(
                domain: "FixtureFetcher",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "no fixture for \(url)"]
            )
        }
        return data
    }
}

// MARK: - PhishTank adapter (phishing-domains)

/// PhishTank publishes a CSV of verified phishing URLs. The v1 adapter
/// reads the CSV, extracts URLs from the `url` column, parses the host,
/// and emits lowercase ASCII / punycode domains. License: open-data (the
/// dataset is free for non-commercial / verified use).
public struct PhishTankAdapter {
    public static let id = "phishtank"
    public static let url = URL(string: "https://data.phishtank.com/data/online-valid.csv")!
    public let fetcher: FetcherProtocol
    public init(fetcher: FetcherProtocol = URLSessionFetcher()) {
        self.fetcher = fetcher
    }

    public func fetchDomains() throws -> [String] {
        let bytes = try fetcher.fetch(PhishTankAdapter.url)
        return Self.parseCSV(bytes)
    }

    /// Public for testing. Expects the upstream CSV with at least a `url`
    /// column header.
    public static func parseCSV(_ data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var rows = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        guard let headerRow = rows.first else { return [] }
        let headers = splitCSVRow(String(headerRow))
        guard let urlCol = headers.firstIndex(of: "url") else { return [] }
        rows.removeFirst()
        var out: [String] = []
        for row in rows {
            let cols = splitCSVRow(String(row))
            guard urlCol < cols.count else { continue }
            if let host = hostFromURL(cols[urlCol]) {
                out.append(host)
            }
        }
        return out
    }
}

// MARK: - URLhaus adapter (phishing-domains)

/// URLhaus (abuse.ch) publishes a daily CSV of malicious URLs. License: CC0.
/// We treat the URL list as a domain source for `phishing-domains.txt`.
public struct URLhausAdapter {
    public static let id = "urlhaus"
    public static let url = URL(string: "https://urlhaus.abuse.ch/downloads/csv_recent/")!
    public let fetcher: FetcherProtocol
    public init(fetcher: FetcherProtocol = URLSessionFetcher()) {
        self.fetcher = fetcher
    }

    public func fetchDomains() throws -> [String] {
        let bytes = try fetcher.fetch(URLhausAdapter.url)
        return Self.parseCSV(bytes)
    }

    /// URLhaus CSV: comment lines start with `#`. Columns:
    /// `id,dateadded,url,url_status,last_online,threat,tags,urlhaus_link,reporter`.
    public static func parseCSV(_ data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var out: [String] = []
        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(raw)
            if line.hasPrefix("#") || line.isEmpty { continue }
            let cols = splitCSVRow(line)
            // Field index 2 is the URL per the upstream README.
            guard cols.count > 2 else { continue }
            if let host = hostFromURL(cols[2]) {
                out.append(host)
            }
        }
        return out
    }
}

// MARK: - FCC robocall adapter (phone-numbers)

/// The FCC consumer complaint open dataset includes a `caller_id_number`
/// column for unwanted-call complaints. License: public-domain (US gov).
/// The actual export URL is via Socrata; we keep the URL configurable so
/// dry-run can swap in a fixture without hitting the live API.
public struct FCCRobocallAdapter {
    public static let id = "fcc-consumer-complaints"
    /// Socrata "Unwanted Calls" dataset CSV (public).
    public static let url = URL(string: "https://opendata.fcc.gov/resource/sr6c-syda.csv?$limit=2000")!
    public let fetcher: FetcherProtocol
    public init(fetcher: FetcherProtocol = URLSessionFetcher()) {
        self.fetcher = fetcher
    }

    public func fetchPhoneNumbers() throws -> [String] {
        let bytes = try fetcher.fetch(FCCRobocallAdapter.url)
        return Self.parseCSV(bytes)
    }

    /// Returns E.164 numbers. Accepts US-formatted input ("(800) 555-1234"
    /// or "8005551234"), normalises to "+1<10digits>". Numbers we can't
    /// confidently normalise are dropped, not guessed.
    public static func parseCSV(_ data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var rows = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        guard let headerRow = rows.first else { return [] }
        let headers = splitCSVRow(String(headerRow))
        guard let col = headers.firstIndex(where: { $0.contains("caller_id_number") })
              ?? headers.firstIndex(where: { $0.contains("phone") }) else {
            return []
        }
        rows.removeFirst()
        var out: [String] = []
        for row in rows {
            let cols = splitCSVRow(String(row))
            guard col < cols.count else { continue }
            if let e164 = normaliseUSPhone(cols[col]) {
                out.append(e164)
            }
        }
        return out
    }
}

// MARK: - Apple Support fakes (manually curated)

/// Local seed list of Apple-impersonation domains, kept under
/// `Anchor/threat-feed/sources/apple-support-fakes-manual.txt`. License:
/// vakter-curated. Each entry is sourced from public security blogs;
/// follow-on tickets (#65) will widen the list.
public struct AppleSupportFakesAdapter {
    public static let id = "vakter-apple-support-fakes-manual"
    public let path: URL
    public init(path: URL) {
        self.path = path
    }

    public func fetchDomains() throws -> [String] {
        let raw = try Data(contentsOf: path)
        guard let text = String(data: raw, encoding: .utf8) else { return [] }
        return Self.parseText(text)
    }

    /// Strip comments and blanks. Each remaining line is `<domain>` with an
    /// optional trailing comment "# first-seen YYYY-MM-DD" already on its
    /// own line, per `phishing-domains.txt` rules.
    public static func parseText(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(raw)
            if line.hasPrefix("#") { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // Permit "domain.example   # first-seen 2026-..." form.
            let first = trimmed.split(separator: " ").first.map(String.init)
                ?? trimmed
            out.append(first.lowercased())
        }
        return out
    }
}

// MARK: - CSV / URL helpers (intentionally tiny)

/// Tokeniser for one CSV row. Handles double-quoted strings with
/// embedded commas and `""` escapes. Good enough for the well-formed
/// public CSVs we consume; not a fully-conformant RFC 4180 parser.
public func splitCSVRow(_ row: String) -> [String] {
    var fields: [String] = []
    var cur = ""
    var inQuotes = false
    var i = row.startIndex
    while i < row.endIndex {
        let c = row[i]
        if inQuotes {
            if c == "\"" {
                let next = row.index(after: i)
                if next < row.endIndex && row[next] == "\"" {
                    cur.append("\"")
                    i = next
                } else {
                    inQuotes = false
                }
            } else {
                cur.append(c)
            }
        } else {
            if c == "\"" {
                inQuotes = true
            } else if c == "," {
                fields.append(cur)
                cur = ""
            } else {
                cur.append(c)
            }
        }
        i = row.index(after: i)
    }
    fields.append(cur)
    return fields
}

/// Pull the host out of `http://foo/bar` or `https://foo:8080/bar?q=1`
/// without using `URLComponents` (URLComponents rejects some malformed
/// URLs we still want hosts from). Returns lowercase host or nil.
public func hostFromURL(_ raw: String) -> String? {
    var s = raw.trimmingCharacters(in: .whitespaces)
    if s.isEmpty { return nil }
    if let schemeEnd = s.range(of: "://") {
        s = String(s[schemeEnd.upperBound...])
    }
    if let slash = s.firstIndex(of: "/") {
        s = String(s[..<slash])
    }
    if let q = s.firstIndex(of: "?") {
        s = String(s[..<q])
    }
    if let at = s.firstIndex(of: "@") {
        // userinfo@host
        s = String(s[s.index(after: at)...])
    }
    if let colon = s.firstIndex(of: ":") {
        s = String(s[..<colon])
    }
    s = s.lowercased()
    // Reject IPs (digits and dots only).
    if s.allSatisfy({ $0.isNumber || $0 == "." }) { return nil }
    // Need at least one dot (eTLD+1).
    guard s.contains(".") else { return nil }
    // Reject anything that doesn't match the post-parse regex from the
    // phishing-domains schema. We keep this slightly looser to catch
    // upstream typos and drop them silently.
    let allowed: Set<Character> = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
    guard s.allSatisfy({ allowed.contains($0) }) else { return nil }
    return s
}

/// Normalise messy US phone strings to E.164. Drops anything we can't be
/// confident about — false E.164 numbers are worse than no number.
public func normaliseUSPhone(_ raw: String) -> String? {
    let digits = raw.unicodeScalars
        .filter { CharacterSet.decimalDigits.contains($0) }
        .map { Character($0) }
    let s = String(digits)
    if s.count == 10 { return "+1" + s }
    if s.count == 11, s.first == "1" { return "+" + s }
    return nil
}
