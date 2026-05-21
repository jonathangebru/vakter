import Foundation

/// How Vakter's menubar icon presents itself. A power-user feature —
/// most users want the lighthouse silhouette so they can disarm with
/// a click, but a small fraction (people travelling through high-risk
/// areas, journalists, anyone with plausible-deniability needs) wants
/// the icon NOT to advertise Vakter's presence.
///
/// **Trade-offs**:
///   - `.lighthouse`: full Vakter brand mark with breathing animation
///     and state-tinted lantern dot. Most discoverable. The default.
///   - `.fakeBattery`: shows a generic `battery.75` SF Symbol. To the
///     casual observer (the thief), it looks like the system battery
///     widget. Clicking it still opens Vakter's menu — but you have
///     to *know* to click it.
///   - `.hidden`: no menubar icon at all. The only way to interact is
///     the global hotkey + the AppleScript / Shortcuts interface.
///     Maximum stealth, zero discoverability — Vakter forces an
///     onboarding step that confirms you have a working hotkey
///     before allowing this.
public enum MenubarAppearance: String, Codable, Sendable, CaseIterable, Equatable {
    case lighthouse
    case fakeBattery
    case hidden

    public var displayName: String {
        switch self {
        case .lighthouse:  return "Lighthouse (default)"
        case .fakeBattery: return "Fake battery icon"
        case .hidden:      return "Hidden — hotkey only"
        }
    }

    public var blurb: String {
        switch self {
        case .lighthouse:
            return "Vakter's lighthouse silhouette with state-tinted lantern. Click to open the menu."
        case .fakeBattery:
            return "Looks like a system battery glyph. Plausible deniability — click still opens the menu."
        case .hidden:
            return "No menubar icon. Requires a working hotkey to arm and a separate app launch to disarm."
        }
    }
}

public enum MenubarAppearanceStore {

    private static var url: URL {
        VakterConstants.supportDirectoryURL
            .appendingPathComponent("menubar-appearance.json")
    }

    public static func load() -> MenubarAppearance {
        guard let data = try? Data(contentsOf: url),
              let appearance = try? JSONDecoder().decode(MenubarAppearance.self, from: data)
        else { return .lighthouse }
        return appearance
    }

    public static func save(_ appearance: MenubarAppearance) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(appearance) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
