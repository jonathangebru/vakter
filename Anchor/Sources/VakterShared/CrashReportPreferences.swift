import Foundation

/// User preference for whether macOS-native crash reports get bundled
/// into the `DiagnosticExport.zip` the user shares with support.
///
/// **Default: off.** Crash reports contain process memory layout, system
/// version, and full backtraces — useful for debugging but more revealing
/// than the redacted config we ship by default. Users opt in deliberately
/// from Settings → Privacy.
///
/// Pinned to UserDefaults under a stable key so the toggle persists
/// across launches.
public enum CrashReportPreferences {

    private static let key = "vakter.diag.includeCrashReports"

    public static var includeCrashReports: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
