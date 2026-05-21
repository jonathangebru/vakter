import Foundation

/// One rule that auto-arms Vakter when its condition becomes true.
///
/// The #1 retention problem for every anti-theft app is "the user
/// forgot to arm it." Auto-arm rules solve that. A rule is essentially:
///
///   "When <condition>, automatically arm Vakter."
///
/// Rules are user-configured (Settings → Auto-arm) and evaluated
/// continuously by `AutoArmEngine` in the helper. Each rule is
/// independent — multiple may be active at once; any one firing is
/// enough to arm.
///
/// **Why a struct + enum instead of polymorphism?** Easier to
/// serialise (Codable), easier to ship over XPC, easier to render in
/// Settings. The actual `evaluate` logic lives in `AutoArmEngine`
/// alongside the OS-level subscriptions.
public struct AutoArmRule: Codable, Sendable, Identifiable, Equatable {

    public let id: UUID
    public var name: String          // user-facing label, e.g. "Leaving home"
    public var enabled: Bool
    public var trigger: Trigger
    public var cooldownSeconds: TimeInterval   // re-fire suppression

    public enum Trigger: Codable, Sendable, Equatable {

        /// Fire when the Mac leaves the radius around the given
        /// coordinate. CoreLocation geofence.
        case geofenceExit(latitude: Double, longitude: Double, radiusMeters: Double)

        /// Fire when the Mac disconnects from any of the named Wi-Fi
        /// SSIDs (typically the user's home + office networks).
        /// CoreWLAN.
        case wifiDisconnect(ssids: [String])

        /// Fire when the keyboard and trackpad have been idle for at
        /// least `seconds`. CGEventSourceSecondsSinceLastEventType.
        case idleForSeconds(seconds: TimeInterval)

        /// Fire at a calendar boundary — every weekday at HH:MM. Use
        /// for "arm at 6pm so I don't forget when leaving work."
        case dailyAt(hour: Int, minute: Int)
    }

    public init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        trigger: Trigger,
        cooldownSeconds: TimeInterval = 600    // 10 min default
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.trigger = trigger
        self.cooldownSeconds = cooldownSeconds
    }
}

/// Persistent collection of auto-arm rules. JSON-backed.
public enum AutoArmRuleStore {

    private static var url: URL {
        VakterConstants.supportDirectoryURL
            .appendingPathComponent("auto-arm-rules.json")
    }

    public static func load() -> [AutoArmRule] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([AutoArmRule].self, from: data)) ?? []
    }

    @discardableResult
    public static func save(_ rules: [AutoArmRule]) -> Bool {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(rules) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
