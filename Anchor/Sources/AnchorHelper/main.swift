import Foundation
import AnchorShared

// Anchor helper daemon entry point.
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

NSLog("[Anchor.helper] starting (build %@)", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")

// Materialise the state machine. The machine owns the timers (grace, loaner)
// and dispatches all side effects.
let stateMachine = StateMachine()

// HotkeyObserver gets its own reference so the XPC service can ask it to
// rebind when the user picks a new combo in Settings.
let hotkey = HotkeyObserver()

// WakeObserver gets its own reference because it needs to read state
// machine state (to decide whether to delay sleep acknowledgement) AND
// to subscribe to state changes (to acknowledge sleep when user disarms).
let wake = WakeObserver()

// Wire up observers. Each observer publishes `AnchorSignal` values to the
// state machine. Order doesn't matter — they're independent.
let observers: [AnchorSignalObserver] = [
    LidObserver(),
    PowerObserver(),
    BluetoothObserver(),
    hotkey,
    ScreenLockObserver(),
    wake,
]

for observer in observers {
    observer.start { signal in
        stateMachine.handle(signal: signal)
    }
}

// Bidirectional link: WakeObserver needs to read state and subscribe to
// snapshot pushes so it can release a held sleep request the moment the
// user disarms during the delay window.
wake.wireStateMachine(stateMachine)

// Stand up the XPC listener so the menubar app can subscribe to snapshots
// and dispatch arm/disarm/setMode commands.
let xpc = XPCService(stateMachine: stateMachine, hotkey: hotkey)
xpc.start()

NSLog("[Anchor.helper] ready — running run loop")
RunLoop.main.run()
