import Foundation

/// Shared identifiers and paths used by both the menubar app and the helper.
public enum AnchorConstants {
    /// Bundle ID for the user-facing menubar app.
    public static let appBundleID = "app.anchor.mac"

    /// Bundle ID for the background LaunchAgent helper.
    public static let helperBundleID = "app.anchor.mac.helper"

    /// Mach service name used for XPC between the app and the helper.
    public static let xpcMachServiceName = "app.anchor.mac.helper.xpc"

    /// Default global hotkey for arming, expressed as a human-readable label.
    /// The actual key combo lives in `Settings` (user-customisable).
    public static let defaultHotkeyLabel = "⌘⌃⌥L"

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
