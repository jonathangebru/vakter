import Foundation
import Carbon.HIToolbox
import AnchorShared

/// Watches for the global "arm" hotkey.
///
/// The binding is loaded from `HotkeyStore` at start and can be changed
/// at runtime via `rebind()` (called by the helper's XPC service when
/// the app saves a new binding).
///
/// Uses RegisterEventHotKey (Carbon) rather than CGEventTap so we avoid
/// the Accessibility permission requirement — this matches Apple's
/// preferred approach for app-defined global shortcuts.
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

        // One-time event-handler install — must precede RegisterEventHotKey.
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        var eventHandlerRef: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), HotkeyObserver.handlerUPP,
                            1, &eventType, opaque, &eventHandlerRef)

        registerCurrentBinding()
    }

    /// Re-read the binding from `HotkeyStore` and re-register. Called by
    /// the XPC service after the user picks a new combo in Settings.
    func rebind() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        registerCurrentBinding()
    }

    private func registerCurrentBinding() {
        let binding = HotkeyStore.load()
        let hotKeyID = EventHotKeyID(signature: OSType(0x414E4348), id: 1) // "ANCH"

        let status = RegisterEventHotKey(
            UInt32(binding.keyCode),
            binding.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            NSLog("[HotkeyObserver] RegisterEventHotKey failed: %d (binding=%@)",
                  status, binding.displayLabel)
        } else {
            NSLog("[HotkeyObserver] registered %@", binding.displayLabel)
        }
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
    }
}
