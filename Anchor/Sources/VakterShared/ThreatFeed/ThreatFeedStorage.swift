import Foundation

/// On-disk layout for the threat-feed client's local cache.
///
/// ## Directory layout
///
/// ```
/// ~/Library/Application Support/Vakter/ThreatFeed/
/// ├── feed.current/      <- active, signature-verified bundle (read-only)
/// │   ├── manifest.json
/// │   ├── phishing-domains.txt
/// │   ├── phone-numbers.txt
/// │   ├── apple-support-fakes.txt
/// │   ├── malware-bundle-ids.txt
/// │   ├── sms-templates.json
/// │   ├── romance-scam-patterns.json
/// │   ├── package-scam-templates.json
/// │   └── sources.json
/// ├── feed.tmp/          <- staging dir for in-flight downloads (cleared on each fetch)
/// └── history.log        <- one JSON line per fetch attempt (success or failure)
/// ```
///
/// ## Atomic-swap invariant
///
/// `feed.current/` is the *only* directory consumers (Watch domains,
/// EXPLAIN module, etc.) ever read from. Updates are produced by
/// writing the new bundle into `feed.tmp/`, validating *every* file's
/// SHA-256 plus the manifest signature, then atomically renaming
/// `feed.tmp/` over `feed.current/` via `FileManager.replaceItem(at:withItemAt:)`.
///
/// The rename is a `rename(2)` under the hood on APFS for same-volume
/// moves, so either the operation succeeds and `feed.current/` points
/// at the new bundle, or it fails and `feed.current/` still points at
/// the old one. A power loss or process kill mid-download can never
/// leave a half-applied bundle visible to consumers.
public enum ThreatFeedStorage {

    /// Root for the client's on-disk state. Sits directly under the
    /// shared Vakter support directory so backups, profile migrations,
    /// and the existing legacy-Anchor migration in
    /// ``VakterConstants/supportDirectoryURL`` apply to it
    /// transparently.
    public static var rootDirectoryURL: URL {
        VakterConstants.supportDirectoryURL
            .appendingPathComponent("ThreatFeed", isDirectory: true)
    }

    /// The active, verified bundle directory. Consumers read here.
    /// Promoted atomically from ``stagingDirectoryURL`` on a
    /// successful update.
    public static var currentBundleDirectoryURL: URL {
        rootDirectoryURL
            .appendingPathComponent("feed.current", isDirectory: true)
    }

    /// Staging directory for in-flight downloads. Cleared at the
    /// start of every fetch so a previous failed download cannot
    /// poison the next attempt.
    public static var stagingDirectoryURL: URL {
        rootDirectoryURL
            .appendingPathComponent("feed.tmp", isDirectory: true)
    }

    /// One JSON line per fetch attempt — success or failure. The
    /// Settings → Privacy → Threat Feed pane (ticket #63) reads the
    /// tail of this file to render "Threat feed: just now / 3h ago /
    /// 7d ago".
    public static var historyLogURL: URL {
        rootDirectoryURL.appendingPathComponent("history.log")
    }

    /// Creates the directory tree if it doesn't already exist. Safe
    /// to call repeatedly — `withIntermediateDirectories: true` makes
    /// the operation idempotent.
    public static func ensureDirectoriesExist(
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: rootDirectoryURL,
            withIntermediateDirectories: true
        )
    }
}
