import Foundation
import Carbon.HIToolbox
import VakterShared

/// Watches for the global "arm" hotkey.
///
/// The binding is loaded from `HotkeyStore` at start and can be changed
/// at runtime via `rebind()` (called by the helper's XPC service when
/// the app saves a new binding).
///
/// Uses RegisterEventHotKey (Carbon) rather than CGEventTap so we avoid
/// the Accessibility permission requirement — this matches Apple's
/// preferred approach for app-defined global shortcuts.
///
/// **Critical**: Carbon `kEventClassKeyboard` events are only dispatched
/// when the host process is running an NSApplication run loop. A bare
/// `RunLoop.main.run()` (Foundation runloop) will NOT pump them, so the
/// handler trampoline is never called. The Vakter helper's `main.swift`
/// explicitly calls `NSApp.run()` for this reason. If you ever observe
/// "`registered ⌘⌃⌥L`" in logs but key presses do nothing, double-check
/// the host's runloop choice before suspecting anything here.
final class HotkeyObserver: VakterSignalObserver {

    private var hotKeyRef: EventHotKeyRef?
    private var emit: ((VakterSignal) -> Void)?
    private var heartbeatTimer: DispatchSourceTimer?

    // Static handler trampoline → instance handler.
    private static let handlerUPP: EventHandlerUPP = { (_, eventRef, userData) -> OSStatus in
        guard let userData = userData else { return noErr }
        let me = Unmanaged<HotkeyObserver>.fromOpaque(userData).takeUnretainedValue()
        NSLog("[HotkeyObserver] handler fired — emit .hotkeyArm")
        me.emit?(.hotkeyArm)
        return noErr
    }

    func start(_ emit: @escaping (VakterSignal) -> Void) {
        self.emit = emit

        // One-time event-handler install — must precede RegisterEventHotKey.
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        var eventHandlerRef: EventHandlerRef?
        let installStatus = InstallEventHandler(GetApplicationEventTarget(),
                                                HotkeyObserver.handlerUPP,
                                                1, &eventType, opaque,
                                                &eventHandlerRef)
        if installStatus != noErr {
            NSLog("[HotkeyObserver] InstallEventHandler FAILED: %d", installStatus)
        } else {
            NSLog("[HotkeyObserver] InstallEventHandler ok")
        }

        registerCurrentBinding()
        startHeartbeat()
    }

    /// Permanent diagnostic. Every 30 s, emit a single line to Console.app
    /// confirming the observer is alive and noting the currently-registered
    /// binding. If a user reports "hotkey doesn't work", the first thing
    /// we ask them to do is `log stream --predicate 'process ==
    /// "VakterHelper"' --info | grep HotkeyObserver` — if heartbeats are
    /// present but no "handler fired" lines on key press, the bug is in
    /// the runloop / Carbon dispatch, not the registration.
    private func startHeartbeat() {
        heartbeatTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .global())
        t.schedule(deadline: .now() + 30, repeating: 30)
        t.setEventHandler {
            let b = HotkeyStore.load()
            NSLog("[HotkeyObserver] alive — binding=%@", b.displayLabel)
        }
        t.resume()
        heartbeatTimer = t
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
        // `HotkeyStore.load()` already substitutes the default if the
        // user's saved combo collides with a macOS reserved shortcut.
        // We don't need to re-check here, but we DO emit a louder log
        // line so a Console.app grep tells the whole story.
        let binding = HotkeyStore.load()
        if binding.collidesWithReservedSystemShortcut {
            // Defence-in-depth — should never happen because load()
            // healed the file, but if it does, bail before calling
            // RegisterEventHotKey (which would succeed but never fire).
            NSLog("[HotkeyObserver] REFUSING to register %@ — macOS reserves this combo and will intercept it. Falling back to default %@.",
                  binding.displayLabel,
                  HotkeyBinding.default.displayLabel)
            return
        }

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
        heartbeatTimer?.cancel()
    }
}
