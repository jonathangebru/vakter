import Foundation
import Carbon.HIToolbox

/// A user-rebindable global hotkey.
///
/// Stored in Carbon's keyCode + modifier-flags format because that's what
/// `RegisterEventHotKey` consumes directly. The display side (Settings UI)
/// converts to/from this representation via the helpers below.
///
/// Both the menubar app and the helper daemon read/write `HotkeyBinding`
/// values through `HotkeyStore`, which keeps them in sync via a JSON file
/// on disk.
public struct HotkeyBinding: Codable, Sendable, Equatable {

    /// Carbon virtual key code, e.g. `kVK_ANSI_L` (37).
    public let keyCode: UInt16

    /// Carbon modifier mask, e.g. `cmdKey | controlKey | optionKey`.
    public let modifiers: UInt32

    public init(keyCode: UInt16, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The shipped default — ⌘⌃⌥L. Mnemonic: "Lock-aLarm" (extends the
    /// system lock shortcut ⌃⌘Q with an Option modifier).
    public static let `default` = HotkeyBinding(
        keyCode: UInt16(kVK_ANSI_L),
        modifiers: UInt32(cmdKey | controlKey | optionKey)
    )

    /// A binding is "useful" only if it has at least one modifier (so the
    /// user can still type the underlying key normally). UI rejects
    /// modifier-less captures.
    public var hasModifier: Bool {
        modifiers & UInt32(cmdKey | controlKey | optionKey | shiftKey) != 0
    }

    /// True if this combo collides with a macOS reserved system
    /// shortcut that's intercepted *before* Carbon delivers the event
    /// to our `RegisterEventHotKey` handler. Vakter can't see these
    /// presses no matter what — the OS swallows them first.
    ///
    /// We use this to refuse to register the combo and fall back to
    /// the shipped default, so users don't get the "I bound a hotkey
    /// and nothing happens" experience.
    ///
    /// The list is conservative — only combos that are *actually*
    /// captured by macOS system services in default-configured installs.
    public var collidesWithReservedSystemShortcut: Bool {
        let mods = modifiers & UInt32(cmdKey | controlKey | optionKey | shiftKey)
        let cmd: UInt32      = UInt32(cmdKey)
        let ctrl: UInt32     = UInt32(controlKey)
        let opt: UInt32      = UInt32(optionKey)

        // ⌘L — macOS "Lock Screen" (Sonoma+ default). The OS intercepts
        // and locks immediately; our handler never runs.
        if mods == cmd && Int(keyCode) == kVK_ANSI_L { return true }

        // ⌘Space — Spotlight.
        if mods == cmd && Int(keyCode) == kVK_Space { return true }

        // ⌘Tab — app switcher. (Tab keyCode = 48.)
        if mods == cmd && Int(keyCode) == kVK_Tab { return true }

        // ⌘⌥Esc — Force Quit.
        if mods == (cmd | opt) && Int(keyCode) == kVK_Escape { return true }

        // ⌃⌘Q — old "Lock Screen" shortcut, still works on most macOS.
        if mods == (cmd | ctrl) && Int(keyCode) == kVK_ANSI_Q { return true }

        // ⌃Space — input-source switch. Not always bound but commonly is.
        if mods == ctrl && Int(keyCode) == kVK_Space { return true }

        return false
    }

    /// Human-readable label, e.g. "⌘⌃⌥L".
    /// Order matches Apple HIG: ⌃ ⌥ ⇧ ⌘ + key.
    public var displayLabel: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyName
        return s
    }

    /// Best-effort character / symbol for the keyCode. Covers letters,
    /// digits, common punctuation, and the special keys most users would
    /// pick for a global shortcut.
    private var keyName: String {
        switch Int(keyCode) {
        // Letters (Carbon assigns these in a non-obvious order — letter
        // order follows the US QWERTY layout positions).
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"

        // Digits
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"

        // Common punctuation
        case kVK_ANSI_Comma:        return ","
        case kVK_ANSI_Period:       return "."
        case kVK_ANSI_Slash:        return "/"
        case kVK_ANSI_Semicolon:    return ";"
        case kVK_ANSI_Quote:        return "'"
        case kVK_ANSI_LeftBracket:  return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash:    return "\\"
        case kVK_ANSI_Minus:        return "-"
        case kVK_ANSI_Equal:        return "="
        case kVK_ANSI_Grave:        return "`"

        // Special keys
        case kVK_Space:    return "Space"
        case kVK_Return:   return "↩"
        case kVK_Tab:      return "⇥"
        case kVK_Escape:   return "⎋"
        case kVK_Delete:   return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow:  return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow:    return "↑"
        case kVK_DownArrow:  return "↓"
        case kVK_F1:  return "F1"
        case kVK_F2:  return "F2"
        case kVK_F3:  return "F3"
        case kVK_F4:  return "F4"
        case kVK_F5:  return "F5"
        case kVK_F6:  return "F6"
        case kVK_F7:  return "F7"
        case kVK_F8:  return "F8"
        case kVK_F9:  return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"

        default:
            return "?[\(keyCode)]"
        }
    }
}

// MARK: - NSEvent ↔ Carbon modifier-flag conversion

/// Convert AppKit's `NSEvent.modifierFlags` (a `UInt`) to Carbon's UInt32
/// modifier-mask format used by `RegisterEventHotKey`.
///
/// Note: this lives in `VakterShared` so the recorder UI in the app can
/// produce the exact format the helper expects when storing a binding.
public func carbonModifiers(fromCocoa flags: UInt) -> UInt32 {
    var m: UInt32 = 0
    // Match against NSEvent.ModifierFlags raw bit positions (AppKit
    // doesn't expose them directly to VakterShared, but the raw values
    // are stable since 10.0).
    let cmd:     UInt = 1 << 20  // .command
    let shift:   UInt = 1 << 17  // .shift
    let option:  UInt = 1 << 19  // .option
    let control: UInt = 1 << 18  // .control
    if flags & cmd     != 0 { m |= UInt32(cmdKey) }
    if flags & shift   != 0 { m |= UInt32(shiftKey) }
    if flags & option  != 0 { m |= UInt32(optionKey) }
    if flags & control != 0 { m |= UInt32(controlKey) }
    return m
}
