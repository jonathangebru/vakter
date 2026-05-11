import Foundation

/// Disk-backed JSON store for the user's hotkey binding.
///
/// Lives at `~/Library/Application Support/Anchor/hotkey.json`. Both the
/// menubar app and the helper daemon read from here; the app writes when
/// the user picks a new combo, then asks the helper to reload via XPC.
///
/// We chose a JSON file rather than `UserDefaults`/`CFPreferences`
/// because cross-process settings sync via the latter requires app
/// groups + entitlements that we don't otherwise need. A plain file is
/// trivial and the read/write path is one line each.
public enum HotkeyStore {

    private static var url: URL {
        AnchorConstants.supportDirectoryURL.appendingPathComponent("hotkey.json")
    }

    /// Load the current binding. Returns the default if the file doesn't
    /// exist, is unreadable, or fails to decode.
    public static func load() -> HotkeyBinding {
        guard let data = try? Data(contentsOf: url),
              let binding = try? JSONDecoder().decode(HotkeyBinding.self, from: data) else {
            return .default
        }
        return binding
    }

    /// Persist a new binding atomically. Errors are logged via NSLog —
    /// we don't surface them because there's nothing the user can do.
    public static func save(_ binding: HotkeyBinding) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(binding)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[HotkeyStore] save failed: %@", error.localizedDescription)
        }
    }
}
