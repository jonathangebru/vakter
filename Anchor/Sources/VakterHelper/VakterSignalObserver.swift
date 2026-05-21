import Foundation
import VakterShared

/// Common interface for everything that produces `VakterSignal` values
/// (lid sensor, power, Bluetooth, hotkey, future: power button).
///
/// Observers own their own lifetime. They're started once at daemon launch
/// and run until the process exits.
protocol VakterSignalObserver: AnyObject {
    /// Begin emitting signals. The handler may be invoked from any thread.
    func start(_ emit: @escaping (VakterSignal) -> Void)
}

/// Optional add-on protocol for observers whose work should only run
/// while Vakter is `.armed`. The state machine calls `resume()` on
/// each arm transition and `pause()` on each disarm.
///
/// Why arm-gate? Some observers — notably `FindMyTokenWatcher` and
/// `AppleIDChangeWatcher` — shell out to a subprocess on every tick.
/// Polling `nvram` every 30 s while unarmed would waste battery and
/// CPU for no benefit (no alarm path is even watching the signal).
protocol ArmGatedObserver: AnyObject {
    /// Vakter just entered `.armed`. Start polling / scanning.
    func resume()
    /// Vakter just left `.armed`. Stop polling / scanning.
    func pause()
}
