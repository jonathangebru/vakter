import Foundation
import IOKit
import IOKit.pwr_mgt
import AnchorShared

/// Observes system sleep/wake transitions and emits `.systemWake` whenever
/// the kernel sends `kIOMessageSystemHasPoweredOn`.
///
/// Why this exists, since we already hold sleep-prevention assertions:
/// On Apple Silicon, when the lid is closed on battery without an external
/// display attached, the firmware-managed clamshell sleep path frequently
/// overrides `kIOPMAssertPreventSystemSleep` and even
/// `kIOPMAssertPreventUserIdleDisplaySleep`. The system sleeps regardless,
/// the helper's grace-period `DispatchSource` timer is suspended, and the
/// alarm never fires through the closed lid.
///
/// This observer is the fallback. The state machine consumes `.systemWake`
/// while in `.armed` or `.grace` and transitions straight to `.alarm`.
/// Net effect: the moment a thief opens the lid (or wakes the Mac in any
/// way), the alarm fires. Not as good as catching them mid-bag, but it
/// closes the silent-theft hole.
///
/// Uses `IORegisterForSystemPower` — the canonical sleep/wake notification
/// API that works correctly inside background daemons.
final class WakeObserver: AnchorSignalObserver, @unchecked Sendable {

    private var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var emit: ((AnchorSignal) -> Void)?

    // IOMessage constants from <IOKit/IOMessage.h>. The Swift-bridged
    // versions of these aren't exposed via plain `import IOKit`, so we
    // use the raw values. Stable since Mac OS X 10.0.
    private static let kIOMessageCanSystemSleep:    UInt32 = 0xE0000270
    private static let kIOMessageSystemWillSleep:   UInt32 = 0xE0000280
    private static let kIOMessageSystemHasPoweredOn: UInt32 = 0xE0000300

    private static let callback: IOServiceInterestCallback = { refcon, _, msgType, msgArg in
        guard let refcon = refcon else { return }
        let me = Unmanaged<WakeObserver>.fromOpaque(refcon).takeUnretainedValue()

        switch msgType {
        case kIOMessageSystemHasPoweredOn:
            NSLog("[WakeObserver] kIOMessageSystemHasPoweredOn — emitting .systemWake")
            me.emit?(.systemWake)

        case kIOMessageCanSystemSleep:
            // The system is *asking* if it can sleep. We MUST respond, or
            // the system stalls for 30 s waiting for us. Always allow —
            // we tried to prevent sleep via SleepGuard, and if it's still
            // asking us, we can't override anyway. The wake handler will
            // catch the resume.
            let arg = msgArg.map { Int(bitPattern: $0) } ?? 0
            IOAllowPowerChange(me.rootPort, arg)

        case kIOMessageSystemWillSleep:
            // System has decided to sleep. Acknowledge so the kernel can
            // proceed. Without this, sleep stalls.
            NSLog("[WakeObserver] kIOMessageSystemWillSleep — sleep imminent")
            let arg = msgArg.map { Int(bitPattern: $0) } ?? 0
            IOAllowPowerChange(me.rootPort, arg)

        default:
            break
        }
    }

    func start(_ emit: @escaping (AnchorSignal) -> Void) {
        self.emit = emit

        let opaque = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(opaque, &notifyPort, WakeObserver.callback, &notifier)

        guard rootPort != 0, let notifyPort = notifyPort else {
            NSLog("[WakeObserver] FAIL: IORegisterForSystemPower returned 0")
            return
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue(),
            .defaultMode
        )

        NSLog("[WakeObserver] watching system sleep/wake transitions")
    }

    deinit {
        if notifier != 0 { IODeregisterForSystemPower(&notifier) }
        if let notifyPort = notifyPort { IONotificationPortDestroy(notifyPort) }
        if rootPort != 0 { IOServiceClose(rootPort) }
    }
}
