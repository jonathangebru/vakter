import Foundation

/// Shared identifiers and paths used by both the menubar app and the helper.
///
/// NOTE: The type name retains the `Anchor` prefix because all Swift code
/// in this codebase already imports `VakterShared` and references
/// `VakterConstants`. Internal class names are deferred for a future
/// pure-refactor commit; everything the user perceives — bundle name,
/// bundle IDs, mach service names, UI copy, NSLog tags — already says
/// "Vakter" (the Norwegian word for a night-watchman: calm 99% of the
/// time, fierce the moment it has to be).
public enum VakterConstants {
    /// Bundle ID for the user-facing menubar app.
    public static let appBundleID = "app.vakter.mac"

    /// Bundle ID for the background LaunchAgent helper.
    public static let helperBundleID = "app.vakter.mac.helper"

    /// Mach service name used for XPC between the app and the helper.
    public static let xpcMachServiceName = "app.vakter.mac.helper.xpc"

    /// Bundle ID for the privileged daemon (runs as root).
    public static let privilegedDaemonBundleID = "app.vakter.mac.privileged-helper"

    /// Mach service exposed by the privileged daemon (root). Used by the
    /// user-level helper to ask the daemon to toggle pmset disablesleep.
    public static let privilegedDaemonMachServiceName = "app.vakter.mac.privileged-helper.xpc"

    /// User-data root. Lives under `~/Library/Application Support/Vakter`.
    /// On first access we migrate any pre-existing `Anchor/` directory
    /// (from the Anchor-era beta) into `Vakter/` so users don't lose
    /// their event log, hotkey binding, or grace setting.
    public static var supportDirectoryURL: URL {
        let library = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let target = library.appendingPathComponent("Vakter", isDirectory: true)
        migrateLegacyAnchorDirectoryIfNeeded(toTarget: target, library: library)
        return target
    }

    /// Directory where alarm-event photo bursts are written.
    public static var eventsDirectoryURL: URL {
        supportDirectoryURL.appendingPathComponent("events", isDirectory: true)
    }

    /// Path to the persistent event log (JSON-lines file).
    public static var eventLogURL: URL {
        supportDirectoryURL.appendingPathComponent("events.jsonl")
    }

    // MARK: - Legacy Anchor → Vakter migration

    /// One-shot migration. If the user has data at the legacy
    /// `~/Library/Application Support/Anchor/` path (from the Anchor-era
    /// beta), move it under `Vakter/`. Idempotent.
    private static func migrateLegacyAnchorDirectoryIfNeeded(toTarget target: URL, library: URL) {
        let fm = FileManager.default
        let legacy = library.appendingPathComponent("Anchor", isDirectory: true)

        // Already migrated, or nothing to migrate.
        guard fm.fileExists(atPath: legacy.path) else { return }
        if fm.fileExists(atPath: target.path) {
            // Target exists — assume migration happened. Leave both in
            // place rather than risk merging conflicting state.
            return
        }
        do {
            try fm.moveItem(at: legacy, to: target)
            NSLog("[Vakter] migrated legacy Anchor support dir → Vakter/")
        } catch {
            NSLog("[Vakter] legacy support dir migration failed: %@", error.localizedDescription)
        }
    }
}
