import Foundation
import AppKit
import VakterShared

// Vakter helper daemon entry point.
//
// Responsibilities:
//   - Owns the authoritative state machine
//   - Runs all signal observers (lid, power, Bluetooth, hotkey, ...)
//   - Drives the audio controller during ALARM
//   - Captures the photo burst during ALARM
//   - Persists events to the event log
//   - Exposes XPC for the menubar app to subscribe + control
//
// This is a background-only process. It is installed via SMAppService from
// the menubar app's first-run flow and survives app restarts. See
// `openspec/changes/bootstrap-anchor/design.md` § Architecture.

NSLog("[Vakter.helper] starting (build %@)", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")

// Materialise the state machine. The machine owns the timers (grace, loaner)
// and dispatches all side effects.
let stateMachine = StateMachine()

// HotkeyObserver gets its own reference so the XPC service can ask it to
// rebind when the user picks a new combo in Settings.
let hotkey = HotkeyObserver()

// BluetoothObserver gets its own reference so the XPC service can drive
// the pairing-UI scan + add/remove from trusted peers.
let bluetooth = BluetoothObserver()

// WakeObserver gets its own reference because it needs to read state
// machine state (to decide whether to delay sleep acknowledgement) AND
// to subscribe to state changes (to acknowledge sleep when user disarms).
let wake = WakeObserver()

// Arm-gated watchers — they only run their probe loop while armed.
// Created here so we can register them as both signal sources AND
// arm-gated observers below.
let findMyWatcher  = FindMyTokenWatcher.make()
let appleIDWatcher = AppleIDChangeWatcher.make()

// Wire up observers. Each observer publishes `VakterSignal` values to the
// state machine. Order doesn't matter — they're independent.
let observers: [VakterSignalObserver] = [
    LidObserver(),
    PowerObserver(),
    bluetooth,
    hotkey,
    ScreenLockObserver(),
    wake,
    findMyWatcher,
    appleIDWatcher,
]

for observer in observers {
    observer.start { signal in
        stateMachine.handle(signal: signal)
    }
}

// Register the two arm-gated watchers so the state machine pauses /
// resumes their polling loops on each .armed transition. Polling
// `nvram` and `defaults` every 30 s while unarmed would waste battery
// for no benefit — these watchers don't matter unless Vakter is armed.
stateMachine.armGatedObservers = [findMyWatcher, appleIDWatcher]

// Bidirectional link: WakeObserver needs to read state and subscribe to
// snapshot pushes so it can release a held sleep request the moment the
// user disarms during the delay window.
wake.wireStateMachine(stateMachine)

// Stand up the XPC listener so the menubar app can subscribe to snapshots
// and dispatch arm/disarm/setMode commands.
let xpc = XPCService(stateMachine: stateMachine, hotkey: hotkey, bluetooth: bluetooth)
xpc.start()

// v1.4: auto-arm rules engine. Reads user-configured rules from disk
// (geofence / Wi-Fi / idle / daily-at) and arms Vakter automatically
// when any rule fires. No-op if the user has no rules configured.
// Lives on the MainActor because CLLocationManager + CoreWLAN require
// a runloop, which NSApp.run() provides above.
let autoArmEngine = Task { @MainActor in
    let engine = AutoArmEngine(stateMachine: stateMachine)
    engine.reload()
    return engine
}
// Reference retained to keep the engine + its CLLocationManager alive
// for the lifetime of the helper.
_ = autoArmEngine

NSLog("[Vakter.helper] ready — running NSApp run loop")

// CRITICAL: we use `NSApplication.run()` here instead of
// `RunLoop.main.run()`. The former pumps both Foundation runloop sources
// (used by NSXPCListener, CBCentralManager, IOKit notifications, etc.)
// AND Carbon HIToolbox `kEventClassKeyboard` events — the latter is
// what makes `HotkeyObserver`'s `RegisterEventHotKey` callback fire.
// Pre-v0.9 the helper used `RunLoop.main.run()` and the arm-hotkey
// silently broke: registration succeeded but the handler never ran.
//
// `.prohibited` activation policy keeps this a fully background process
// (no Dock icon, no menubar slot, no window list) — same UX as before,
// just with a working AppKit runloop underneath.
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
