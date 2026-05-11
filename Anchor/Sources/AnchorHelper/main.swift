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

// Wire up observers. Each observer publishes `AnchorSignal` values to the
// state machine. Order doesn't matter — they're independent.
let observers: [AnchorSignalObserver] = [
    LidObserver(),
    PowerObserver(),
    BluetoothObserver(),
    HotkeyObserver(),
    ScreenLockObserver(),
]

for observer in observers {
    observer.start { signal in
        stateMachine.handle(signal: signal)
    }
}

// Stand up the XPC listener so the menubar app can subscribe to snapshots
// and dispatch arm/disarm/setMode commands.
let xpc = XPCService(stateMachine: stateMachine)
xpc.start()

NSLog("[Anchor.helper] ready — running run loop")
RunLoop.main.run()
