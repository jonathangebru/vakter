// Publisher.swift
//
// The orchestration layer. Given a set of source adapters, builds the 8
// category files, writes them to `out/v1/`, computes sha256s, assembles
// `manifest.json`, then signs the tarball.
//
// This file is the entry point exercised by both the CLI (Main.swift) and
// the test suite. Network access lives in the adapters (`Sources.swift`),
// not here — `Publisher` only handles bytes.

import Foundation
import Crypto

/// One-stop bundle of inputs for the publisher run. The CLI fills this
/// in from env vars and command-line flags; tests build it inline.
public struct PublisherConfig {
    public var outputDirectory: URL
    public var bundleDate: Date
    public var feedHost: String
    public var publisherKeyID: String
    public var schemaVersion: Int
    public var phishTank: PhishTankAdapter
    public var urlHaus: URLhausAdapter
    public var fccRobocall: FCCRobocallAdapter
    public var appleSupportFakes: AppleSupportFakesAdapter
    public var previousBundleVersion: String?
    public var previousBundleSHA256: String?
    public var signer: Signer

    public init(
        outputDirectory: URL,
        bundleDate: Date = Date(),
        feedHost: String = "feed.vakter.app",
        publisherKeyID: String,
        schemaVersion: Int = 1,
        phishTank: PhishTankAdapter,
        urlHaus: URLhausAdapter,
        fccRobocall: FCCRobocallAdapter,
        appleSupportFakes: AppleSupportFakesAdapter,
        previousBundleVersion: String? = nil,
        previousBundleSHA256: String? = nil,
        signer: Signer
    ) {
        self.outputDirectory = outputDirectory
        self.bundleDate = bundleDate
        self.feedHost = feedHost
        self.publisherKeyID = publisherKeyID
        self.schemaVersion = schemaVersion
        self.phishTank = phishTank
        self.urlHaus = urlHaus
        self.fccRobocall = fccRobocall
        self.appleSupportFakes = appleSupportFakes
        self.previousBundleVersion = previousBundleVersion
        self.previousBundleSHA256 = previousBundleSHA256
        self.signer = signer
    }
}

public enum PublisherError: Error, CustomStringConvertible {
    case schemaCheckFailed(String)
    case alreadyPublished(String)

    public var description: String {
        switch self {
        case .schemaCheckFailed(let why):
            return "Schema check failed: \(why)"
        case .alreadyPublished(let v):
            return "Bundle version \(v) already exists in the output directory."
        }
    }
}

/// Result of one publish run. Returned from `Publisher.run()` so tests
/// can assert on what was written without re-reading disk.
public struct PublishResult: Equatable {
    public let bundleDirectory: URL
    public let bundleVersion: String
    public let manifest: Manifest
    /// Sha256 of `manifest.json` as written to disk.
    public let manifestSHA256: String
    /// Sha256 of the tarball that was signed. Echoed into `latest.json`.
    public let tarballSHA256: String
    /// Detached signature bytes (64 raw bytes).
    public let signature: Data
}

public struct Publisher {
    public let config: PublisherConfig
    public init(_ config: PublisherConfig) { self.config = config }

