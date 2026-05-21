import Foundation

/// Reads Vakter-related crash reports from macOS's native
/// `~/Library/Logs/DiagnosticReports/` folder.
///
/// **Why not PLCrashReporter / Sentry?**
/// We considered both. macOS already runs `ReportCrash` on every process
/// crash, symbolicates against the on-device dSYMs, and writes a complete
/// `.ips` file to `DiagnosticReports/`. Adding PLCrashReporter would
/// duplicate this work, add a 300 KB binary dependency, and force us to
/// stand up a telemetry server — none of which fits Vakter's "no cloud,
/// no telemetry" positioning.
///
/// Instead we collect the native reports on demand and offer the user a
/// one-click "include these in my diagnostic export" toggle. The user
/// still decides what gets sent off-device; we never auto-upload.
///
/// **What we collect**
///   - Files matching `Vakter*` (catches the menubar app, helper LaunchAgent,
///     privileged daemon, the dev-only helper-poke CLI)
///   - `.ips`, `.crash`, and `.diag` extensions
///   - Up to the 10 newest reports (older ones are typically stale)
public enum CrashReportCollector {

    /// One discovered crash report.
    public struct Report: Equatable {
        public let url: URL
        public let process: String
        public let timestamp: Date
        public let sizeBytes: Int

        public var displayName: String { url.lastPathComponent }
    }

    /// `~/Library/Logs/DiagnosticReports/`
    public static var defaultDirectory: URL {
        FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/DiagnosticReports", isDirectory: true)
    }

    /// Scan the directory. Returns up to `limit` reports, newest first.
    /// Safe on machines where the directory doesn't exist or is empty
    /// — both yield an empty array.
    public static func recent(limit: Int = 10, in directory: URL = defaultDirectory) -> [Report] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let allowedExts: Set<String> = ["ips", "crash", "diag"]
        let reports: [Report] = contents.compactMap { url -> Report? in
            guard allowedExts.contains(url.pathExtension.lowercased()) else {
                return nil
            }
            let name = url.lastPathComponent
            guard isVakterProcess(name: name) else { return nil }

            let attrs = try? url.resourceValues(forKeys: [
                .contentModificationDateKey, .fileSizeKey
            ])
            return Report(
                url: url,
                process: processName(from: name),
                timestamp: attrs?.contentModificationDate ?? .distantPast,
                sizeBytes: attrs?.fileSize ?? 0
            )
        }
        .sorted { $0.timestamp > $1.timestamp }

        return Array(reports.prefix(limit))
    }

    /// True if the filename looks like one of Vakter's binaries.
    public static func isVakterProcess(name: String) -> Bool {
        let lc = name.lowercased()
        return lc.hasPrefix("vakter")
            // Defensive: pre-rebrand binaries still on user disks.
            || lc.hasPrefix("anchor")
    }

    /// Extract the process name from a crash filename. macOS uses
    /// `<process>-<timestamp>-<pid>.ips`. We split on the first dash.
    public static func processName(from filename: String) -> String {
        let stem = (filename as NSString).deletingPathExtension
        if let dash = stem.firstIndex(of: "-") {
            return String(stem[..<dash])
        }
        return stem
    }
}
