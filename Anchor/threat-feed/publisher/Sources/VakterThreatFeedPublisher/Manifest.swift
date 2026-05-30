// Manifest.swift
//
// Codable mirrors of the bundle schema defined in
// `openspec/changes/vakter-watch-pivot/specs/threat-feed/bundle-schema.md`
// and `Anchor/threat-feed/schema/manifest.schema.json`. If the JSON Schema
// changes, these types must change too — the schema is authoritative.
//
// IMPORTANT: JSONEncoder is forced to .sortedKeys + no whitespace so the
// emitted manifest bytes (and therefore its sha256, which appears in
// latest.json) are reproducible across runs.

import Foundation

/// One row of `manifest.files`. Mirrors `$defs/FileEntry` in
/// `manifest.schema.json`.
public struct FileEntry: Codable, Equatable {
    public let name: String
    public let sha256: String
    public let entry_count: Int
    public let category: String

    public init(name: String, sha256: String, entry_count: Int, category: String) {
        self.name = name
        self.sha256 = sha256
        self.entry_count = entry_count
        self.category = category
    }
}

/// Top-level shape of `manifest.json`. Mirrors `manifest.schema.json`.
public struct Manifest: Codable, Equatable {
    public let schema_version: Int
    public let bundle_version: String
    public let published_at: String
    public let feed_host: String
    public let publisher_key_id: String
    public let files: [FileEntry]
    public let total_entry_count: Int
    public let previous_bundle_version: String?
    public let previous_bundle_sha256: String?

    public init(
        schema_version: Int,
        bundle_version: String,
        published_at: String,
        feed_host: String,
        publisher_key_id: String,
        files: [FileEntry],
        total_entry_count: Int,
        previous_bundle_version: String?,
        previous_bundle_sha256: String?
    ) {
        self.schema_version = schema_version
        self.bundle_version = bundle_version
        self.published_at = published_at
        self.feed_host = feed_host
        self.publisher_key_id = publisher_key_id
        self.files = files
        self.total_entry_count = total_entry_count
        self.previous_bundle_version = previous_bundle_version
        self.previous_bundle_sha256 = previous_bundle_sha256
    }
}

/// The 8 canonical category slugs in the order they must appear in
/// `manifest.files`. The schema enforces "exactly 8 entries, unique
/// category" — we match that here by construction.
public enum Category: String, CaseIterable {
    case phishingDomains = "phishing-domains"
    case phoneNumbers = "phone-numbers"
    case appleSupportFakes = "apple-support-fakes"
    case malwareBundleIds = "malware-bundle-ids"
    case smsTemplates = "sms-templates"
    case romanceScamPatterns = "romance-scam-patterns"
    case packageScamTemplates = "package-scam-templates"
    case sources = "sources"

    /// File name inside the tarball (per the canonical category table in
    /// the bundle-schema doc).
    public var fileName: String {
        switch self {
        case .phishingDomains:       return "phishing-domains.txt"
        case .phoneNumbers:          return "phone-numbers.txt"
        case .appleSupportFakes:     return "apple-support-fakes.txt"
        case .malwareBundleIds:      return "malware-bundle-ids.txt"
        case .smsTemplates:          return "sms-templates.json"
        case .romanceScamPatterns:   return "romance-scam-patterns.json"
        case .packageScamTemplates:  return "package-scam-templates.json"
        case .sources:               return "sources.json"
        }
    }
}

/// Reproducible JSON encoder for everything we sign or check the sha256
/// of. Sorted keys + no whitespace + 8601 timestamps so two runs of the
/// publisher on the same inputs produce byte-identical output.
public func makeReproducibleEncoder() -> JSONEncoder {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    enc.dateEncodingStrategy = .iso8601
    return enc
}
