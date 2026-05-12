import Foundation

/// User-tuneable grace window (seconds between trigger and alarm).
///
/// Stored on disk as JSON; both app and helper read this so the user can
/// change the value in Settings and the helper picks it up at the next
/// grace start (no XPC notification needed — the file read is microseconds).
public struct GraceSettings: Codable, Sendable, Equatable {

    /// Seconds the grace timer runs for. Range 3–30 is enforced in UI.
    public let seconds: TimeInterval

    public init(seconds: TimeInterval) {
        self.seconds = seconds
    }

    public static let `default` = GraceSettings(seconds: 8)

    public static let minSeconds: TimeInterval = 3
    public static let maxSeconds: TimeInterval = 30
}

public enum GraceSettingsStore {

    private static var url: URL {
        AnchorConstants.supportDirectoryURL.appendingPathComponent("grace.json")
    }

    public static func load() -> GraceSettings {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(GraceSettings.self, from: data) else {
            return .default
        }
        // Clamp to sane range — protects against a user editing the JSON.
        let clamped = max(GraceSettings.minSeconds,
                          min(GraceSettings.maxSeconds, s.seconds))
        return GraceSettings(seconds: clamped)
    }

    public static func save(_ settings: GraceSettings) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(settings)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[GraceSettingsStore] save failed: %@", error.localizedDescription)
        }
    }
}
