import Foundation
import IOKit
import IOKit.pwr_mgt
import VakterShared

/// Observes system sleep/wake transitions, fires `.systemWake` on resume,
/// AND **delays acknowledging `kIOMessageSystemWillSleep`** while armed —
/// the only reliable way to keep an Apple Silicon Mac awake long enough
/// for the alarm to be audible during lid-close.
///
/// Why the delayed acknowledgement matters:
/// IOPM assertions (`kIOPMAssertPreventSystemSleep`, …) are advisory and
/// the firmware overrides them on M-series Macs for clamshell close on
/// battery. The message-handshake path is stronger — the kernel sends
/// `kIOMessageSystemWillSleep`, then **waits up to 30 seconds** for every
/// registered listener to call `IOAllowPowerChange`. If we hold off, the
/// Mac stays awake. We use that window to play the full alarm at full
/// volume; once the user disarms (or 25 s passes), we acknowledge and
/// let the Mac sleep.
///
/// Coordination with the rest of the system:
///   - `WakeObserver` keeps a weak ref to the `StateMachine`. On a will-
///     sleep notification it asks the state machine for the current state.
///     If armed/grace/alarm, hold off; otherwise acknowledge.
///   - Subscribes to `StateMachine.addObserver` so that whenever state
///     goes back to `.unarmed` (e.g. user authenticated and disarmed),
///     we acknowledge the held sleep request immediately so the Mac can
///     actually sleep.
final class WakeObserver: VakterSignalObserver, @unchecked Sendable {

    // IOMessage constants from <IOKit/IOMessage.h>. Stable since 10.0.
    private static let kIOMessageCanSystemSleep:     UInt32 = 0xE0000270
    private static let kIOMessageSystemWillSleep:    UInt32 = 0xE0000280
    private static let kIOMessageSystemHasPoweredOn: UInt32 = 0xE0000300

    /// Maximum delay before we MUST acknowledge a sleep request. The
    /// kernel forces sleep after ~30 s — we leave 5 s of headroom.
    private static let maxDelaySeconds: TimeInterval = 25.0

    private var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var emit: ((VakterSignal) -> Void)?

    /// Pending sleep state (only set while we're holding off an ack).
    private var pendingSleepArg: Int = 0
    private var pendingAcknowledgeTimer: DispatchSourceTimer?
    private let lock = NSLock()

    /// Set after construction so the observer can ask "are we armed?"
    weak var stateMachine: StateMachine?

    func start(_ emit: @escaping (VakterSignal) -> Void) {
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

    /// Hook up the bidirectional link with the state machine.
    /// Called by `main.swift` after both objects exist.
    func wireStateMachine(_ sm: StateMachine) {
        self.stateMachine = sm
        // Subscribe to snapshots — whenever we drop back to .unarmed
        // (e.g. user authenticated and disarmed during our delay), let
        // the Mac sleep immediately.
        sm.addObserver { [weak self] snapshot in
            if snapshot.state == .unarmed {
                self?.acknowledgePendingSleep(reason: "state → unarmed")
            }
        }
    }

    /// Acknowledge the held sleep request and cancel the timer. Safe to
    /// call repeatedly — no-op if no sleep is pending.
    private func acknowledgePendingSleep(reason: String) {
        lock.lock()
        let arg = pendingSleepArg
        pendingSleepArg = 0
        pendingAcknowledgeTimer?.cancel()
        pendingAcknowledgeTimer = nil
        let port = rootPort
        lock.unlock()
        guard arg != 0, port != 0 else { return }
        IOAllowPowerChange(port, arg)
        NSLog("[WakeObserver] acknowledged pending sleep (%@) — Mac may now sleep", reason)
    }

    private static let callback: IOServiceInterestCallback = { refcon, _, msgType, msgArg in
        guard let refcon = refcon else { return }
        let me = Unmanaged<WakeObserver>.fromOpaque(refcon).takeUnretainedValue()

        switch msgType {
        case WakeObserver.kIOMessageSystemHasPoweredOn:
            NSLog("[WakeObserver] kIOMessageSystemHasPoweredOn — emitting .systemWake")
            me.emit?(.systemWake)

        case WakeObserver.kIOMessageCanSystemSleep:
            // System asking "can I sleep?" — used for idle sleep path.
            // We don't generally need to block here (lid-close goes
            // straight to WillSleep). Always allow.
            let arg = msgArg.map { Int(bitPattern: $0) } ?? 0
            IOAllowPowerChange(me.rootPort, arg)

        case WakeObserver.kIOMessageSystemWillSleep:
            // CRITICAL PATH for lid-close-on-battery.
            // If we're armed/grace/alarm, hold off acknowledging.
            // The kernel waits up to 30 s for us — we use that to keep
            // the Mac awake so the alarm can play audibly through the
            // closed lid.
            let arg = msgArg.map { Int(bitPattern: $0) } ?? 0
            let state = me.stateMachine?.snapshot().state ?? .unarmed

            if state == .unarmed {
                // Nothing to protect. Acknowledge immediately.
                IOAllowPowerChange(me.rootPort, arg)
                NSLog("[WakeObserver] WillSleep while unarmed → acknowledged immediately")
                return
            }

            NSLog("[WakeObserver] WillSleep while %@ — DELAYING ack up to %.0fs so alarm can play",
                  state.rawValue, WakeObserver.maxDelaySeconds)

            me.lock.lock()
            me.pendingSleepArg = arg

            // Cancel any previous timer (shouldn't happen but defensive).
            me.pendingAcknowledgeTimer?.cancel()

            // Schedule the worst-case acknowledge — we MUST call
            // IOAllowPowerChange within 30 s or the kernel stalls.
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
            timer.schedule(deadline: .now() + WakeObserver.maxDelaySeconds)
            timer.setEventHandler { [weak me] in
                me?.acknowledgePendingSleep(reason: "delay timeout")
            }
            timer.resume()
            me.pendingAcknowledgeTimer = timer
            me.lock.unlock()

            // If we're still in .armed (lid hasn't been detected yet —
            // possible if WillSleep arrives before the clamshell
            // notification), force the alarm trigger so the audio fires
            // before the limited window expires.
            if state == .armed {
                NSLog("[WakeObserver] state was .armed (no trigger fired yet) — injecting .lidClosed")
                me.emit?(.lidClosed)
            }

        default:
            break
        }
    }

    deinit {
        acknowledgePendingSleep(reason: "deinit")
        if notifier != 0 { IODeregisterForSystemPower(&notifier) }
        if let notifyPort = notifyPort { IONotificationPortDestroy(notifyPort) }
        if rootPort != 0 { IOServiceClose(rootPort) }
    }
}
