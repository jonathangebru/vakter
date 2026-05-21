import Foundation

/// Pareto-style security checklist Vakter surfaces from its menubar
/// dropdown. Modelled after the "80/20 security" pattern: a small set
/// of high-impact macOS posture checks, grouped into categories, each
/// with a pass / warn / fail status the user can act on.
///
/// This file is the pure-data model — no shell-out, no SwiftUI. It
/// lives in `VakterShared` so both the menubar app (renders the
/// dropdown) and the helper (could run periodic checks in the
/// background) can consume the same types.
///
/// The actual probes live in `DefensesProbe.runAll()`, which materialises
/// these types by shelling out to `defaults`, `socketfilterfw`,
/// `systemsetup`, `launchctl`, etc.

// MARK: - Categories

/// Top-level grouping for security checks. Maps 1:1 to the columns in
/// the menubar dropdown — `Access Security › Firewall & Sharing ›
/// macOS Updates › Software Updates › System Integrity`.
public enum DefenseCategory: String, CaseIterable, Sendable, Codable {
    case accessSecurity
    case firewallSharing
    case macOSUpdates
    case softwareUpdates
    case systemIntegrity

    public var displayName: String {
        switch self {
        case .accessSecurity:  return "Access Security"
        case .firewallSharing: return "Firewall & Sharing"
        case .macOSUpdates:    return "macOS Updates"
        case .softwareUpdates: return "Software Updates"
        case .systemIntegrity: return "System Integrity"
        }
    }

    /// SF Symbol for the menubar submenu header. Kept generic so the
    /// icons read consistently with macOS's own System Settings panes.
    public var icon: String {
        switch self {
        case .accessSecurity:  return "lock.shield"
        case .firewallSharing: return "network"
        case .macOSUpdates:    return "arrow.triangle.2.circlepath"
        case .softwareUpdates: return "app.badge"
        case .systemIntegrity: return "checkmark.shield"
        }
    }
}

// MARK: - Status

/// Result of a single check. `pass` = green, `warn` = amber (probably
/// fine but worth knowing), `fail` = red (user should act). `unknown`
/// is reserved for probes we couldn't run (e.g. missing binary).
public enum DefenseStatus: String, Sendable, Codable {
    case pass
    case warn
    case fail
    case unknown

    /// SF Symbol surfaced in the menubar dropdown. Mirrors Pareto's
    /// pass/fail iconography so the visual language is familiar.
    public var icon: String {
        switch self {
        case .pass:    return "checkmark.circle.fill"
        case .warn:    return "exclamationmark.triangle.fill"
        case .fail:    return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Roll-up category for an icon's tint. Used by both the menubar
    /// and the Defenses settings tab so colour semantics match.
    public var tone: Tone {
        switch self {
        case .pass:    return .healthy
        case .warn:    return .warning
        case .fail:    return .attention
        case .unknown: return .neutral
        }
    }

    public enum Tone: String, Sendable {
        case healthy, warning, attention, neutral
    }
}

// MARK: - DefenseItem

/// One concrete check. `id` is a stable string used for
/// per-check enable/disable preferences in v1.0 (not wired yet).
public struct DefenseItem: Sendable, Codable, Identifiable, Equatable {

    public let id: String
    public let category: DefenseCategory
    public let title: String
    /// Short one-line description of what good looks like, shown in the
    /// Settings → Defenses tab. Not rendered in the menubar (kept terse
    /// there for scanability — title only).
    public let detail: String
    public let status: DefenseStatus
    /// Open this URL when the user clicks the menubar row. Typically a
    /// `x-apple.systempreferences:` deep-link to the relevant pane.
    public let remediationURLString: String?

    public init(id: String,
                category: DefenseCategory,
                title: String,
                detail: String,
                status: DefenseStatus,
                remediationURLString: String? = nil) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.status = status
        self.remediationURLString = remediationURLString
    }
}

// MARK: - Checklist snapshot

/// What `DefensesProbe.runAll()` returns and what's cached for the
/// menubar's "Last check N min ago" timestamp.
public struct DefenseChecklist: Sendable, Codable, Equatable {
    public let runAt: Date
    public let items: [DefenseItem]

    public init(runAt: Date = Date(), items: [DefenseItem]) {
        self.runAt = runAt
        self.items = items
    }

    /// Items grouped by category in stable presentation order.
    public var byCategory: [(DefenseCategory, [DefenseItem])] {
        DefenseCategory.allCases.map { cat in
            (cat, items.filter { $0.category == cat })
        }.filter { !$0.1.isEmpty }
    }

    /// Worst status in a category (for the parent submenu's icon tint).
    public func worstStatus(in category: DefenseCategory) -> DefenseStatus {
        let cs = items.filter { $0.category == category }.map { $0.status }
        if cs.contains(.fail) { return .fail }
        if cs.contains(.warn) { return .warn }
        if cs.contains(.unknown) { return .unknown }
        return .pass
    }

    /// "49 min ago" style label for the menubar footer.
    public func relativeRunLabel(now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(runAt)
        if interval < 60 { return "just now" }
        if interval < 3600 {
            let m = Int(interval / 60)
            return "\(m) min ago"
        }
        if interval < 86_400 {
            let h = Int(interval / 3600)
            return "\(h) hour\(h == 1 ? "" : "s") ago"
        }
        let d = Int(interval / 86_400)
        return "\(d) day\(d == 1 ? "" : "s") ago"
    }

    /// Roll-up score: percentage of `.pass` items (0–100). Same shape
    /// as the legacy `DefensesAudit.score(_:)` so existing UI keeps
    /// working.
    public var passPercentage: Int {
        guard !items.isEmpty else { return 0 }
        let good = items.filter { $0.status == .pass }.count
        return Int(round(Double(good) / Double(items.count) * 100))
    }
}

// MARK: - Persistence

/// Persists the most-recent checklist to disk so the menubar can show
/// a snapshot immediately on launch (before the first scheduled probe
/// run completes). Same pattern as `AlarmSoundStore` / `HotkeyStore`.
public enum DefenseChecklistStore {

    /// Optional override for unit tests. When set, load/save target
    /// this URL instead of the user-visible production path. This
    /// prevents tests from clobbering the user's real checklist
    /// (which is exactly what bit us in v0.10.0 — a `swift test`
    /// run would leave the menubar dropdown showing 2 fake items
    /// until the next scheduler tick re-ran the probes).
    nonisolated(unsafe) public static var testURL: URL?

    private static var url: URL {
        if let override = testURL { return override }
        return VakterConstants.supportDirectoryURL
            .appendingPathComponent("defenses-checklist.json")
    }

    public static func load() -> DefenseChecklist? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.iso.decode(DefenseChecklist.self, from: data)
    }

    public static func save(_ checklist: DefenseChecklist) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.iso.encode(checklist) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// Date encoding helpers — kept here rather than in Foundation extensions
// so they're scoped to this file's needs and don't leak globally.
private extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
private extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
