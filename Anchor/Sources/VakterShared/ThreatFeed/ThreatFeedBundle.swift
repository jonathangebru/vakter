import Foundation

/// In-memory representation of a single, verified threat-feed bundle.
///
/// **Brand contract — one-way.** A `ThreatFeedBundle` is the result of
/// the client *downloading*, *signature-verifying*, and *atomically
/// swapping in* a daily bundle. Nothing in this type's surface area
/// ever flows back to the publisher. The bundle is loaded from local
/// disk after the atomic swap has succeeded; from that moment forward
/// it is a read-only snapshot of the user's local threat indicators.
///
/// ## Why not flatten to per-file Codable types?
///
/// The eight category files have heterogeneous shapes: four are
/// line-delimited `.txt` files (domains, phone numbers, bundle IDs)
/// and four are JSON arrays of objects (patterns, sources). Modelling
/// each one as its own typed struct would couple the threat-feed
/// client (this ticket — #62) to the *consumers* of those indicators
/// (future Watch domains — Mail, Messages, Web, Mac — and #67's
/// EXPLAIN module). That coupling is premature.
///
/// At #62 the client's job is: download → verify → atomic-swap → hold
/// a verified bundle in memory. The downstream consumers will parse
/// the raw file bytes against their domain-specific schemas in their
/// own tickets. We therefore expose each category as `Data` keyed by
/// the canonical ``ThreatFeedCategory``, plus the parsed manifest.
public struct ThreatFeedBundle: Equatable, Sendable {

    /// The parsed manifest. Already signature-verified by the
    /// ``ThreatFeedClient`` before this struct is constructed.
    public let manifest: ThreatFeedManifest

    /// Raw bytes for each of the 8 canonical category files, keyed
    /// by category. Each file's SHA-256 has been verified against
    /// the manifest's `FileEntry.sha256` before this struct is
    /// constructed. Consumers parse the bytes against their own
    /// schemas in their respective tickets.
    public let categoryFiles: [ThreatFeedCategory: Data]

    /// Filesystem URL the bundle was loaded from. The atomic-swap
    /// directory `feed.current/`. Useful for diagnostics and for
    /// re-reading a single category on demand.
    public let onDiskURL: URL

    public init(
        manifest: ThreatFeedManifest,
        categoryFiles: [ThreatFeedCategory: Data],
        onDiskURL: URL
    ) {
        self.manifest = manifest
        self.categoryFiles = categoryFiles
        self.onDiskURL = onDiskURL
    }

    /// Convenience accessor for a single category's raw bytes. Returns
    /// `nil` if the bundle was constructed without that category
    /// (should never happen in production — the client always
    /// includes all 8 — but tests may construct partial bundles).
    public func data(for category: ThreatFeedCategory) -> Data? {
        categoryFiles[category]
    }
}