    /// Build, validate, write, and sign the bundle.
    @discardableResult
    public func run() throws -> PublishResult {
        let fm = FileManager.default
        try fm.createDirectory(
            at: config.outputDirectory,
            withIntermediateDirectories: true
        )

        // ----- 1. Pull from adapters -----
        let phishingDomains = try gatherPhishingDomains()
        let phoneNumbers = try gatherPhoneNumbers()
        let appleSupport = try gatherAppleSupportFakes()

        // ----- 2. Build empty/seed files for the other 5 categories -----
        //
        // The bundle schema is "exactly 8 files". For v1 the publisher
        // only has live coverage of 3 categories; the other 5 are emitted
        // as schema-valid empty files. Subsequent tickets (#65) will
        // populate them. Treating "0 entries" as legal is the same path
        // the client uses when a category genuinely empties out.
        let malwareBundleIds: [String] = []
        let smsTemplates: [SMSTemplate] = []
        let romanceScamPatterns: [RomancePattern] = []
        let packageScamTemplates: [PackageTemplate] = []

        // ----- 3. Assemble sources.json -----
        let now = isoTimestamp(config.bundleDate)
        let sources = SourcesFile(sources: [
            SourceRecord(
                id: "phishtank-" + dateOnly(config.bundleDate),
                name: "PhishTank",
                url: "https://phishtank.org/",
                license: "open-data",
                permission_note: nil,
                categories: ["phishing-domains"],
                fetched_at: now
            ),
            SourceRecord(
                id: "urlhaus-" + dateOnly(config.bundleDate),
                name: "URLhaus (abuse.ch)",
                url: "https://urlhaus.abuse.ch/",
                license: "CC0",
                permission_note: nil,
                categories: ["phishing-domains"],
                fetched_at: now
            ),
            SourceRecord(
                id: "fcc-consumer-complaints-" + dateOnly(config.bundleDate),
                name: "FCC Consumer Complaint Data — Unwanted Calls",
                url: "https://opendata.fcc.gov/Consumer/CGB-Consumer-Complaints-Data/3xyp-aqkj",
                license: "public-domain",
                permission_note: nil,
                categories: ["phone-numbers"],
                fetched_at: now
            ),
            SourceRecord(
                id: "vakter-apple-support-fakes-manual",
                name: "Vakter manually-curated Apple-impersonation list",
                url: "https://github.com/jonathangebru/vakter/blob/main/Anchor/threat-feed/sources/apple-support-fakes-manual.txt",
                license: "vakter-curated",
                permission_note: nil,
                categories: ["apple-support-fakes"],
                fetched_at: now
            )
        ])

        // ----- 4. Hard fail: any proprietary-with-permission needs permission_note -----
        for s in sources.sources where s.license == "proprietary-with-permission" {
            guard let n = s.permission_note, !n.isEmpty else {
                throw PublisherError.schemaCheckFailed(
                    "source \(s.id) is proprietary-with-permission but has no permission_note"
                )
            }
        }

        // ----- 5. Render each file's bytes -----
        let phishingDomainsBytes = renderDomainsTxt(
            title: "phishing-domains",
            domains: phishingDomains
        )
        let phoneNumbersBytes = renderPhonesTxt(numbers: phoneNumbers)
        let appleSupportBytes = renderDomainsTxt(
            title: "apple-support-fakes",
            domains: appleSupport
        )
        let malwareBundleIdsBytes = renderBundleIdsTxt(ids: malwareBundleIds)

        let enc = makeReproducibleEncoder()
        let smsBytes = try enc.encode(smsTemplates)
        let romanceBytes = try enc.encode(romanceScamPatterns)
        let packageBytes = try enc.encode(packageScamTemplates)
        let sourcesBytes = try enc.encode(sources)

        // ----- 6. Bundle directory + write files -----
        let bundleVersion = try resolveBundleVersion()
        // Directory name uses the full version (including any .N suffix)
        // so two same-day publishes do not stomp each other's files.
        let bundleDir = config.outputDirectory.appendingPathComponent(
            "feed-" + bundleVersionToDirComponent(bundleVersion)
        )
        try fm.createDirectory(at: bundleDir, withIntermediateDirectories: true)

        let writes: [(Category, Data)] = [
            (.phishingDomains, phishingDomainsBytes),
            (.phoneNumbers, phoneNumbersBytes),
            (.appleSupportFakes, appleSupportBytes),
            (.malwareBundleIds, malwareBundleIdsBytes),
            (.smsTemplates, smsBytes),
            (.romanceScamPatterns, romanceBytes),
            (.packageScamTemplates, packageBytes),
            (.sources, sourcesBytes)
        ]
        var fileEntries: [FileEntry] = []
        for (category, bytes) in writes {
            let path = bundleDir.appendingPathComponent(category.fileName)
            try bytes.write(to: path)
            let sha = sha256Hex(bytes)
            let count = entryCount(category: category, bytes: bytes, sources: sources)
            fileEntries.append(FileEntry(
                name: category.fileName,
                sha256: sha,
                entry_count: count,
                category: category.rawValue
            ))
        }

        // ----- 7. Manifest -----
        let total = fileEntries.reduce(0) { $0 + $1.entry_count }
        let manifest = Manifest(
            schema_version: config.schemaVersion,
            bundle_version: bundleVersion,
            published_at: now,
            feed_host: config.feedHost,
            publisher_key_id: config.publisherKeyID,
            files: fileEntries,
            total_entry_count: total,
            previous_bundle_version: config.previousBundleVersion,
            previous_bundle_sha256: config.previousBundleSHA256
        )

        // schema rigour: 8 files exactly, unique categories
        guard manifest.files.count == 8 else {
            throw PublisherError.schemaCheckFailed("expected 8 file entries, got \(manifest.files.count)")
        }
        let cats = Set(manifest.files.map { $0.category })
        guard cats.count == 8 else {
            throw PublisherError.schemaCheckFailed("category column must be unique across the 8 files")
        }
        guard manifest.total_entry_count == total else {
            throw PublisherError.schemaCheckFailed("total_entry_count drift")
        }

        let manifestBytes = try enc.encode(manifest)
        let manifestPath = bundleDir.appendingPathComponent("manifest.json")
        try manifestBytes.write(to: manifestPath)

        // ----- 8. Tarball + signature -----
        let tarball = try makeTar(bundleDir: bundleDir)
        let stem = "feed-" + bundleVersionToDirComponent(bundleVersion)
        let tarPath = config.outputDirectory.appendingPathComponent(stem + ".tar.gz")
        try tarball.write(to: tarPath)
        let tarSHA = sha256Hex(tarball)

        let signature = try config.signer.sign(tarball)
        let sigPath = config.outputDirectory.appendingPathComponent(stem + ".sig")
        try signature.write(to: sigPath)

        // latest.json pointer
        let latest: [String: Any] = [
            "date": dateDirComponent(bundleVersion),
            "bundle_version": bundleVersion,
            "sha256": tarSHA
        ]
        let latestData = try JSONSerialization.data(
            withJSONObject: latest,
            options: [.sortedKeys]
        )
        try latestData.write(to: config.outputDirectory.appendingPathComponent("latest.json"))

        return PublishResult(
            bundleDirectory: bundleDir,
            bundleVersion: bundleVersion,
            manifest: manifest,
            manifestSHA256: sha256Hex(manifestBytes),
            tarballSHA256: tarSHA,
            signature: signature
        )
    }

