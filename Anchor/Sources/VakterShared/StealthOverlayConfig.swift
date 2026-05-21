import Foundation

/// User-configurable text shown by the stealth lock-screen overlay when
/// Vakter enters the `.alarm` state.
///
/// Vakter's signature deterrence is loud, but loudness alone doesn't
/// communicate *what to do next*. A thief sees the normal macOS lock
/// screen and reads "this Mac is locked but otherwise unremarkable."
/// A Good Samaritan who finds the Mac sees the same. The stealth
/// overlay changes both audiences' read in a single moment: huge
/// "STOLEN MAC" headline + the owner's return-contact info, rendered
/// above the lock screen at `NSWindow.Level.screenSaver`. This is the
/// "car alarm flashing light" — a visible deterrent that complements
/// the audible one.
///
/// Persistence: a single JSON file at
///   `~/Library/Application Support/Vakter/stealth-overlay.json`
/// Same on-disk pattern as `HotkeyStore`, `MenubarAppearanceStore`,
/// `GraceSettingsStore`, etc. We chose a flat file rather than
/// `UserDefaults` because the helper does not need to read this — it
/// is purely an App-process concern (the overlay window lives in the
/// menubar app). Keeping it on disk also means a fresh install with
/// the support directory restored from backup gets the user's owner
/// message back without re-entering it.
///
/// Default values: both fields are empty. When empty, the overlay
/// falls back to a baked-in default message so the user is never
/// in a state where the alarm shows the screen with NOTHING on it.
/// See `displayMessage` / `displayCallback` for the resolved values.
public struct StealthOverlayConfig: Codable, Sendable, Equatable {

    /// Maximum number of characters we persist in the multi-line
    /// "owner name + return info" field. The overlay can render a
    /// reasonable amount of text without wrapping into illegibility;
    /// past ~200 chars we clip silently rather than reject the save
    /// (rejecting feels arbitrary, clipping is forgiving).
    public static let maxMessageLength = 200

    /// Maximum length of the callback-number field. Phone numbers
    /// internationally top out around 17 chars (E.164 plus dashes);
    /// we round up generously so users can include country names
    /// or short labels like "+1 555-123-4567 (mom)" without losing
    /// data.
    public static let maxCallbackLength = 60

    /// Free-form owner / return-info string. Examples:
    ///   "If found, please return to Jane Doe."
    ///   "Reward offered. This Mac is being tracked."
    ///   "Owner: jane@example.com — please contact."
    /// Multi-line is allowed; the overlay renders with line wrapping.
    public var message: String

    /// Phone number (or other contact string — we don't enforce format
    /// strictly because users may want to write "Telegram: @owner" etc).
    /// When set to something that *looks* like a phone number, the
    /// overlay renders it tappable as a `tel:` URL so a Good Samaritan
    /// can call directly from any nearby iPhone via Continuity.
    public var callbackNumber: String

    public init(message: String = "", callbackNumber: String = "") {
        // Clip on construction so neither persistence nor the overlay
        // can be handed a runaway string. This handles the case where
        // the on-disk JSON was hand-edited beyond the cap; we still
        // load it, just bounded.
        self.message = String(message.prefix(Self.maxMessageLength))
        self.callbackNumber = String(callbackNumber.prefix(Self.maxCallbackLength))
    }

    /// Empty default — both fields blank. The overlay code uses
    /// `displayMessage` / `displayCallback` to substitute a sensible
    /// fallback in this case so the overlay never renders a blank
    /// screen even if the user never opened Settings.
    public static let `default` = StealthOverlayConfig()

    /// True when no user-supplied content is set. The overlay code
    /// checks this rather than introspecting both strings inline.
    public var isEmpty: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && callbackNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The message text the overlay should actually render. Returns
    /// the user's string when non-empty, otherwise a baked-in fallback
    /// that communicates the same idea without naming an owner.
    ///
    /// We resolve the fallback inside the model so every caller —
    /// alarm path, preview button, future companion-app remote-display —
    /// sees the same string. One source of truth.
    public var displayMessage: String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return "This Mac is being recovered.\nContact local authorities."
    }

    /// The callback contact the overlay should render, or `nil` if
    /// the user has not configured one (the overlay omits the call
    /// affordance in that case).
    public var displayCallback: String? {
        let trimmed = callbackNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Phone-number heuristic

    /// Loose "does this look like a phone number" check. Used by the
    /// overlay view to decide whether to render the callback string
    /// as a tappable `tel:` link. We intentionally accept a wide
    /// variety of formats — international codes, dashes, parentheses,
    /// dots, spaces — because users will type whatever feels natural
    /// to them. The check is *for tap affordance only*; the user's
    /// raw string is what we render visually.
    ///
    /// Rules:
    ///   - At least 7 digits total (the minimum for a real phone)
    ///   - Optional leading "+"
    ///   - Allowed separators: space, dash, dot, parens
    ///   - No letters (so "Telegram: @owner" is correctly *not* a phone)
    public var looksLikePhoneNumber: Bool {
        guard let trimmed = displayCallback else { return false }
        let allowed = Set("+0123456789 -().\u{00A0}")
        for ch in trimmed where !allowed.contains(ch) {
            return false
        }
        let digitCount = trimmed.filter { $0.isNumber }.count
        return digitCount >= 7
    }

    /// `tel:` URL form of the callback, suitable for `NSWorkspace.open`
    /// or a SwiftUI `Link`. Strips formatting characters because the
    /// dialer expects digits + leading "+".
    public var telURL: URL? {
        guard looksLikePhoneNumber, let trimmed = displayCallback else { return nil }
        let allowedInTel = Set("+0123456789")
        let stripped = String(trimmed.filter { allowedInTel.contains($0) })
        guard !stripped.isEmpty else { return nil }
        return URL(string: "tel:\(stripped)")
    }
}

// MARK: - Persistence

/// Disk-backed JSON store for `StealthOverlayConfig`.
///
/// Lives at `~/Library/Application Support/Vakter/stealth-overlay.json`.
/// The menubar app reads on launch and writes when the user edits the
/// "If found, please contact" card in Settings → General. The helper
/// does NOT read this file — the overlay is rendered by the app, not
/// the helper.
///
/// Errors are logged but never thrown out — the same defensive posture
/// as `HotkeyStore`. If the file is missing or unreadable we hand back
/// `.default` (empty fields, which resolves to the baked-in fallback
/// inside the model). Users may never have opened Settings and the
/// alarm should still produce a screen that says *something* useful.
public enum StealthOverlayConfigStore {

    private static var url: URL {
        VakterConstants.supportDirectoryURL.appendingPathComponent("stealth-overlay.json")
    }

    /// Load the persisted config, or `.default` if the file is missing
    /// or corrupt. Always returns a value — never nil — because the
    /// alarm code path needs a concrete config to render.
    public static func load() -> StealthOverlayConfig {
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(StealthOverlayConfig.self, from: data) else {
            return .default
        }
        return cfg
    }

    /// Persist atomically. Truncation is enforced by `init` so even if
    /// callers hand in oversized strings the on-disk JSON stays bounded.
    public static func save(_ config: StealthOverlayConfig) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(config)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[StealthOverlayConfigStore] save failed: %@", error.localizedDescription)
        }
    }

    /// Erase the on-disk file. Used by the Settings "reset to default"
    /// button (if we add one) and by the unit-test cleanup path so
    /// tests don't bleed state between runs.
    public static func reset() {
        try? FileManager.default.removeItem(at: url)
    }
}
