import Foundation

/// Shared identifiers and paths used by both the menubar app and the helper.
public enum AnchorConstants {
    /// Bundle ID for the user-facing menubar app.
    public static let appBundleID = "app.anchor.mac"

    /// Bundle ID for the background LaunchAgent helper.
    public static let helperBundleID = "app.anchor.mac.helper"

    /// Mach service name used for XPC between the app and the helper.
    public static let xpcMachServiceName = "app.anchor.mac.helper.xpc"

    /// Bundle ID for the privileged daemon (runs as root).
    public static let privilegedDaemonBundleID = "app.anchor.mac.privileged-helper"

    /// Mach service exposed by the privileged daemon (root). Used by the
    /// user-level helper to ask the daemon to toggle pmset disablesleep.
    public static let privilegedDaemonMachServiceName = "app.anchor.mac.privileged-helper.xpc"

    /// User-data root. Lives under `~/Library/Application Support/Anchor`.
    public static var supportDirectoryURL: URL {
        let library = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return library.appendingPathComponent("Anchor", isDirectory: true)
    }

    /// Directory where alarm-event photo bursts are written.
    public static var eventsDirectoryURL: URL {
        supportDirectoryURL.appendingPathComponent("events", isDirectory: true)
    }

    /// Path to the persistent event log (JSON-lines file).
    public static var eventLogURL: URL {
        supportDirectoryURL.appendingPathComponent("events.jsonl")
    }
}
