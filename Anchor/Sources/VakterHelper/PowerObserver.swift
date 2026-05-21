import Foundation
import IOKit.ps
import VakterShared

/// Observes AC adapter connection state via IOPSGetProvidingPowerSourceType.
///
/// Emits `.powerConnected` / `.powerDisconnected` on transitions.
/// Reliability is very high; latency is essentially instant.
///
/// TODO(week-3): replace polling with IOPSNotificationCreateRunLoopSource
/// for an event-driven implementation. Polling at 1Hz is adequate for v1
/// (battery impact negligible).
final class PowerObserver: VakterSignalObserver {

    private var timer: DispatchSourceTimer?
    private var lastOnAC: Bool?

    func start(_ emit: @escaping (VakterSignal) -> Void) {
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now() + 1.0, repeating: 1.0)
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            let onAC = self.isOnAC()
            defer { self.lastOnAC = onAC }
            guard let prev = self.lastOnAC, prev != onAC else { return }
            emit(onAC ? .powerConnected : .powerDisconnected)
        }
        t.resume()
        timer = t
        NSLog("[PowerObserver] polling every 1s")
    }

    private func isOnAC() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else {
            return false
        }
        // "AC Power" when plugged; "Battery Power" otherwise.
        return type == kIOPSACPowerValue
    }

    deinit {
        timer?.cancel()
    }
}
