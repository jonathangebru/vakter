import Foundation

/// Codable types for the threat-feed manifest (`manifest.json`).
///
/// **Canonical spec:** `openspec/changes/vakter-watch-pivot/specs/threat-feed/bundle-schema.md`.
/// **JSON Schema:** `Anchor/threat-feed/schema/manifest.schema.json` (from #60).
///
/// The manifest is the bundle's table of contents. Every other file in
/// the bundle is listed here with its SHA-256. The threat-feed client
/// (this module) verifies the Ed25519 signature on the manifest file
/// itself, then validates each category file's SHA-256 against the
/// `files` array, then loads each file.
///
/// ## One-way contract
///
/// The threat-feed client is **download-only**. Vakter NEVER uploads
/// anything to the publisher. There is no query API, no per-user
/// state, no telemetry. The same bytes are served to every Vakter
/// installation in the world. This file's `Codable` types parse the
/// bundle the client has already downloaded; they do not produce
/// outbound network traffic.
///
/// ## Canonical category slugs (the closed vocabulary)
///
/// The manifest's `files` array MUST contain exactly 8 entries — one
/// per slug below. Unknown category strings are a hard reject at the
/// client. See ``ThreatFeedCategory`` for the typed enum.
public struct ThreatFeedManifest: Codable, Equatable, Sendable {

    /// Schema axis. The bundle-schema document defines the current
    /// value as `1`. Clients refuse bundles whose `schemaVersion`
    /// exceeds the highest version they know.
    public let schemaVersion: Int

    /// Date-based bundle version, format `YYYY.MM.DD` (or
    /// `YYYY.MM.DD.N` for same-day re-publishes). Monotonic across
    /// the publisher's lifetime. The client uses lexicographic
    /// compare to decide "is this newer than what I have?".
    public let bundleVersion: String

    /// RFC 3339 UTC timestamp when the publisher signed this bundle.
    /// Always ends in `Z`. Decoded as a string so the manifest can
    /// round-trip exactly through the verifier — the Ed25519
    /// signature is over the raw bytes, so we never re-emit the JSON
    /// on the client.
    public let publishedAt: String

    /// Publishing host. The client requires the exact constant
    /// `feed.vakter.app`. Reject if it doesn't match.
    public let feedHost: String

    /// Identifier of the Ed25519 key that signed the bundle. The
    /// client carries a list of known public keys keyed by this id.
    /// Format `vakter-feed-YYYY-qN`. Quarter-rotated by the
    /// publisher.
    public let publisherKeyId: String

    /// Exactly 8 entries — one per canonical category slug. The
    /// client validates `files.count == 8` and rejects otherwise.
    public let files: [FileEntry]

    /// Sum of `entryCount` across `files`. The client cross-checks
    /// this against the parsed sum; mismatch is a hard reject.
    public let totalEntryCount: Int

    /// The previous bundle's `bundleVersion`. Absent for the first
    /// bundle ever published.
    public let previousBundleVersion: String?

    /// The previous bundle's tarball SHA-256. Absent for the first
    /// bundle ever published.
    public let previousBundleSha256: String?

    public init(
        schemaVersion: Int,
        bundleVersion: String,
        publishedAt: String,
        feedHost: String,
        publisherKeyId: String,
        files: [FileEntry],
        totalEntryCount: Int,
        previousBundleVersion: String? = nil,
        previousBundleSha256: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.bundleVersion = bundleVersion
        self.publishedAt = publishedAt
        self.feedHost = feedHost
        self.publisherKeyId = publisherKeyId
        self.files = files
        self.totalEntryCount = totalEntryCount
        self.previousBundleVersion = previousBundleVersion
        self.previousBundleSha256 = previousBundleSha256
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case bundleVersion = "bundle_version"
        case publishedAt = "published_at"
        case feedHost = "feed_host"
        case publisherKeyId = "publisher_key_id"
        case files
        case totalEntryCount = "total_entry_count"
        case previousBundleVersion = "previous_bundle_version"
        case previousBundleSha256 = "previous_bundle_sha256"
    }

    /// One row in the manifest's `files` array. Describes a single
    /// category file's name, SHA-256, entry count, and category slug.
    public struct FileEntry: Codable, Equatable, Sendable {
        /// Filename inside the bundle. Must match
        /// `^[a-z][a-z0-9-]*\.(txt|json)$`. No path components.
        public let name: String

        /// Lowercase hex SHA-256 of the file's bytes. The client
        /// computes the SHA-256 of the downloaded file and rejects
        /// the whole bundle if any entry's hash mismatches.
        public let sha256: String

        /// Number of indicators in the file. For `.txt` files this
        /// is the non-comment, non-blank line count. For `.json`
        /// files this is the top-level array length.
        public let entryCount: Int

        /// One of the 8 canonical category slugs. The client maps
        /// this to ``ThreatFeedCategory``; an unknown slug is a
        /// hard reject.
        public let category: String

        public init(
            name: String,
            sha256: String,
            entryCount: Int,
            category: String
        ) {
            self.name = name
            self.sha256 = sha256
            self.entryCount = entryCount
            self.category = category
        }

        enum CodingKeys: String, CodingKey {
            case name
            case sha256
            case entryCount = "entry_count"
            case category
        }
    }
}

/// The 8 canonical category slugs. See bundle-schema.md "Canonical
/// category slugs" for the table.
///
/// The client uses this enum to type-check `FileEntry.category`. Any
/// string outside this closed vocabulary is a hard reject.
public enum ThreatFeedCategory: String, CaseIterable, Codable, Sendable {
    case phishingDomains = "phishing-domains"
    case phoneNumbers = "phone-numbers"
    case appleSupportFakes = "apple-support-fakes"
    case malwareBundleIds = "malware-bundle-ids"
    case smsTemplates = "sms-templates"
    case romanceScamPatterns = "romance-scam-patterns"
    case packageScamTemplates = "package-scam-templates"
    case sources

    /// The required filename inside the bundle for this category.
    /// Used by the client to look up file bytes after the manifest
    /// has been parsed.
    public var requiredFilename: String {
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
