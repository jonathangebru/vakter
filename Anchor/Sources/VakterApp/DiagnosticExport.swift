import Foundation
import VakterShared

/// Builds a user-shareable zip of recent Vakter activity + system
/// state, for "send this to Vakter support" / "attach to insurance
/// claim" / "give the police something useful." Triggered from the
/// Help → "Export diagnostics" menu item.
///
/// **What it includes**:
///   - `events.jsonl`        — last 7 days of state-machine events
///                              (no photos — those live in events/)
///   - `defenses.json`       — current `DefensesProbe` snapshot
///   - `config-redacted.json`— Vakter config minus the iMessage
///                              recipient (privacy: that's the user's
///                              phone number)
///
/// **What it deliberately does NOT include**:
///   - the iMessage recipient handle (PII)
///   - any photos (potentially compromising; users send those
///     separately if needed)
///   - the SHA-256 Apple-ID hash (still PII via correlation)
///
/// Output lands at `~/Desktop/vakter-diagnostic-<ts>.zip` so the
/// user can attach it directly to an email without hunting.
enum DiagnosticExport {

    enum ExportError: Error, LocalizedError {
        case stagingFailed(underlying: Error)
        case zipFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .stagingFailed(let e): return "Couldn't stage files: \(e.localizedDescription)"
            case .zipFailed(let e):     return "Couldn't build zip: \(e.localizedDescription)"
            }
        }
    }

    /// Build the export. Returns the URL of the resulting .zip.
    static func build() throws -> URL {
        let fm = FileManager.default

        // Staging directory in /tmp so we can zip via relative paths.
        let stage = fm.temporaryDirectory
            .appendingPathComponent("vakter-diag-\(UUID().uuidString)",
                                    isDirectory: true)
        do {
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        } catch {
            throw ExportError.stagingFailed(underlying: error)
        }
        defer { try? fm.removeItem(at: stage) }

        // 1. Events — last 7 days.
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let events = EventLogStore.shared.recent(limit: 10_000)
            .filter { $0.timestamp >= cutoff }
        if let data = try? JSONEncoder.pretty.encode(events) {
            try? data.write(to: stage.appendingPathComponent("events.json"),
                            options: .atomic)
        }

        // 2. Defenses snapshot.
        let defenses = DefensesProbe.snapshot()
        if let data = try? JSONEncoder.pretty.encode(defenses) {
            try? data.write(to: stage.appendingPathComponent("defenses.json"),
                            options: .atomic)
        }

        // 3. Redacted config — what mode, what hotkey, what alarm sound,
        //    but NO recipient handle and NO Apple-ID hash.
        let config: [String: String] = [
            "mode":         ActiveModeStore.load().rawValue,
            "alarmSound":   AlarmSoundStore.load().rawValue,
            "hotkey":       HotkeyStore.load().displayLabel,
            "appVersion":   Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            "buildVersion": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
            "exportedAt":   ISO8601DateFormatter().string(from: Date()),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: config,
                                                   options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: stage.appendingPathComponent("config-redacted.json"),
                            options: .atomic)
        }

        // 4. Crash reports — opt-in. macOS's native ReportCrash already
        //    populated these in ~/Library/Logs/DiagnosticReports/; we
        //    just collect and include them if the user has the toggle on.
        if CrashReportPreferences.includeCrashReports {
            let crashes = CrashReportCollector.recent(limit: 10)
            if !crashes.isEmpty {
                let crashDir = stage.appendingPathComponent("crashes",
                                                            isDirectory: true)
                try? fm.createDirectory(at: crashDir,
                                        withIntermediateDirectories: true)
                for report in crashes {
                    let dest = crashDir.appendingPathComponent(report.displayName)
                    try? fm.copyItem(at: report.url, to: dest)
                }
            }
        }

        // 5. Zip into ~/Desktop.
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let outURL = desktop.appendingPathComponent("vakter-diagnostic-\(stamp).zip")

        do {
            let inputs = try fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil)
            try Zipper.zip(inputs: inputs, to: outURL, baseDirectory: stage)
        } catch {
            throw ExportError.zipFailed(underlying: error)
        }

        return outURL
    }
}

private extension JSONEncoder {
    /// Pretty-printer that sorts keys (so multiple exports diff cleanly).
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
