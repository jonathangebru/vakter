import Foundation
import Carbon.HIToolbox
import AnchorShared

/// Watches for the global "arm" hotkey (default `⌘⌃⌥L`).
///
/// Uses RegisterEventHotKey (Carbon) rather than CGEventTap so we avoid
/// the Accessibility permission requirement — this matches Apple's
/// preferred approach for app-defined global shortcuts.
///
/// TODO(week-3):
///   - Read the user's customised key combo from Settings instead of
///     hardcoded ⌘⌃⌥L
///   - When hotkey fires, also invoke the screen-lock side effect
///     (CGSession lock or `pmset displaysleepnow`)
final class HotkeyObserver: AnchorSignalObserver {

    private var hotKeyRef: EventHotKeyRef?
    private var emit: ((AnchorSignal) -> Void)?

    // Static handler trampoline → instance handler.
    private static let handlerUPP: EventHandlerUPP = { (_, eventRef, userData) -> OSStatus in
        guard let userData = userData else { return noErr }
        let me = Unmanaged<HotkeyObserver>.fromOpaque(userData).takeUnretainedValue()
        me.emit?(.hotkeyArm)
        return noErr
    }

    func start(_ emit: @escaping (AnchorSignal) -> Void) {
        self.emit = emit

        let hotKeyID = EventHotKeyID(signature: OSType(0x414E4348), id: 1) // "ANCH"
        let keyCode: UInt32 = UInt32(kVK_ANSI_L)
        let modifiers: UInt32 = UInt32(cmdKey | controlKey | optionKey)

        let opaque = Unmanaged.passUnretained(self).toOpaque()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        var eventHandlerRef: EventHandlerRef?

        InstallEventHandler(GetApplicationEventTarget(), HotkeyObserver.handlerUPP,
                            1, &eventType, opaque, &eventHandlerRef)

        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(),
                                         0, &hotKeyRef)
        if status != noErr {
            NSLog("[HotkeyObserver] RegisterEventHotKey failed: %d", status)
        } else {
            NSLog("[HotkeyObserver] registered default ⌘⌃⌥L")
        }
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
    }
}