    // MARK: - Adapter calls + dedup/normalize

    func gatherPhishingDomains() throws -> [(domain: String, source: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for d in try config.phishTank.fetchDomains() where seen.insert(d).inserted {
            out.append((d, "phishtank"))
        }
        for d in try config.urlHaus.fetchDomains() where seen.insert(d).inserted {
            out.append((d, "urlhaus"))
        }
        return out
    }

    func gatherPhoneNumbers() throws -> [(e164: String, source: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for n in try config.fccRobocall.fetchPhoneNumbers() where seen.insert(n).inserted {
            out.append((n, "fcc"))
        }
        return out
    }

    func gatherAppleSupportFakes() throws -> [(domain: String, source: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for d in try config.appleSupportFakes.fetchDomains() where seen.insert(d).inserted {
            out.append((d, "vakter-manual"))
        }
        return out
    }

    // MARK: - Rendering

    func renderDomainsTxt(title: String, domains: [(domain: String, source: String)]) -> Data {
        var s = "# \(title) — Vakter threat feed (auto-generated)\n"
        s += "# One lowercase domain per line. See bundle-schema.md.\n\n"
        for (d, _) in domains {
            s += "\(d)\n"
        }
        return s.data(using: .utf8) ?? Data()
    }

    func renderPhonesTxt(numbers: [(e164: String, source: String)]) -> Data {
        var s = "# phone-numbers — Vakter threat feed (auto-generated)\n"
        s += "# One E.164 number per line. See bundle-schema.md.\n\n"
        for (n, _) in numbers {
            s += "\(n)\n"
        }
        return s.data(using: .utf8) ?? Data()
    }

    func renderBundleIdsTxt(ids: [String]) -> Data {
        var s = "# malware-bundle-ids — Vakter threat feed (auto-generated)\n"
        s += "# One CFBundleIdentifier per line. See bundle-schema.md.\n\n"
        for id in ids { s += "\(id)\n" }
        return s.data(using: .utf8) ?? Data()
    }

    // MARK: - entry_count rule (txt vs json) per bundle-schema.md

    func entryCount(category: Category, bytes: Data, sources: SourcesFile) -> Int {
        switch category {
        case .phishingDomains, .phoneNumbers, .appleSupportFakes, .malwareBundleIds:
            guard let text = String(data: bytes, encoding: .utf8) else { return 0 }
            return text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                .filter { line in
                    let s = line.trimmingCharacters(in: .whitespaces)
                    return !s.isEmpty && !s.hasPrefix("#")
                }
                .count
        case .smsTemplates, .romanceScamPatterns, .packageScamTemplates:
            // top-level JSON array length
            if let any = try? JSONSerialization.jsonObject(with: bytes),
               let arr = any as? [Any] {
                return arr.count
            }
            return 0
        case .sources:
            return sources.sources.count
        }
    }

    // MARK: - Bundle versioning (incl. same-day .N suffix per #60)

    func resolveBundleVersion() throws -> String {
        let base = dateOnly(config.bundleDate)
            .replacingOccurrences(of: "-", with: ".")
        // YYYY.MM.DD base. Check for existing same-day bundles in outputDirectory.
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: config.outputDirectory.path) else {
            return base
        }
        // We look for both `feed-YYYY-MM-DD.tar.gz` and same-day .N suffixes.
        let dateDir = dateDirComponent(base)
        let sameDay = entries.compactMap { name -> Int? in
            // feed-YYYY-MM-DD.tar.gz                       => 0
            // feed-YYYY-MM-DD.N.tar.gz                     => N
            guard name.hasSuffix(".tar.gz") else { return nil }
            let stripped = String(name.dropLast(".tar.gz".count))
            if stripped == "feed-" + dateDir { return 0 }
            let prefix = "feed-" + dateDir + "."
            if stripped.hasPrefix(prefix) {
                let suffix = String(stripped.dropFirst(prefix.count))
                return Int(suffix)
            }
            return nil
        }
        guard let max = sameDay.max() else { return base }
        return base + "." + String(max + 1)
    }
}

// MARK: - JSON-array category stub types

/// Stub types kept here (not in Manifest.swift) because they belong to
/// the publisher's emission contract, not to the manifest contract.
/// v1 emits empty arrays. #65 will fill them in.
struct SMSTemplate: Codable, Equatable {
    let id: String
    let pattern: String
    let category: String
    let source_id: String
    let first_seen: String
}

struct RomancePattern: Codable, Equatable {
    let id: String
    let narrative_tags: [String]
    let minimum_signals: Int
    let category: String
    let source_id: String
    let first_seen: String
}

struct PackageTemplate: Codable, Equatable {
    let id: String
    let shipper: String
    let channels: [String]
    let pattern: String
    let category: String
    let source_id: String
    let first_seen: String
}

// MARK: - sha256 / time helpers

public func sha256Hex(_ data: Data) -> String {
    Data(SHA256.hash(data: data)).hexString()
}

public func dateOnly(_ d: Date) -> String {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
    return f.string(from: d)
}

public func dateDirComponent(_ versionOrDate: String) -> String {
    // Accepts "2026.05.29" or "2026.05.29.2" or "2026-05-29".
    // Returns the dashed "2026-05-29" used in file names.
    let trimmed = versionOrDate.split(separator: ".").prefix(3).joined(separator: "-")
    return trimmed
}

/// Like `dateDirComponent`, but preserves any `.N` suffix as `.N` so
/// the tarball/sig/bundle-dir names disambiguate same-day re-publishes.
/// Input  "2026.05.29"    -> "2026-05-29"
/// Input  "2026.05.29.2"  -> "2026-05-29.2"
public func bundleVersionToDirComponent(_ bundleVersion: String) -> String {
    let parts = bundleVersion.split(separator: ".").map(String.init)
    guard parts.count >= 3 else { return bundleVersion }
    let date = parts[0..<3].joined(separator: "-")
    let suffix = parts.dropFirst(3)
    if suffix.isEmpty { return date }
    return date + "." + suffix.joined(separator: ".")
}

public func isoTimestamp(_ d: Date) -> String {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.formatOptions = [
        .withInternetDateTime,
        .withFractionalSeconds
    ]
    return f.string(from: d)
}
