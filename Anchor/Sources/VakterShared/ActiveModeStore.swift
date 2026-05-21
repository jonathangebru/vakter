import Foundation

/// Disk-backed store of the currently-selected `VakterMode`. The Settings
/// UI writes here when the user picks a mode card; the helper reads it
/// at startup so the previously-selected mode survives restarts.
///
/// In-flight mode changes (e.g. from a menubar pick) still go through
/// the XPC `setMode()` call so the helper can react immediately. This
/// store is the persisted side of the same value.
public enum ActiveModeStore {

    private static var url: URL {
        VakterConstants.supportDirectoryURL.appendingPathComponent("active-mode.json")
    }

    public static func load() -> VakterMode {
        guard let data = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(VakterMode.self, from: data) else {
            return .normal
        }
        return m
    }

    public static func save(_ mode: VakterMode) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(mode)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[ActiveModeStore] save failed: %@", error.localizedDescription)
        }
    }
}
